package com.thangnm.yourssh

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** USB permission belongs to Android; live handles and writes belong to one
 * session token. No background reconnection or queued command replay. */
class SerialChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val manager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val main = Handler(Looper.getMainLooper())
    private val control = Executors.newSingleThreadExecutor()
    private val methods = MethodChannel(messenger, "waytty/serial")
    private val events = EventChannel(messenger, "waytty/serial/events")
    private var sink: EventChannel.EventSink? = null
    private val handles = ConcurrentHashMap<String, Handle>()
    private val permissionAction = context.packageName + ".SERIAL_PERMISSION." + UUID.randomUUID()
    private var pending: Opening? = null // Accessed on the main thread only.
    private val openings = ConcurrentHashMap<String, Opening>()
    @Volatile private var disposed = false
    @Volatile private var epoch = 0

    private data class Opening(val device: UsbDevice, val call: MethodCall,
        val result: MethodChannel.Result, val epoch: Int,
        val cancelled: AtomicBoolean = AtomicBoolean(false))
    private class Handle(val id: String, val port: UsbSerialPort) {
        val closed = AtomicBoolean(false)
        val started = AtomicBoolean(false)
        val readCredit = Semaphore(1)
        val writes = Executors.newSingleThreadExecutor()
        fun close() {
            if (!closed.compareAndSet(false, true)) return
            writes.shutdown()
            readCredit.release()
            try { port.setBreak(false) } catch (_: Exception) { }
            try { port.close() } catch (_: Exception) { }
        }
    }

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != permissionAction) return
            val open = pending ?: return
            pending = null
            if (!manager.hasPermission(open.device)) {
                openings.remove(open.call.argument<String>("id"), open)
                fail(open.result, "USB permission denied")
            }
            else doOpen(open)
        }
    }

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(permissionReceiver,
            IntentFilter(permissionAction), Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") context.registerReceiver(permissionReceiver, IntentFilter(permissionAction))
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    private fun fail(result: MethodChannel.Result, message: String) =
        main.post { result.error("serial", message, null) }
    private fun emit(token: String, data: ByteArray? = null, error: String? = null) {
        main.post {
            if (!disposed) sink?.success(mapOf("token" to token, "data" to data, "error" to error))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) { result.error("serial", "Serial channel closed", null); return }
        try {
            when (call.method) {
                "list" -> {
                    if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)) {
                        result.error("serial", "USB Host is not supported", null); return
                    }
                    val devices = UsbSerialProber.getDefaultProber().findAllDrivers(manager)
                    result.success(devices.flatMap { driver -> driver.ports.map { port ->
                        val d = driver.device
                        mapOf("id" to "${d.deviceId}:${port.portNumber}", "path" to d.deviceName,
                            "label" to "${d.productName ?: "USB Serial"} · ${port.portNumber}",
                            "vendorId" to d.vendorId, "productId" to d.productId,
                            "serialNumber" to if (manager.hasPermission(d)) d.serialNumber else null,
                            "portIndex" to port.portNumber)
                    } })
                }
                "open" -> requestOpen(call, result)
                "ack" -> {
                    handles[call.argument<String>("token")]?.readCredit?.release()
                    result.success(null)
                }
                "cancelOpen" -> {
                    val id = call.argument<String>("id") ?: ""
                    openings[id]?.let { opening ->
                        opening.cancelled.set(true)
                        if (pending === opening) {
                            pending = null; openings.remove(id, opening)
                            fail(opening.result, "Serial opening cancelled")
                        }
                    }
                    result.success(null)
                }
                "close" -> {
                    val token = call.argument<String>("token") ?: ""
                    val handle = handles.remove(token)
                    control.execute { handle?.close(); main.post { result.success(null) } }
                }
                "start", "write", "signal" -> {
                    val token = call.argument<String>("token") ?: ""
                    val handle = handles[token] ?: throw IllegalStateException("Serial session closed")
                    if (call.method == "start") {
                        startReader(token, handle); result.success(null)
                    } else handle.writes.execute {
                        try {
                            check(!handle.closed.get()) { "Serial session closed" }
                            if (call.method == "write") {
                                val bytes = call.argument<ByteArray>("bytes") ?: error("Missing bytes")
                                require(bytes.size <= 4096) { "Write too large" }
                                handle.port.write(bytes, 1000)
                                check(!handle.closed.get()) { "Write outcome unknown" }
                                main.post { result.success(bytes.size) }
                            } else {
                                val enabled = call.argument<Boolean>("enabled") == true
                                when (call.argument<String>("signal")) {
                                    "dtr" -> handle.port.setDTR(enabled)
                                    "rts" -> {
                                        check(handle.port.flowControl != UsbSerialPort.FlowControl.RTS_CTS)
                                        handle.port.setRTS(enabled)
                                    }
                                    "breakSignal" -> handle.port.setBreak(enabled)
                                    else -> error("Unknown signal")
                                }
                                main.post { result.success(null) }
                            }
                        } catch (e: Exception) { fail(result, e.message ?: "Serial operation failed") }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) { fail(result, e.message ?: "Serial operation failed") }
    }

    private fun requestOpen(call: MethodCall, result: MethodChannel.Result) {
        check(pending == null) { "USB permission request is already pending" }
        val id = call.argument<String>("id") ?: error("Missing device id")
        val deviceId = id.substringBefore(':').toInt()
        val device = manager.deviceList.values.firstOrNull { it.deviceId == deviceId }
            ?: error("Serial device disconnected")
        require(device.vendorId == call.argument<Int>("vendorId") &&
            device.productId == call.argument<Int>("productId")) { "Serial device changed" }
        val opening = Opening(device, call, result, epoch)
        check(openings.putIfAbsent(id, opening) == null) { "Serial port is busy" }
        if (manager.hasPermission(device)) { doOpen(opening); return }
        pending = opening
        try {
            // An immutable, package-scoped callback; permission is rechecked
            // with UsbManager rather than trusting intent extras.
            val callback = PendingIntent.getBroadcast(context, 0,
                Intent(permissionAction).setPackage(context.packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            manager.requestPermission(device, callback)
            main.postDelayed({
                if (pending === opening) {
                    pending = null; openings.remove(id, opening)
                    fail(result, "USB permission timed out")
                }
            }, 30000)
        } catch (e: Exception) { pending = null; openings.remove(id, opening); throw e }
    }

    private fun doOpen(opening: Opening) {
        control.execute {
            var port: UsbSerialPort? = null
            try {
                check(!disposed && !opening.cancelled.get() && opening.epoch == epoch) { "Serial opening cancelled" }
                val id = opening.call.argument<String>("id")!!
                check(handles.values.none { it.id == id && !it.closed.get() }) { "Serial port is busy" }
                val current = manager.deviceList.values.firstOrNull { it.deviceId == opening.device.deviceId }
                    ?: error("Serial device disconnected")
                check(manager.hasPermission(current)) { "USB permission denied" }
                val expectedSerial = opening.call.argument<String>("serialNumber")
                check(expectedSerial == null || expectedSerial == current.serialNumber) { "Serial device changed" }
                val driver = UsbSerialProber.getDefaultProber().probeDevice(current) ?: error("Unsupported USB serial device")
                port = driver.ports.firstOrNull { it.portNumber == id.substringAfter(':').toInt() }
                    ?: error("Serial port unavailable")
                check(!opening.cancelled.get() && opening.epoch == epoch) { "Serial opening cancelled" }
                val connection = manager.openDevice(current) ?: error("Cannot open USB device")
                try { port.open(connection) } catch (e: Exception) { connection.close(); throw e }
                val baud = opening.call.argument<Int>("baudRate") ?: 0
                val bits = opening.call.argument<Int>("dataBits") ?: 0
                val stop = opening.call.argument<Int>("stopBits") ?: 0
                require(baud in 1..4000000 && bits in 5..8 && stop in 1..2)
                val parity = when (opening.call.argument<String>("parity")) {
                    "none" -> UsbSerialPort.PARITY_NONE; "odd" -> UsbSerialPort.PARITY_ODD
                    "even" -> UsbSerialPort.PARITY_EVEN; else -> error("Unsupported parity")
                }
                val flow = when (opening.call.argument<String>("flowControl")) {
                    "none" -> UsbSerialPort.FlowControl.NONE
                    "rtsCts" -> UsbSerialPort.FlowControl.RTS_CTS
                    "xonXoff" -> UsbSerialPort.FlowControl.XON_XOFF
                    else -> error("Unsupported flow control")
                }
                require(port.supportedFlowControl.contains(flow)) { "Flow control is not supported by this device" }
                port.setParameters(baud, bits, stop, parity)
                port.flowControl = flow
                if (port.supportedControlLines.contains(UsbSerialPort.ControlLine.DTR)) port.setDTR(false)
                if (flow != UsbSerialPort.FlowControl.RTS_CTS &&
                    port.supportedControlLines.contains(UsbSerialPort.ControlLine.RTS)) port.setRTS(false)
                val token = UUID.randomUUID().toString()
                val handle = Handle(id, port)
                handles[token] = handle
                main.post {
                    openings.remove(id, opening)
                    if (disposed || opening.cancelled.get() || opening.epoch != epoch) {
                        handles.remove(token, handle)
                        Thread({ handle.close() }, "waytty-serial-close").start()
                        fail(opening.result, "Serial opening cancelled")
                    } else {
                        opening.result.success(token)
                    }
                }
            } catch (e: Exception) {
                openings.remove(opening.call.argument<String>("id"), opening)
                try { port?.close() } catch (_: Exception) { }
                fail(opening.result, e.message ?: "Cannot open serial port")
            }
        }
    }

    private fun startReader(token: String, handle: Handle) {
        if (!handle.started.compareAndSet(false, true)) return
        Thread({
            val buffer = ByteArray(8192)
            try {
                while (!handle.closed.get()) {
                    if (!handle.readCredit.tryAcquire(250, TimeUnit.MILLISECONDS)) continue
                    if (handle.closed.get()) break
                    val count = handle.port.read(buffer, 200)
                    if (count > 0) emit(token, data = buffer.copyOf(count))
                    else handle.readCredit.release()
                }
            } catch (e: Exception) {
                if (!handle.closed.get()) emit(token, error = e.message ?: "Serial device disconnected")
            } finally { handles.remove(token, handle); handle.close() }
        }, "waytty-serial-rx").start()
    }

    fun suspendConnections() {
        epoch++
        for (opening in openings.values) opening.cancelled.set(true)
        pending?.let {
            openings.remove(it.call.argument<String>("id"), it)
            fail(it.result, "Serial opening cancelled")
        }
        pending = null
        for ((token, handle) in handles) {
            emit(token, error = "Serial connection closed while app is in background")
            handles.remove(token, handle)
            control.execute { handle.close() }
        }
    }

    fun dispose() {
        if (disposed) return
        suspendConnections()
        disposed = true
        context.unregisterReceiver(permissionReceiver)
        methods.setMethodCallHandler(null); events.setStreamHandler(null); sink = null
        // Open operations finish their cleanup on this queue before shutdown.
        control.shutdown()
    }
}
