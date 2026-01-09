import 'package:flutter/widgets.dart';

import 'auth_state.dart';

class AuthScope extends InheritedNotifier<AuthState> {
  const AuthScope({
    super.key,
    required AuthState authState,
    required super.child,
  }) : super(notifier: authState);

  static AuthState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope not found in widget tree');
    return scope!.notifier!;
  }
}
