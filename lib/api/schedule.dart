import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import '../models/active.dart';
import '../platform.dart';

/// 学习通「考勤」应用（kb.chaoxing.com）按周次生成的签到活动。
/// 项目现有的课程活动列表（taskactivelist / activelist）不一定覆盖这些活动。
class CXScheduleApi extends Api {
  CXScheduleApi([super.user]);

  static const _appId = '1829762';
  static const _mAppId = '19542161';

  /// fid / mappIdEnc 是账号（学校）级的，实测稳定
  static const _ctxTtl = Duration(hours: 12);

  /// 签到活动是分钟级的
  static const _itemsTtl = Duration(minutes: 2);

  /// 失败后的冷却，避免上层频繁刷新时反复打接口
  static const _failureCooldown = Duration(minutes: 1);

  static final Map<String, _ScheduleContext> _ctxCache = {};
  static final Map<String, _ScheduleItems> _itemsCache = {};
  static final Map<String, DateTime> _failureAt = {};

  static void clearCache([String? uid]) {
    if (uid == null) {
      _ctxCache.clear();
      _itemsCache.clear();
      _failureAt.clear();
    } else {
      _ctxCache.remove(uid);
      _itemsCache.remove(uid);
      _failureAt.remove(uid);
    }
  }

  /// 获取本周课表签到。任何一步失败都返回空列表，不影响调用方的原有数据。
  Future<List<Active>> fetchWeekScheduleActives({bool refresh = false}) async {
    if (!PlatformManager().isChaoxing || user == null) return [];

    final uid = user!.uid;
    final now = DateTime.now();

    if (!refresh) {
      final cached = _itemsCache[uid];
      if (cached != null && now.difference(cached.fetchedAt) < _itemsTtl) {
        return cached.actives;
      }
      final failedAt = _failureAt[uid];
      if (failedAt != null && now.difference(failedAt) < _failureCooldown) {
        return [];
      }
    }

    try {
      final actives = await _fetch(uid);
      if (actives == null) {
        _failureAt[uid] = DateTime.now();
        return [];
      }
      _failureAt.remove(uid);
      _itemsCache[uid] = _ScheduleItems(actives, DateTime.now());
      return actives;
    } catch (e, stackTrace) {
      debugPrint('课表签到获取失败: $e\n$stackTrace');
      _failureAt[uid] = DateTime.now();
      return [];
    }
  }

  /// 返回 null 表示失败
  Future<List<Active>?> _fetch(String uid) async {
    final context = await _getContext(uid);
    if (context == null) {
      debugPrint('课表签到：获取 fid/mappIdEnc 失败');
      return null;
    }

    final lessonsData = await _getLessons(context, uid);
    if (lessonsData == null) {
      debugPrint('课表签到：getMyLessons 失败');
      return null;
    }

    final curriculum =
        _asMap(lessonsData['curriculum']) ?? const <String, dynamic>{};
    final lessons = lessonsData['lessonArray'] as List? ?? [];
    if (lessons.isEmpty) {
      debugPrint('课表签到：课表为空');
      return null;
    }

    final weeks = _asInt(curriculum['realCurrentWeek'] ?? curriculum['currentWeek']);
    final schoolYear = '${curriculum['schoolYear'] ?? ''}';
    final semester = _asInt(curriculum['semester']);
    if (weeks <= 0 || schoolYear.isEmpty) {
      debugPrint('课表签到：周次/学年异常 weeks=$weeks schoolYear=$schoolYear');
      return null;
    }

    final classNos = <String>[];
    for (final lesson in lessons) {
      final no = _asMap(lesson)?['classNo'];
      if (no is String && no.isNotEmpty && !classNos.contains(no)) {
        classNos.add(no);
      }
    }
    if (classNos.isEmpty) {
      debugPrint('课表签到：未取到 classNo');
      return null;
    }

    // 接口要求带上本周的周一/周日，由第一周日期推算
    final monday = _weekMonday(curriculum['firstWeekDate'], weeks);
    final payload = await _getWeekSigns(
        context, uid, schoolYear, semester, weeks, classNos, monday);
    if (payload == null) return null;

    final actives = _buildActives(payload, lessons);
    debugPrint('课表签到：本周 ${actives.length} 条（课表 ${lessons.length} 节）');
    return actives;
  }

