import 'package:flutter/widgets.dart';

void runAfterBuild(VoidCallback callback) {
  WidgetsBinding.instance.addPostFrameCallback((_) => callback());
}