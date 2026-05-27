import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

class HtmlMessageView extends StatelessWidget {
  const HtmlMessageView({super.key, required this.html});

  final String html;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: HtmlWidget(
        html,
        textStyle: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
