// Data layer for UniRide Verify: records, verification rules, reports.
// Records are JSON maps (one list per collection), ready to move to Cloud Firestore.
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef M = Map<String, dynamic>;
String two(int n) => n.toString().padLeft(2, '0');
String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String hm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${two(d.hour)}:${two(d.minute)}';
}
String dm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${hm(ms)}';
}
int nowMs() => DateTime.now().millisecondsSinceEpoch;

const defaultPassword = 'UniRide@2026'; // replace with Firebase Authentication in production
const studentStatuses = ['Active', 'Suspended', 'Inactive'];
const yearsOfStudy = ['1st year', '2nd year', '3rd year', '4th year', 'Advanced Diploma', 'Postgraduate'];
const authorised = 'Authorised', rejected = 'Not authorised', unable = 'Unable to verify';
/// Why a student qualifies for school transport (the administrator picks one when registering).
const qualBases = ['NSFAS funded', 'Lives off campus', 'Transport fee paid', 'Special approval'];
/// Default end of access: 15 December of this year (next year once December has started).
int defaultUntil() {
  final n = DateTime.now();
  return DateTime(n.month > 11 ? n.year + 1 : n.year, 12, 15, 23, 59).millisecondsSinceEpoch;
}

class Store extends ChangeNotifier {
  Store(this._p);
  final SharedPreferences _p;
  late M db;
  String? meId;
  int _n = 0;
  String id() => '${DateTime.now().microsecondsSinceEpoch}${_n++}';

  static Future<Store> open() async {
    final s = Store(await SharedPreferences.getInstance());
    final raw = s._p.getString('uniride_v4');
    if (raw != null) {
      try {
        s.db = jsonDecode(raw) as M;
        return s;
      } catch (_) {}
    }
    s._seed();
    return s;
  }

  void commit() {
    _p.setString('uniride_v4', jsonEncode(db));
    notifyListeners();
  }

  List<M> t(String k) => (db[k] as List).cast<M>();
  M? find(String k, String? i) => t(k).where((e) => e['id'] == i).firstOrNull;
  String nameOf(String k, String? i) => (find(k, i)?['name'] ?? find(k, i)?['label'] ?? '—') as String;
  M? get me => find('users', meId);
  bool get isAdmin => me?['role'] == 'admin';
  bool get isDriver => me?['role'] == 'driver';
  void audit(String action, String summary) => t('audit').add({'id': id(), 'actor': meId, 'action': action, 'summary': summary, 'ts': nowMs()});

  // ---------- account ----------
  String? signIn(String email, String password) {
    final u = t('users').where((x) => x['email'] == email.trim().toLowerCase()).firstOrNull;
    if (u == null || password != defaultPassword) return 'Incorrect email or password';
    if (u['active'] != true) return 'This account has been deactivated';
    meId = u['id'];
    commit();
    return null;
  }
  void signOut() { meId = null; commit(); }
  void reset() { meId = null; _seed(); }

  // ---------- trips (driver) ----------
  M? activeTrip(String? driverId) => t('trips').where((x) => x['driverId'] == driverId && x['status'] == 'Active').firstOrNull;
  List<M> scansOf(String tripId) => t('scans').where((x) => x['tripId'] == tripId).toList()..sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
  /// Newest scan of a trip that has a GPS position.
  M? lastLocated(String tripId) => scansOf(tripId).where((x) => x['lat'] != null).firstOrNull;
  bool expired(M st) { final u = st['validUntil']; return u is int && u < nowMs(); }
  bool hasAccess(M st) => st['status'] == 'Active' && !expired(st);
  int seatsOf(String tripId) => (find('vehicles', find('trips', tripId)?['vehicleId'])?['cap'] ?? 0) as int;
  int countOf(String tripId, String result) => t('scans').where((x) => x['tripId'] == tripId && x['result'] == result).length;

  String? startTrip() {
    final u = me!;
    final v = find('vehicles', u['vehicleId']), r = find('routes', u['routeId']);
    if (v == null || r == null) return 'No shuttle or route is assigned to you. Contact the administrator.';
    if (v['active'] != true || r['active'] != true) return 'Your assigned shuttle or route is inactive.';
    if (activeTrip(meId) != null) return 'You already have an active trip.';
    t('trips').add({'id': id(), 'routeId': r['id'], 'vehicleId': v['id'], 'driverId': meId, 'status': 'Active', 'startedAt': nowMs(), 'endedAt': null});
    audit('Trip started', '${r['name']} · ${v['label']}');
    commit();
    return null;
  }
  void endTrip(String tid) {
    final tr = find('trips', tid);
    if (tr == null) return;
    tr['status'] = 'Ended';
    tr['endedAt'] = nowMs();
    audit('Trip ended', nameOf('routes', tr['routeId']));
    commit();
  }