  /// 换取课表页地址，从中取出 fid（appFid）和 mappIdEnc。
  ///
  /// 不用 getTallyInfo：该接口对部分账号恒返回 status:false，
  /// 而 getAppInfo 允许全部参数为空并由服务端补齐。
  Future<_ScheduleContext?> _getContext(String uid) async {
    final cached = _ctxCache[uid];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _ctxTtl) {
      return cached;
    }

    final response = await ApiService.sendRequest(
      'https://uc.chaoxing.com/mobileSet/getAppInfo',
      params: {
        'id': _appId,
        'mAppId': _mAppId,
        'roleId': '',
        'deptId': '',
        'fid': '',
        'time': '',
        'enc': '',
      },
      userId: uid,
    );

    final data = _asMap(response?.data);
    if (data == null || data['status'] != true) {
      debugPrint('课表签到：getAppInfo 返回异常 ${response?.data}');
      return null;
    }

    final fid = data['appFid']?.toString() ?? '';
    if (fid.isEmpty) return null;

    // 形如 https://uc.chaoxing.com/mobile/openApp?code=<base64>&enc=...
    // 课表页面地址（含 mappIdEnc）在 code 参数里
    final url = data['url'];
    if (url is! String || url.isEmpty) return null;
    final code = Uri.tryParse(url)?.queryParameters['code'];
    if (code == null || code.isEmpty) return null;

    String mappIdEnc;
    try {
      final decoded = utf8.decode(base64.decode(code));
      final value = Uri.parse(decoded).queryParameters['mappIdEnc'];
      if (value == null || value.isEmpty) {
        debugPrint('课表签到：课表地址中未找到 mappIdEnc');
        return null;
      }
      mappIdEnc = value;
    } catch (e) {
      debugPrint('课表签到：解析 mappIdEnc 失败 $e');
      return null;
    }

