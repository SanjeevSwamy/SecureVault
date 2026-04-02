import 'package:flutter/material.dart';

/// App-wide RouteObserver. Register it in MaterialApp.navigatorObservers,
/// then mix RouteAware into any widget that needs to react to route changes.
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();