  /// Checks a scanned or typed card against the access list for this trip's route.
  M verify(String tid, String raw, {bool manual = false, double? lat, double? lng}) {
    final tr = find('trips', tid)!;
    final code = raw.trim().toUpperCase();
    final full = seatsOf(tid) > 0 && countOf(tid, authorised) >= seatsOf(tid);
    final st = t('students').where((s) => [s['card'], s['no'], s['barcode']].any((v) => v != null && v.toString().isNotEmpty && v.toString().toUpperCase() == code)).firstOrNull;
    String result, reason;
    if (code.isEmpty) {
      result = unable; reason = 'Card could not be read';
    } else if (st == null) {
      result = unable; reason = 'Card not found in the system';
    } else if (st['status'] != 'Active') {
      result = rejected; reason = 'Shuttle access is ${(st['status'] as String).toLowerCase()}';
    } else if (expired(st)) {
      result = rejected; reason = 'Access expired on ${ymd(DateTime.fromMillisecondsSinceEpoch(st['validUntil']))}';
    } else if (st['routeId'] != tr['routeId']) {
      result = rejected; reason = 'Not assigned to ${nameOf('routes', tr['routeId'])}';
    } else {
      final dup = t('scans').where((x) => x['tripId'] == tid && x['studentId'] == st['id'] && x['result'] == authorised).firstOrNull;
      if (dup != null) return {'result': authorised, 'reason': 'Already scanned at ${hm(dup['ts'])}', 'student': st, 'duplicate': true};
      result = authorised; reason = full ? 'Access confirmed (shuttle was already full)' : 'Access confirmed';
    }
    t('scans').add({'id': id(), 'tripId': tid, 'studentId': st?['id'], 'code': code, 'result': result, 'reason': reason, 'ts': nowMs(), 'by': meId,
      'method': manual ? 'Manual entry' : 'Scanned', 'reviewed': result == authorised, 'note': '', 'lat': lat, 'lng': lng});
    commit();
    return {'result': result, 'reason': reason, 'student': st, 'duplicate': false, 'over': result == authorised && full};
  }

  // ---------- administration ----------
  String? saveStudent({String? sid, required String name, required String no, required String programme, String? routeId, required String status, String note = '', String basis = 'Special approval', required int validUntil, String? photo, String year = '', String residence = '', String barcode = ''}) {
    if (name.trim().length < 3 || no.trim().length < 4) return 'Enter the student’s name and student number';
    if (programme.trim().isEmpty) return 'Enter the student’s course';
    if (residence.trim().length < 2) return 'Enter the residence or area where the student stays';
    if (routeId == null) return 'Select a route';
    if (t('students').any((s) => s['no'].toString().toLowerCase() == no.trim().toLowerCase() && s['id'] != sid)) return 'That student number is already registered';
    if (barcode.trim().isNotEmpty && t('students').any((s) => (s['barcode'] ?? '').toString().toLowerCase() == barcode.trim().toLowerCase() && s['id'] != sid)) return 'That card number belongs to another student';
    if (sid == null) {
      t('students').add({'id': id(), 'name': name.trim(), 'no': no.trim(), 'programme': programme.trim(), 'routeId': routeId, 'status': status, 'note': note, 'basis': basis, 'validUntil': validUntil, 'photo': photo, 'year': year, 'residence': residence.trim(), 'barcode': barcode.trim(), 'card': 'UR-${100000 + Random().nextInt(900000)}'});
      audit('Student registered', '${name.trim()} · $basis');
    } else {
      final s = find('students', sid)!;
      final changed = s['status'] != status;
      s..['name'] = name.trim()..['no'] = no.trim()..['programme'] = programme.trim()..['routeId'] = routeId..['status'] = status..['note'] = note..['basis'] = basis..['validUntil'] = validUntil..['photo'] = photo..['year'] = year..['residence'] = residence.trim()..['barcode'] = barcode.trim();
      audit(changed ? 'Access set to $status' : 'Student updated', '${name.trim()}${note.isEmpty ? '' : ': $note'}');
    }
    commit();
    return null;
  }

