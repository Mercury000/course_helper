import 'package:flutter/material.dart';

import '../../../models/active.dart';

/// 课程活动卡片，课程内容页与「未归类签到」页共用
class ActiveCard extends StatelessWidget {
  final Active active;
  final VoidCallback onTap;

  const ActiveCard({
    super.key,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            active.getIcon(),
            color: active.status
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
            size: 35,
          ),
        ),
        title: Text(
          active.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              active.description.isEmpty ? '手动结束' : active.description,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            if (active.attendNum > 0)
              Text(
                '参与人数：${active.attendNum}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