    final context = _ScheduleContext(fid, mappIdEnc, DateTime.now());
    _ctxCache[uid] = context;
    return context;
  }

  /// 课表：给出 schoolYear / semester / 周次 / 第一周日期 和每节课的 classNo
  Future<Map<String, dynamic>?> _getLessons(
      _ScheduleContext context, String uid) async {
    final response = await ApiService.sendRequest(
      'https://kb.chaoxing.com/curriculum/getMyLessons',
      params: {
        'mappId': _mAppId,
        'mappIdEnc': context.mappIdEnc,
        'fid': context.fid,
        'curTime': DateTime.now().millisecondsSinceEpoch.toString(),
        'onlyJwKb': '1',
      },
      userId: uid,
    );

    final data = _asMap(response?.data);
    if (data == null || data['result'] != 1) return null;
    return _asMap(data['data']);
  }

  /// 本周签到活动 + 本人已签记录
  ///
  /// 该接口只经 noteyd 代理可用（直连 mobilelearn 会 500），
  /// 且必须带 mondayOfDate / sundayOfDate。
  Future<_SignPayload?> _getWeekSigns(
      _ScheduleContext context,
      String uid,
      String schoolYear,
      int semester,
      int weeks,
      List<String> classNos,
      DateTime monday) async {
    final sunday = monday.add(const Duration(days: 6));
    final innerPath = '/widget/attendanceSign/getStudentSignByWeekAllSign'
        '?fid=${context.fid}'
        '&schoolYear=$schoolYear'
        '&semester=$semester'
        '&weeks=$weeks'
        '&classNos=${classNos.join(',')}'
        '&mondayOfDate=${_monthDay(monday)}'
        '&sundayOfDate=${_monthDay(sunday)}'
        '&DB_STRATEGY=DEFAULT';

    // proxy_url 需要双重 URL 编码，这里手工拼好整条 URL，避免被再次编码
    final proxyUrl = 'https://noteyd.chaoxing.com/proxy/apis/proxy/proxyApiReq'
        '?proxy_url=${Uri.encodeComponent(Uri.encodeComponent(innerPath))}'
        '&uuid=mobilelearn_getStudentSignByWeekAllSign'
        '&proxy_returnFormat=json'
        '&crossOrigin=true';

    final response = await ApiService.sendRequest(
      proxyUrl,
      receiveTimeoutSeconds: 20,
      userId: uid,
    );

    final body = _asMap(response?.data);
    if (body == null || body['result'] != 1) return null;

    final wrapper = _asMap(body['data']);
    if (wrapper == null) return null;
    if (wrapper['result'] != 1) {
      debugPrint('课表签到：${wrapper['errorMsg'] ?? wrapper['msg']}');
      return null;
    }

    final data = _asMap(wrapper['data']);
    if (data == null) return null;

    final signedIds = <String>{};
    for (final item in data['userAttendListOfClass'] as List? ?? []) {
      final activeId = _asMap(item)?['activeId']?.toString();
      if (activeId != null) signedIds.add(activeId);
    }

    // 两个互补来源：
    //   listOfClass = 与课程关联的签到（带数字 courseId/classId）
    //   list        = 教务课自动发放的签到（只有 courseNo/classNo，按班级号筛出本班的）
    final listOfClass = data['listOfClass'] as List?;
    if (listOfClass == null) return null;

    final classNoSet = classNos.toSet();
    final classItems = (data['list'] as List? ?? []).where((raw) {
      final classNo = _asMap(raw)?['classNo']?.toString();
      return classNo != null && classNoSet.contains(classNo);
    }).toList();

    return _SignPayload(listOfClass, classItems, signedIds);
  }

  List<Active> _buildActives(_SignPayload payload, List lessons) {
    final lessonByClassId = <String, Map<String, dynamic>>{};
    final lessonByClassNo = <String, Map<String, dynamic>>{};
    for (final lesson in lessons) {
      final map = _asMap(lesson);
      if (map == null) continue;
      final classId = map['classId']?.toString() ?? '';
      final classNo = map['classNo']?.toString() ?? '';
      if (classId.isNotEmpty) lessonByClassId[classId] = map;
      if (classNo.isNotEmpty) lessonByClassNo[classNo] = map;
    }

    // listOfClass 优先：它带数字 ID，能直接关联到项目课程
    final actives = <Active>[];
    final seen = <String>{};

    for (final raw in payload.listOfClass) {
      final item = _asMap(raw);
      if (item == null) continue;

      final activeId = item['id']?.toString() ?? '';
      if (activeId.isEmpty || !seen.add(activeId)) continue;

      final appUrl = item['appUrl']?.toString() ?? '';
      final query =
          Uri.tryParse(appUrl)?.queryParameters ?? const <String, String>{};
      final classId = query['classId'] ?? item['clazzid']?.toString() ?? '';
      final courseId = query['courseId'] ?? '';
      final lesson = lessonByClassId[classId];

      actives.add(_toActive(
        activeId: activeId,
        appUrl: appUrl,
        courseId: courseId,
        classId: classId,
        lesson: lesson,
        // signTypeIndexMap 只有 0/2/3/4/5，未知取值必须兜底（getSignTypeFromIndex 是非空断言）
        signType: signTypeIndexMap.containsKey(_asInt(item['otherId']))
            ? getSignTypeFromIndex(_asInt(item['otherId']))
            : SignType.normal,
        startMs: _asInt(item['starttime']),
        endMs: _asInt(item['endtime']),
        startStr: item['starttimeStr']?.toString(),
        endStr: item['endtimeStr']?.toString(),
        signed: payload.signedIds.contains(activeId),
      ));
    }

    // 教务课签到：无数字 ID，靠 classNo 找到课表条目，再借课程名关联项目课程
    for (final raw in payload.listOfClassExtra) {
      final item = _asMap(raw);
      if (item == null) continue;

      final activeId = item['activeId']?.toString() ?? '';
      if (activeId.isEmpty || !seen.add(activeId)) continue;

      final classNo = item['classNo']?.toString() ?? '';
      final lesson = lessonByClassNo[classNo];
      final content = _asMap(_tryDecodeJson(item['content']));

      actives.add(_toActive(
        activeId: activeId,
        appUrl: item['appUrl']?.toString() ?? '',
        courseId: '',
        classId: '',
        lesson: lesson,
        // 教务课签到不返回 otherId，按是否开启地址推断
        signType: _asInt(content?['ifopenAddress']) == 1
            ? SignType.location
            : SignType.normal,
        startMs: _parseTime(item['startTime']),
        endMs: _parseTime(item['endTime']),
        startStr: item['startTime']?.toString(),
        endStr: item['endTime']?.toString(),
        signed: payload.signedIds.contains(activeId),
      ));
    }

    return actives;
  }

  Active _toActive({
    required String activeId,
    required String appUrl,
    required String courseId,
    required String classId,
    required Map<String, dynamic>? lesson,
    required SignType signType,
    required int startMs,
    required int endMs,
    required String? startStr,
    required String? endStr,
    required bool signed,
  }) {
    // 教务课签到没有数字 ID，用课程名兜底关联项目课程
    final courseName = lesson?['name']?.toString() ?? '';
    final location = lesson?['location']?.toString() ?? '';
    final timeRange = _timeRange(startStr, endStr);

    final description = [
      if (location.isNotEmpty) location,
      if (timeRange.isNotEmpty) timeRange,
      if (signed) '已签到',
    ].join(' · ');

    return Active(
      type: ActiveType.signIn.value,
      id: activeId,
      name: courseName.isNotEmpty ? courseName : '课表签到',
      description: description,
      startTime: startMs,
      url: appUrl,
      attendNum: 0,
      // 接口返回的 status 语义未知，按结束时间自行判断
      status: endMs <= 0 || DateTime.now().millisecondsSinceEpoch < endMs,
      signType: signType,
      extras: {
        'schedule': true,
        'signed': signed,
        'courseId': courseId,
        'classId': classId,
        'courseName': courseName,
      },
    );
  }
}

