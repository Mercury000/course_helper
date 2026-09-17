import 'package:flutter/material.dart';

import '../../api/course.dart';
import '../../models/active.dart';
import 'list.dart';
import 'settings.dart';
import 'widget/active_card.dart';
import '../../platform.dart';


class CourseContentPage extends StatefulWidget {
  final String courseId;
  final String courseName;
  final String classId;
  final String cpi;

  const CourseContentPage({
    super.key,
    required this.courseId,
    required this.courseName,
    required this.classId,
    required this.cpi,
  });

  @override
  State<CourseContentPage> createState() => _CourseContentPageState();
}

class _CourseContentPageState extends State<CourseContentPage> {
  List<Active> _activeList = [];
  bool _isContentLoading = false;
  late CXCourseApi _courseApi;

  @override
  void initState() {
    super.initState();
    _courseApi = CXCourseApi();
    _loadCourseContent();
  }

  Future<void> _loadCourseContent({bool refresh = false}) async {
    setState(() {
      _isContentLoading = true;
    });

    try {
      final List<Active>? contentList = await _courseApi.getActiveList(
        widget.courseId,
        widget.classId,
        widget.cpi,
        refreshSchedule: refresh,
        courseName: widget.courseName,
      );

      if (contentList != null) {
        setState(() {
          _activeList = contentList;
          _isContentLoading = false;
        });
      } else {
        setState(() {
          _activeList = [];
          _isContentLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('获取内容列表失败')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _activeList = [];
        _isContentLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取内容列表时发生错误：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.courseName),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CourseSettingsPage(
                    courseId: widget.courseId
                  ),
                ),
              );
            },
            tooltip: '课程设置'
          ),
        ],
      ),
      body: _isContentLoading
          ? const Center(child: CircularProgressIndicator())
          : _activeList.isEmpty
          ? Center(
        child: Text(
          '暂无内容',
          style: const TextStyle(fontSize: 18, color: Colors.grey)
        ),
      )
          : RefreshIndicator(
        onRefresh: () => _loadCourseContent(refresh: true),
        child: ListView.builder(
          itemCount: _activeList.length,
          itemBuilder: (context, index) {
            final active = _activeList[index];
            return ActiveCard(
              active: active,
              onTap: () {
                CoursesPage.navigateToActive(
                  context,
                  active,
                  widget.courseId,
                  widget.classId,
                  widget.cpi,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
