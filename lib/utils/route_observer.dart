import 'package:flutter/widgets.dart';

/// Global route observer used for lifecycle hooks like `RouteAware`.
///
/// Keeps navigation-related side effects (e.g. dismissing keyboard on return)
/// localized to widgets without wiring callbacks through every navigator call.
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();