  /// Adds many qualifying students at once.
  /// One student per line: name, student number, course, year, residence, card barcode number (everything after the student number is optional).
  String importStudents(String raw, String routeId, String basis, int validUntil) {
    var added = 0;
    final skipped = <String>[];
    for (final line in raw.split('\n')) {
      final p = line.split(RegExp(r'[,;\t]')).map((e) => e.trim()).toList();
      if (p.length < 2 || p[0].isEmpty || p[0].toLowerCase() == 'name') continue;
      String at(int i) => p.length > i ? p[i] : '';
      final dup = t('students').any((x) => x['no'].toString().toLowerCase() == p[1].toLowerCase() || (at(5).isNotEmpty && (x['barcode'] ?? '').toString() == at(5)));
      if (p[0].length < 3 || p[1].length < 4 || dup) { skipped.add(p[1].isEmpty ? p[0] : p[1]); continue; }
      t('students').add({'id': id(), 'name': p[0], 'no': p[1], 'programme': at(2), 'year': at(3), 'residence': at(4), 'barcode': at(5), 'photo': null, 'routeId': routeId, 'status': 'Active', 'note': '', 'basis': basis, 'validUntil': validUntil, 'card': 'UR-${100000 + Random().nextInt(900000)}'});
      added++;
    }
    if (added > 0) { audit('Students imported', '$added added · $basis'); commit(); }
    return skipped.isEmpty ? '$added students added' : '$added added, ${skipped.length} skipped (duplicate or invalid): ${skipped.take(5).join(', ')}';
  }

  // ---------- notices (administrator to drivers) ----------
  List<M> get notices => t('notices').toList()..sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
  String? addNotice(String text) {
    if (text.trim().length < 5) return 'Write the notice first';
    t('notices').add({'id': id(), 'text': text.trim(), 'ts': nowMs(), 'by': meId});
    audit('Notice posted', text.trim());
    commit();
    return null;
  }
  void removeNotice(String nid) {
    t('notices').removeWhere((x) => x['id'] == nid);
    audit('Notice removed', '');
    commit();
  }

  /// Verification log as CSV text (opens in Excel), oldest first.
  String scansCsv(int days) {
    String q(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    final rows = ['Date,Time,Student,Student number,Course,Year,Residence,Result,Reason,Route,Driver,Method,Latitude,Longitude'];
    final list = scansIn(days)..sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
    for (final x in list) {
      final st = find('students', x['studentId']);
      rows.add([
        ymd(DateTime.fromMillisecondsSinceEpoch(x['ts'])),
        hm(x['ts']),
        st?['name'] ?? 'Unknown card ${x['code']}',
        st?['no'] ?? '',
        st?['programme'] ?? '',
        st?['year'] ?? '',
        st?['residence'] ?? '',
        x['result'],
        x['reason'],
        nameOf('routes', find('trips', x['tripId'])?['routeId']),
        nameOf('users', x['by']),
        x['method'],
        x['lat'] ?? '',
        x['lng'] ?? '',
      ].map(q).join(','));
    }
    return '\uFEFF${rows.join('\r\n')}';
  }

  String? addVehicle(String label, String reg, int? cap) {
    if (label.trim().isEmpty || reg.trim().isEmpty || cap == null || cap < 1) return 'Enter label, registration and seats';
    t('vehicles').add({'id': id(), 'label': label.trim(), 'reg': reg.trim(), 'cap': cap, 'active': true});
    audit('Vehicle added', reg.trim());
    commit();
    return null;
  }
  String? addRoute(String name, String stops) {
    if (name.trim().length < 3) return 'Enter a route name';
    t('routes').add({'id': id(), 'name': name.trim(), 'stops': stops.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(), 'active': true});
    audit('Route added', name.trim());
    commit();
    return null;
  }
  String? addDriver(String name, String email, String lang) {
    final em = email.trim().toLowerCase();
    if (name.trim().length < 3 || !em.contains('@')) return 'Enter the driver’s name and a valid email';
    if (t('users').any((u) => u['email'] == em)) return 'That email is already registered';
    t('users').add({'id': id(), 'name': name.trim(), 'email': em, 'role': 'driver', 'lang': lang, 'active': true, 'vehicleId': null, 'routeId': null});
    audit('Driver added', name.trim());
    commit();
    return null;
  }
  void assignDriver(String uid, String? vehicleId, String? routeId) {
    final u = find('users', uid)!;
    u['vehicleId'] = vehicleId;
    u['routeId'] = routeId;
    audit('Driver assigned', '${u['name']}: ${nameOf('vehicles', vehicleId)} · ${nameOf('routes', routeId)}');
    commit();
  }
  String? toggleActive(String k, String rid) {
    final r = find(k, rid);
    if (r == null) return 'Not found';
    if (k == 'users' && rid == meId) return 'You cannot deactivate your own account';
    r['active'] = r['active'] != true;
    audit(r['active'] == true ? 'Reactivated' : 'Deactivated', '$k: ${r['name'] ?? r['label']}');
    commit();
    return null;
  }
  void reviewScan(String sid, String note) {
    final s = find('scans', sid);
    if (s == null) return;
    s['reviewed'] = true;
    s['note'] = note.trim();
    audit('Exception reviewed', '${s['result']}: ${note.trim()}');
    commit();
  }

  // ---------- numbers for dashboards and reports ----------
  List<M> get exceptions => t('scans').where((s) => s['result'] != authorised).toList()..sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
  int get openExceptions => t('scans').where((s) => s['reviewed'] != true).length;
  int get scansToday => t('scans').where((s) => ymd(DateTime.fromMillisecondsSinceEpoch(s['ts'])) == ymd(DateTime.now())).length;
  List<M> scansIn(int days) {
    final from = DateTime.now().subtract(Duration(days: days - 1));
    final start = DateTime(from.year, from.month, from.day).millisecondsSinceEpoch;
    return t('scans').where((s) => (s['ts'] as int) >= start).toList();
  }
  List<double> dailyScans(int days) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    final a = List<double>.filled(days, 0);
    for (final s in t('scans')) {
      final d = DateTime.fromMillisecondsSinceEpoch(s['ts']);
      final i = DateTime(d.year, d.month, d.day).difference(start).inDays;
      if (i >= 0 && i < days) a[i]++;
    }
    return a;
  }