class _ScheduleContext {
  final String fid;
  final String mappIdEnc;
  final DateTime fetchedAt;

  _ScheduleContext(this.fid, this.mappIdEnc, this.fetchedAt);
}

class _ScheduleItems {
  final List<Active> actives;
  final DateTime fetchedAt;

  _ScheduleItems(this.actives, this.fetchedAt);
}

class _SignPayload {
  final List<dynamic> listOfClass;

  /// list 里筛出的本班教务课签到
  final List<dynamic> listOfClassExtra;
  final Set<String> signedIds;

  _SignPayload(this.listOfClass, this.listOfClassExtra, this.signedIds);
}

Map<String, dynamic>? _asMap(dynamic value) =>
    value is Map ? value.cast<String, dynamic>() : null;

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

dynamic _tryDecodeJson(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  try {
    return jsonDecode(value);
  } catch (_) {
    return null;
  }
}

/// "2026-09-15 15:28:55" -> 毫秒时间戳
int _parseTime(dynamic value) {
  if (value == null) return 0;
  final text = value.toString();
  final parsed = DateTime.tryParse(text);
  return parsed?.millisecondsSinceEpoch ?? 0;
}

/// 第一周日期所在周的周一，再推 (weeks - 1) 周
DateTime _weekMonday(dynamic firstWeekDate, int weeks) {
  DateTime start;
  final ms = _asInt(firstWeekDate);
  if (ms > 0) {
    start = DateTime.fromMillisecondsSinceEpoch(ms);
  } else {
    // 兜底：本周
    final today = DateTime.now();
    start = today.subtract(Duration(days: today.weekday - DateTime.monday));
  }
  final monday = DateTime(start.year, start.month, start.day)
      .subtract(Duration(days: start.weekday - DateTime.monday));
  return monday.add(Duration(days: (weeks - 1) * 7));
}

String _monthDay(DateTime date) =>
    '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// "2026-09-15 07:50:38" + "2026-09-15 08:03:38" -> "07:50-08:03"
String _timeRange(String? start, String? end) {
  String hm(String? value) {
    if (value == null || value.length < 16) return '';
    return value.substring(11, 16);
  }

  final from = hm(start);
  final to = hm(end);
  if (from.isEmpty) return '';
  return to.isEmpty ? from : '$from-$to';
}
