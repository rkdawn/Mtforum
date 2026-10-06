import 'package:flutter/material.dart';

class ThreadTitleHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onLongPress;

  const ThreadTitleHeader({
    super.key,
    required this.title,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Semantics(
        header: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: onLongPress,
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
            softWrap: true,
            overflow: TextOverflow.visible,
          ),
        ),
      ),
    );
  }
}
