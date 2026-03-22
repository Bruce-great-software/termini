import 'package:flutter/material.dart';

void showAppSnackBar(BuildContext context, SnackBar snackBar) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: snackBar.content,
        duration: const Duration(milliseconds: 500),
      ),
    );
}
