import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../widgets/logo_background.dart';

class DocumentScreen extends StatelessWidget {
  final String title;
  final String content;

  const DocumentScreen({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.headerGradient,
          ),
        ),
      ),
      body: LogoBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            content,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
