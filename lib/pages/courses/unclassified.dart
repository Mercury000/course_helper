import 'package:flutter/material.dart';

import '../../models/active.dart';
import 'list.dart';
import 'widget/active_card.dart';

/// 匹配不到项目课程条目的课表签到
class UnclassifiedActivesPage extends StatelessWidget {
  final List<Active> actives;

  const UnclassifiedActivesPage({super.key, required this.actives});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('未归类签到'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        itemCount: actives.length,
        itemBuilder: (context, index) {
          final active = actives[index];
          return ActiveCard(
            active: active,
            onTap: () {
              CoursesPage.navigateToActive(
                context,
                active,
                active.extras?['courseId']?.toString() ?? '',
                active.extras?['classId']?.toString() ?? '',
                '',
              );
            },
          );
        },
      ),
    );
  }
}
