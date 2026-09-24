cmake_minimum_required(VERSION 3.14)
project(qjsbridge C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)

set(QJS_SOURCES
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs/quickjs.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs/libunicode.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs/libregexp.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs/cutils.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs/libbf.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/bridge/qjs_bridge.c"
)

add_library(qjsbridge SHARED ${QJS_SOURCES})
target_include_directories(qjsbridge PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs"
  "${CMAKE_CURRENT_SOURCE_DIR}/bridge"
)
target_compile_definitions(qjsbridge PRIVATE
  CONFIG_VERSION="2024-01-13"
  CONFIG_BIGNUM
  _CRT_SECURE_NO_WARNINGS
)

# Plain MSVC cl.exe cannot compile QuickJS/libbf; ClangCL (clang + MSVC SDK) can.
if(MSVC AND CMAKE_C_COMPILER_ID STREQUAL "MSVC")
  message(FATAL_ERROR
    "MSVC cl.exe cannot compile QuickJS/libbf cleanly. Use native/build_windows.ps1 with -T ClangCL.")
endif()

# Quiet a few noisy but harmless QuickJS warnings under clang-cl.
if(CMAKE_C_COMPILER_ID MATCHES "Clang")
  target_compile_options(qjsbridge PRIVATE -Wno-unused-parameter -Wno-sign-compare)
endif()
