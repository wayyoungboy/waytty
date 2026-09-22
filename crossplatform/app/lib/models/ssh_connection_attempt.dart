import 'dart:async';

import 'ssh_credentials.dart';

/// Lifetime of one interactive attempt, including queued credential dialogs.
class SshConnectionAttempt {
  bool _cancelled = false;
  final _listeners = <void Function()>{};
  bool get isCancelled => _cancelled;

  void check() {
    if (_cancelled) throw const AuthenticationCancelled();
  }

  void addCancelListener(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeCancelListener(void Function() listener) =>
      _listeners.remove(listener);

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  /// Stop waiting immediately; dispose resources returned by a late dial.
  Future<T> wait<T>(Future<T> future, {void Function(T)? onLateResult}) {
    final result = Completer<T>();
    void cancelWait() => result.completeError(const AuthenticationCancelled());
    addCancelListener(cancelWait);
    future.then(
      (value) {
        removeCancelListener(cancelWait);
        if (result.isCompleted) {
          onLateResult?.call(value);
        } else {
          result.complete(value);
        }
      },
      onError: (Object error, StackTrace stack) {
        removeCancelListener(cancelWait);
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future;
  }
}