  // ---------- sample data (fictional names) ----------
  void _seed() {
    final r = Random(11);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    M user(String n, String e, String role, String lang, [int? v, int? ro]) => {'id': id(), 'name': n, 'email': e, 'role': role, 'lang': lang, 'active': true, 'vehicleId': null, 'routeId': null};
    final users = [user('Nomvula Khumalo', 'admin@uniride.demo', 'admin', 'Zulu'), user('Mahlatse Mathabatha', 'admin2@uniride.demo', 'admin', 'Sepedi'),
      user('Themba Ngubane', 'themba@uniride.demo', 'driver', 'Zulu'), user('Sizwe Ntshona', 'sizwe@uniride.demo', 'driver', 'Xhosa'), user('Kagiso Modise', 'kagiso@uniride.demo', 'driver', 'Setswana')];
    final routes = <M>[
      {'id': id(), 'name': 'Route 1: Mdantsane', 'stops': ['Mdantsane NU1', 'Mdantsane NU6', 'Potsdam Campus'], 'active': true},
      {'id': id(), 'name': 'Route 2: Duncan Village', 'stops': ['Duncan Village', 'Buffalo Flats', 'Potsdam Campus'], 'active': true},
      {'id': id(), 'name': 'Route 3: Beacon Bay', 'stops': ['Gonubie', 'Beacon Bay', 'Potsdam Campus'], 'active': true},
    ];
    final vehicles = <M>[
      {'id': id(), 'label': 'Shuttle 01', 'reg': 'EC 123-456', 'cap': 22, 'active': true},
      {'id': id(), 'label': 'Shuttle 02', 'reg': 'EC 789-012', 'cap': 22, 'active': true},
      {'id': id(), 'label': 'Shuttle 03', 'reg': 'EC 345-678', 'cap': 15, 'active': true},
      {'id': id(), 'label': 'Shuttle 04 (spare)', 'reg': 'EC 901-234', 'cap': 15, 'active': false},
    ];
    for (var i = 0; i < 3; i++) {
      users[2 + i]['vehicleId'] = vehicles[i]['id'];
      users[2 + i]['routeId'] = routes[i]['id'];
    }
    const prog = ['Dip. Information Technology', 'Dip. Accounting', 'B.Ed Foundation Phase', 'Dip. Public Management', 'Adv. Dip. Applications Development'];
    const raw = [('Lindiwe Mthembu', 0, 'Active'), ('Andile Mbeki', 0, 'Active'), ('Kgomotso Sebego', 1, 'Active'), ('Mahlatse Maleka', 1, 'Active'), ('Thandiwe Ngcobo', 2, 'Active'),
      ('Luyanda Gcaleka', 0, 'Active'), ('Boitumelo Modise', 1, 'Active'), ('Dikeledi Rakgoale', 2, 'Active'), ('Sipho Dlamini', 0, 'Suspended'), ('Nomonde Mqhayi', 2, 'Active'),
      ('Tshepo Molefe', 1, 'Inactive'), ('Ayanda Mkhize', 0, 'Active'), ('Palesa Mothibi', 2, 'Active'), ('Zodwa Ntuli', 1, 'Active')];
    const homes = ['Fourwinds', 'Panmure', 'Saris Court', 'Amajwara Guest House', 'Rose Alba', 'Alba', 'Bala'];
    final students = <M>[
      for (var i = 0; i < raw.length; i++)
        {'id': id(), 'name': raw[i].$1, 'no': '2026${30100 + i * 7}', 'programme': prog[i % prog.length], 'routeId': routes[raw[i].$2]['id'], 'status': raw[i].$3,
          'note': raw[i].$3 == 'Suspended' ? 'Outstanding transport fee' : '', 'basis': qualBases[i % qualBases.length],
          'validUntil': i == 11 ? today.subtract(const Duration(days: 2)).add(const Duration(hours: 23)).millisecondsSinceEpoch : defaultUntil(), 'year': yearsOfStudy[i % 4], 'residence': homes[i % homes.length], 'barcode': '', 'photo': null, 'card': 'UR-${200000 + i * 137}'}
    ];
    final trips = <M>[], scans = <M>[];
    void scan(M trip, M? st, String code, String result, String reason, int ts, bool reviewed, String by) =>
        scans.add({'id': id(), 'tripId': trip['id'], 'studentId': st?['id'], 'code': code, 'result': result, 'reason': reason, 'ts': ts, 'by': by, 'method': r.nextInt(10) == 0 ? 'Manual entry' : 'Scanned', 'reviewed': reviewed, 'note': reviewed && result != authorised ? 'Checked with student' : ''});
    for (var d = 6; d >= 1; d--) {
      final day = today.subtract(Duration(days: d));
      if (day.weekday == DateTime.sunday) continue;
      for (var ri = 0; ri < 3; ri++) {
        final tr = {'id': id(), 'routeId': routes[ri]['id'], 'vehicleId': vehicles[ri]['id'], 'driverId': users[2 + ri]['id'], 'status': 'Ended',
          'startedAt': day.add(Duration(hours: 6, minutes: 30 + ri * 10)).millisecondsSinceEpoch, 'endedAt': day.add(Duration(hours: 7, minutes: 50 + ri * 10)).millisecondsSinceEpoch};
        trips.add(tr);
        var ts = (tr['startedAt'] as int) + 8 * 60000;
        for (final s in students.where((s) => s['routeId'] == routes[ri]['id'])) {
          ts += (1 + r.nextInt(4)) * 60000;
          if (s['status'] != 'Active') {
            if (r.nextInt(3) == 0) scan(tr, s, s['card'], rejected, 'Shuttle access is ${(s['status'] as String).toLowerCase()}', ts, d > 3, users[2 + ri]['id']);
          } else if (r.nextInt(25) == 0) {
            scan(tr, s, s['card'], unable, 'Card could not be read', ts, d > 3, users[2 + ri]['id']);
          } else if (r.nextInt(14) != 0) {
            scan(tr, s, s['card'], authorised, 'Access confirmed', ts, true, users[2 + ri]['id']);
          }
        }
        if (r.nextInt(5) == 0) scan(tr, null, 'UR-000000', unable, 'Card not found in the system', ts + 60000, d > 3, users[2 + ri]['id']);
      }
    }
    // One trip running right now so the administrator can monitor it
    final live = {'id': id(), 'routeId': routes[1]['id'], 'vehicleId': vehicles[1]['id'], 'driverId': users[3]['id'], 'status': 'Active', 'startedAt': now.subtract(const Duration(minutes: 25)).millisecondsSinceEpoch, 'endedAt': null};
    trips.add(live);
    final onB = students.where((s) => s['routeId'] == routes[1]['id']).toList();
    for (var i = 0; i < 3; i++) {
      scan(live, onB[i], onB[i]['card'], onB[i]['status'] == 'Active' ? authorised : rejected, onB[i]['status'] == 'Active' ? 'Access confirmed' : 'Shuttle access is inactive', now.subtract(Duration(minutes: 20 - i * 5)).millisecondsSinceEpoch, onB[i]['status'] == 'Active', users[3]['id'] as String);
    }
    db = {'users': users, 'routes': routes, 'vehicles': vehicles, 'students': students, 'trips': trips, 'scans': scans, 'audit': <M>[],
      'notices': <M>[{'id': id(), 'text': 'Route 2 leaves 10 minutes earlier on Friday because of the graduation ceremony.', 'ts': now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch, 'by': users[0]['id']}]};
    meId = null;
    commit();
  }
}
