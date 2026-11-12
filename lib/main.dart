// UniRide Verify - UI layer. One codebase: Android (driver + admin) and Chrome (admin).
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'data.dart';
import 'location.dart';
import 'register.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(UniRideApp(await Store.open()));
}

// ---------- design tokens ----------
const navy = Color(0xFF0B1F4B), brand = Color(0xFF2563EB), okC = Color(0xFF16A34A), badC = Color(0xFFDC2626), warnC = Color(0xFFD97706);
const gold = Color(0xFFFBBF24);
const heroGradient = LinearGradient(colors: [Color(0xFF07163A), Color(0xFF123A8F), Color(0xFF2563EB)], begin: Alignment.topLeft, end: Alignment.bottomRight);

/// Gradient banner with soft decorative circles (headers, login, pass, trip summary).
Widget heroBox({required Widget child, EdgeInsets padding = const EdgeInsets.all(20), BorderRadius radius = BorderRadius.zero}) => ClipRRect(
      borderRadius: radius,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: heroGradient),
        child: Stack(children: [
          Positioned(right: -50, top: -50, child: Container(width: 190, height: 190, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(.06)))),
          Positioned(right: 70, bottom: -80, child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, color: gold.withOpacity(.10)))),
          Padding(padding: padding, child: child),
        ]),
      ),
    );
Color resultColor(String r) => r == authorised ? okC : (r == rejected ? badC : warnC);
IconData resultIcon(String r) => r == authorised ? Icons.check_circle : (r == rejected ? Icons.block : Icons.help);
bool wide(BuildContext c) => MediaQuery.of(c).size.width >= 900;
const greet = {'Zulu': 'Sawubona', 'Xhosa': 'Molo', 'Setswana': 'Dumela', 'Sepedi': 'Dumela'};
const limits = 'A scan checks a card number against the access list. It cannot tell whether the person holding the card is the student, so check the card holder when in doubt. “Unable to verify” means the card could not be confirmed, not that the student is unauthorised.';

class UniRideApp extends StatelessWidget {
  const UniRideApp(this.s, {super.key});
  final Store s;
  ThemeData _t(Brightness b) {
    final cs = ColorScheme.fromSeed(seedColor: brand, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFF4F6FB) : null,
      appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
      navigationBarTheme: NavigationBarThemeData(indicatorColor: brand.withOpacity(.16), height: 68),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.blueGrey.withOpacity(.08),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: brand, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'UniRide Verify',
        debugShowCheckedModeBanner: false,
        theme: _t(Brightness.light),
        darkTheme: _t(Brightness.dark),
        home: ListenableBuilder(listenable: s, builder: (_, __) => s.me == null ? WelcomePage(s) : Shell(s)),
      );
}

// ---------- shared widgets ----------
void snack(BuildContext c, String m) => ScaffoldMessenger.of(c)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
Widget panel(BuildContext c, Widget child, {EdgeInsets p = const EdgeInsets.all(16)}) => Container(
      width: double.infinity,
      padding: p,
      decoration: BoxDecoration(color: Theme.of(c).colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(c).colorScheme.outlineVariant.withOpacity(.6)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 14, offset: const Offset(0, 5))]),
      child: child,
    );
Widget chip(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withOpacity(.14), borderRadius: BorderRadius.circular(99)),
      child: Text(t, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
Color statusColor(String s) => s == 'Active' ? okC : (s == 'Suspended' ? warnC : Colors.grey);
Widget avatar(String name, {double r = 20}) => CircleAvatar(radius: r, backgroundColor: brand.withOpacity(.14), child: Text(name.split(' ').where((e) => e.isNotEmpty).map((e) => e[0]).take(2).join().toUpperCase(), style: const TextStyle(color: brand, fontWeight: FontWeight.w700)));
Widget empty(IconData i, String t) => Padding(padding: const EdgeInsets.all(32), child: Center(child: Column(children: [Icon(i, size: 40, color: Colors.grey), const SizedBox(height: 8), Text(t, style: const TextStyle(color: Colors.grey))])));
Widget title(BuildContext c, String t, [Widget? trailing]) => Padding(padding: const EdgeInsets.fromLTRB(2, 20, 2, 10), child: Row(children: [Expanded(child: Text(t, style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))), if (trailing != null) trailing]));
Widget grid(List<Widget> items, {int wideCols = 4, int narrowCols = 2}) => LayoutBuilder(builder: (_, bc) {
      final cols = bc.maxWidth >= 700 ? wideCols : narrowCols;
      const g = 12.0;
      final w = (bc.maxWidth - g * (cols - 1)) / cols;
      return Wrap(spacing: g, runSpacing: g, children: [for (final i in items) SizedBox(width: w, child: i)]);
    });
Widget stat(BuildContext c, IconData i, String label, String value, Color color) => panel(
      c,
      Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withOpacity(.14), borderRadius: BorderRadius.circular(12)), child: Icon(i, color: color)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), Text(label, style: Theme.of(c).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)])),
      ]),
    );
Widget errText(BuildContext c, String? e) => e == null ? const SizedBox() : Padding(padding: const EdgeInsets.only(top: 8), child: Text(e, style: TextStyle(color: Theme.of(c).colorScheme.error)));
Widget tf(String l, TextEditingController c, {bool num = false, Widget? suffix, bool obscure = false}) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextField(controller: c, obscureText: obscure, keyboardType: num ? TextInputType.number : TextInputType.text, decoration: InputDecoration(labelText: l, suffixIcon: suffix)),
    );
Widget dd(String l, String? v, List<(String, String)> items, void Function(String?) f) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DropdownButtonFormField<String>(value: v, isExpanded: true, decoration: InputDecoration(labelText: l), items: [for (final i in items) DropdownMenuItem(value: i.$1, child: Text(i.$2, overflow: TextOverflow.ellipsis))], onChanged: f),
    );
Future<void> sheet(BuildContext c, Widget Function(BuildContext, StateSetter) b) => showModalBottomSheet(
      context: c,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) => SingleChildScrollView(padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom), child: b(ctx, set))),
    );
String scanName(Store s, M x) => x['studentId'] == null ? 'Unknown card ${x['code']}' : s.nameOf('students', x['studentId']);

/// Student photo (stored as a small base64 JPEG) or initials when no photo was added.
Widget studentPhoto(String? photo, String name, {double r = 20}) =>
    photo == null || photo.isEmpty ? avatar(name, r: r) : CircleAvatar(radius: r, backgroundColor: Colors.blueGrey.withOpacity(.2), backgroundImage: MemoryImage(base64Decode(photo)));

/// Camera or gallery, shrunk to 360 px so many photos fit in device storage.
Future<String?> pickPhoto(ImageSource src) async {
  try {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 360, maxHeight: 360, imageQuality: 70);
    if (x == null) return null;
    return base64Encode(await x.readAsBytes());
  } catch (_) {
    return null;
  }
}

String accessLabel(Store s, M x) => x['status'] == 'Active' && s.expired(x) ? 'Expired' : x['status'] as String;
Color accessColor(Store s, M x) => accessLabel(s, x) == 'Expired' ? badC : statusColor(x['status']);

Widget untilButton(BuildContext ctx, int until, void Function(int) f) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () async {
            final d = await showDatePicker(context: ctx, initialDate: DateTime.fromMillisecondsSinceEpoch(until), firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (d != null) f(DateTime(d.year, d.month, d.day, 23, 59).millisecondsSinceEpoch);
          },
          icon: const Icon(Icons.event),
          label: Text('Access valid until ${ymd(DateTime.fromMillisecondsSinceEpoch(until))}'),
        ),
      ),
    );

Widget noticesPanel(BuildContext c, Store s, {bool editable = false}) {
  final list = s.notices;
  if (list.isEmpty) return panel(c, empty(Icons.campaign_outlined, 'No notices'));
  return panel(
    c,
    Column(children: [
      for (final n in list.take(5))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.campaign_outlined, color: brand),
          title: Text(n['text']),
          subtitle: Text('${dm(n['ts'])} · ${s.nameOf('users', n['by'])}'),
          trailing: editable ? IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Remove notice', onPressed: () => s.removeNotice(n['id'])) : null,
        ),
    ]),
    p: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  );
}

void noticeSheet(BuildContext c, Store s) {
  final msg = TextEditingController();
  String? err;
  sheet(c, (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Post a notice', style: Theme.of(ctx).textTheme.titleLarge),
        const Text('Every driver sees this on the Trip screen (delays, route changes, reminders).'),
        tf('Notice', msg),
        errText(ctx, err),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
          final e = s.addNotice(msg.text);
          if (e != null) { set(() => err = e); } else { Navigator.pop(ctx); }
        }, child: const Text('Post notice'))),
      ]));
}

/// Page frame: gradient header on phones, clean title row on wide screens.
class Pg extends StatelessWidget {
  const Pg(this.s, this.heading, this.sub, this.children, {this.fab, this.max = 1100, super.key});
  final Store s;
  final String heading, sub;
  final List<Widget> children;
  final Widget? fab;
  final double max;
  @override
  Widget build(BuildContext context) {
    final w = wide(context);
    final gear = IconButton(icon: Icon(Icons.settings_outlined, color: w ? null : Colors.white), tooltip: 'Settings', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(s))));
    final head = w
        ? Padding(padding: const EdgeInsets.fromLTRB(28, 24, 20, 0), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(heading, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), Text(sub)])), gear]))
        : heroBox(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 14, 8, 26),
            radius: const BorderRadius.vertical(bottom: Radius.circular(28)),
            child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(heading, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)), const SizedBox(height: 2), Text(sub, style: const TextStyle(color: Colors.white70))])), gear]),
          );
    return Scaffold(
      floatingActionButton: fab,
      body: ListView(padding: EdgeInsets.zero, children: [
        head,
        Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: Padding(padding: EdgeInsets.fromLTRB(w ? 24 : 16, 8, w ? 24 : 16, 90), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)))),
      ]),
    );
  }
}

// ---------- welcome ----------
class WelcomePage extends StatelessWidget {
  const WelcomePage(this.s, {super.key});
  final Store s;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(fit: StackFit.expand, children: [
          Image.asset('image/image.jpg', fit: BoxFit.cover),
          Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.black.withOpacity(.6), Colors.black.withOpacity(.2), Colors.transparent], begin: Alignment.bottomCenter, end: Alignment.topCenter))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Spacer(),
                Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white.withOpacity(.18), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.verified_user, color: gold, size: 28)),
                const SizedBox(height: 16),
                const Text('UniRide Verify', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Verified shuttle access\nfor every student.', style: TextStyle(color: Colors.white70, fontSize: 18)),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: brand, foregroundColor: Colors.white, minimumSize: const Size(0, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginPage(s))),
                    child: const Text('Get Started', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ]),
      );
}

// ---------- sign in ----------
class LoginPage extends StatefulWidget {
  const LoginPage(this.s, {super.key});
  final Store s;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(), pw = TextEditingController();
  bool hide = true;
  String? err;

  void _submit() {
    final e = widget.s.signIn(email.text, pw.text);
    if (e != null) setState(() => err = e);
  }

  Widget _brand({bool big = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withOpacity(.16), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.verified_user, color: gold, size: 30)),
        const SizedBox(height: 16),
        Text('UniRide Verify', style: TextStyle(color: Colors.white, fontSize: big ? 38 : 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Verified shuttle access for every student.', style: TextStyle(color: Colors.white70, fontSize: 16)),
        if (big) ...[
          const SizedBox(height: 28),
          for (final t in ['Administrators register qualifying students', 'Drivers scan student cards at the door', 'Live trip monitoring, notices and reports']) Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [const Icon(Icons.check_circle_outline, color: Colors.white70, size: 20), const SizedBox(width: 10), Text(t, style: const TextStyle(color: Colors.white))])),
        ],
      ]);

  Widget _form() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Sign in', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const Text('Use your UniRide account. Your role decides what you see.'),
        const SizedBox(height: 8),
        tf('Email', email),
        tf('Password', pw, obscure: hide, suffix: IconButton(icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => hide = !hide))),
        errText(context, err),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: _submit, child: const Text('Sign in'))),
        const SizedBox(height: 20),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(avatar: const Icon(Icons.admin_panel_settings, size: 18), label: const Text('Administrator'), onPressed: () => setState(() { email.text = 'admin@uniride.demo'; pw.text = defaultPassword; err = null; })),
          ActionChip(avatar: const Icon(Icons.drive_eta, size: 18), label: const Text('Driver'), onPressed: () => setState(() { email.text = 'themba@uniride.demo'; pw.text = defaultPassword; err = null; })),
        ]),
      ]);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: wide(context)
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: heroBox(padding: const EdgeInsets.all(56), child: Align(alignment: Alignment.centerLeft, child: _brand(big: true)))),
                Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Padding(padding: const EdgeInsets.all(24), child: _form())))),
              ])
            : SingleChildScrollView(
                child: Column(children: [
                  heroBox(radius: const BorderRadius.vertical(bottom: Radius.circular(32)), padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 40, 24, 40), child: _brand()),
                  Padding(padding: const EdgeInsets.all(24), child: _form()),
                ]),
              ),
      );
}

// ---------- shell ----------
class Shell extends StatefulWidget {
  const Shell(this.s, {super.key});
  final Store s;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final tabs = <(String, IconData, Widget)>[
      if (s.isAdmin) ...[
        ('Dashboard', Icons.space_dashboard_outlined, Dashboard(s)),
        ('Students', Icons.groups_outlined, StudentsPage(s)),
        ('Fleet', Icons.directions_bus_outlined, FleetPage(s)),
        ('Activity', Icons.fact_check_outlined, ActivityPage(s)),
        ('Reports', Icons.bar_chart_outlined, ReportsPage(s)),
      ],
      if (s.isDriver) ...[('Trip', Icons.route_outlined, DriverTrip(s)), ('History', Icons.history, DriverHistory(s))],
    ];
    final idx = i.clamp(0, tabs.length - 1);
    final body = IndexedStack(index: idx, children: [for (final t in tabs) t.$3]);
    if (wide(context) && s.isAdmin) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: true,
            selectedIndex: idx,
            onDestinationSelected: (v) => setState(() => i = v),
            leading: Padding(padding: const EdgeInsets.fromLTRB(8, 20, 8, 20), child: Row(children: [Container(width: 38, height: 38, decoration: BoxDecoration(gradient: heroGradient, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.directions_bus_filled, color: Colors.white, size: 20)), const SizedBox(width: 10), const Text('UniRide Verify', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))])),
            destinations: [for (final t in tabs) NavigationRailDestination(icon: Icon(t.$2), label: Text(t.$1))],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(selectedIndex: idx, onDestinationSelected: (v) => setState(() => i = v), destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.$2), label: t.$1)]),
    );
  }
}

// ---------- admin: dashboard ----------
Widget scanTile(BuildContext c, Store s, M x, {bool showTrip = false, VoidCallback? onTap}) {
  final col = resultColor(x['result']);
  return ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: col.withOpacity(.14), shape: BoxShape.circle), child: Icon(resultIcon(x['result']), color: col, size: 22)),
    title: Text(scanName(s, x), style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text('${dm(x['ts'])} · ${x['reason']}${showTrip ? ' · ${s.nameOf('routes', s.find('trips', x['tripId'])?['routeId'])}' : ''}'),
    trailing: chip(x['result'], col),
    onTap: onTap,
  );
}

class Dashboard extends StatelessWidget {
  const Dashboard(this.s, {super.key});
  final Store s;
  @override
  Widget build(BuildContext context) {
    final u = s.me!;
    final active = s.t('trips').where((x) => x['status'] == 'Active').toList();
    final students = s.t('students');
    final ex = s.exceptions.take(5).toList();
    return Pg(s, '${greet[u['lang']]}, ${(u['name'] as String).split(' ').first}', 'Shuttle operations overview', [
      const SizedBox(height: 8),
      grid([
        stat(context, Icons.directions_bus, 'Active trips', '${active.length}', brand),
        stat(context, Icons.verified_user, 'Students with access', '${students.where(s.hasAccess).length}/${students.length}', okC),
        stat(context, Icons.qr_code_scanner, 'Scans today', '${s.scansToday}', navy),
        stat(context, Icons.flag, 'Exceptions to review', '${s.openExceptions}', warnC),
      ]),
      title(context, 'Active trips'),
      if (active.isEmpty) panel(context, empty(Icons.directions_bus_outlined, 'No trips running right now')),
      for (final tr in active)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: panel(context, Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: okC.withOpacity(.14), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.directions_bus, color: okC)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.nameOf('routes', tr['routeId']), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${s.nameOf('users', tr['driverId'])} · ${s.nameOf('vehicles', tr['vehicleId'])} · since ${hm(tr['startedAt'])}', style: Theme.of(context).textTheme.bodySmall),
              if (s.lastLocated(tr['id']) != null) Text('Last location: ${fixOf(s.lastLocated(tr['id'])!)}', style: Theme.of(context).textTheme.bodySmall),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('${s.countOf(tr['id'], authorised)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), const Text('boarded', style: TextStyle(fontSize: 12))]),
          ])),
        ),
      title(context, 'Notices to drivers', TextButton.icon(onPressed: () => noticeSheet(context, s), icon: const Icon(Icons.add), label: const Text('Post'))),
      noticesPanel(context, s, editable: true),
      title(context, 'Latest exceptions'),
      panel(context, ex.isEmpty ? empty(Icons.check_circle_outline, 'No exceptions') : Column(children: [for (final x in ex) scanTile(context, s, x, showTrip: true, onTap: () => reviewSheet(context, s, x))])),
    ]);
  }
}

void reviewSheet(BuildContext c, Store s, M x) {
  final note = TextEditingController(text: x['note'] ?? '');
  final st = s.find('students', x['studentId']);
  sheet(c, (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(scanName(s, x), style: Theme.of(ctx).textTheme.titleLarge)), chip(x['result'], resultColor(x['result']))]),
        const SizedBox(height: 6),
        Text('${dm(x['ts'])} · ${x['method']}\n${x['reason']}\nTrip: ${s.nameOf('routes', s.find('trips', x['tripId'])?['routeId'])} · Driver: ${s.nameOf('users', x['by'])}'),
        if (st != null) Text('Student access: ${st['status']}'),
        tf('Review note', note),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () { s.reviewScan(x['id'], note.text); Navigator.pop(ctx); }, child: Text(x['reviewed'] == true ? 'Update note' : 'Mark as reviewed'))),
      ]));
}

// ---------- admin: students ----------
Widget sectionLabel(BuildContext c, String t) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 2), child: Text(t.toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w700, color: Theme.of(c).colorScheme.primary)));

Widget kv(IconData i, String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(i, size: 18, color: brand),
        const SizedBox(width: 10),
        SizedBox(width: 84, child: Text(k, style: const TextStyle(color: Colors.grey))),
        Expanded(child: Text(v.isEmpty ? '-' : v, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    );

void studentSheet(BuildContext c, Store s, {M? st}) {
  final n = TextEditingController(text: st?['name'] ?? ''), no = TextEditingController(text: st?['no'] ?? ''), pr = TextEditingController(text: st?['programme'] ?? ''), note = TextEditingController(text: st?['note'] ?? '');
  final home = TextEditingController(text: st?['residence'] ?? ''), bar = TextEditingController(text: st?['barcode'] ?? '');
  String? route = st?['routeId'], status = st?['status'] ?? 'Active', err;
  String basis = (st?['basis'] ?? qualBases.first) as String;
  String year = yearsOfStudy.contains(st?['year']) ? st!['year'] as String : yearsOfStudy.first;
  int until = (st?['validUntil'] ?? defaultUntil()) as int;
  String? photo = st?['photo'] as String?;
  sheet(c, (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(st == null ? 'Register qualifying student' : 'Edit student', style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 12),
        Center(child: Column(children: [
          studentPhoto(photo, 'Student', r: 46),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
            if (!kIsWeb) OutlinedButton.icon(onPressed: () async { final p = await pickPhoto(ImageSource.camera); if (p != null) set(() => photo = p); }, icon: const Icon(Icons.photo_camera_outlined), label: const Text('Take photo')),
            OutlinedButton.icon(onPressed: () async { final p = await pickPhoto(ImageSource.gallery); if (p != null) set(() => photo = p); }, icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose photo')),
            if (photo != null) TextButton(onPressed: () => set(() => photo = null), child: const Text('Remove')),
          ]),
          const Text('The driver sees this photo when the card is scanned.', style: TextStyle(fontSize: 12)),
        ])),
        sectionLabel(ctx, 'Student details'),
        tf('Full name', n),
        Row(children: [Expanded(child: tf('Student number', no)), const SizedBox(width: 10), Expanded(child: dd('Year of study', year, [for (final y in yearsOfStudy) (y, y)], (v) => set(() => year = v!)))]),
        tf('Course', pr),
        tf('Residence (where the student stays)', home),
        sectionLabel(ctx, 'Student card'),
        tf('Card barcode number (printed under the barcode)', bar, num: true, suffix: IconButton(icon: const Icon(Icons.qr_code_scanner), tooltip: 'Scan the card', onPressed: () async { final v = await Navigator.push<String>(ctx, MaterialPageRoute(builder: (_) => const BarcodePicker())); if (v != null) set(() => bar.text = v); })),
        sectionLabel(ctx, 'Shuttle access'),
        dd('Why the student qualifies', basis, [for (final b in qualBases) (b, b)], (v) => set(() => basis = v!)),
        dd('Route', route, [for (final r in s.t('routes')) (r['id'] as String, r['name'] as String)], (v) => set(() => route = v)),
        untilButton(ctx, until, (v) => set(() => until = v)),
        dd('Shuttle access', status, [for (final x in studentStatuses) (x, x)], (v) => set(() => status = v)),
        tf('Note (optional, e.g. reason for suspension)', note),
        errText(ctx, err),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
          final e = s.saveStudent(sid: st?['id'], name: n.text, no: no.text, programme: pr.text, routeId: route, status: status!, note: note.text.trim(), basis: basis, validUntil: until, photo: photo, year: year, residence: home.text, barcode: bar.text);
          if (e != null) { set(() => err = e); } else { Navigator.pop(ctx); snack(c, st == null ? 'Student registered' : 'Student updated'); }
        }, child: const Text('Save'))),
        if (st != null) Padding(padding: const EdgeInsets.only(top: 8), child: SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => cardDialog(ctx, st), icon: const Icon(Icons.badge_outlined), label: const Text('Show shuttle pass')))),
      ]));
}

class FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.round;
    const l = 34.0;
    final w = size.width, h = size.height;
    canvas.drawPath(Path()..moveTo(0, l)..lineTo(0, 0)..lineTo(l, 0), p);
    canvas.drawPath(Path()..moveTo(w - l, 0)..lineTo(w, 0)..lineTo(w, l), p);
    canvas.drawPath(Path()..moveTo(w, h - l)..lineTo(w, h)..lineTo(w - l, h), p);
    canvas.drawPath(Path()..moveTo(l, h)..lineTo(0, h)..lineTo(0, h - l), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

Widget scanFrame() => SizedBox(width: 300, height: 180, child: CustomPaint(painter: FramePainter()));

/// Opens the camera, reads one barcode and returns its number (used to capture the number on a student card).
class BarcodePicker extends StatefulWidget {
  const BarcodePicker({super.key});
  @override
  State<BarcodePicker> createState() => _BarcodePickerState();
}

class _BarcodePickerState extends State<BarcodePicker> {
  bool done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan the student card')),
        body: Stack(children: [
          Positioned.fill(
            child: MobileScanner(
              onDetect: (cap) {
                for (final b in cap.barcodes) {
                  final v = b.rawValue;
                  if (!done && v != null && v.isNotEmpty) { done = true; Navigator.pop(context, v); break; }
                }
              },
              errorBuilder: (ctx, err, _) => const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Camera unavailable. Allow camera access, or type the number instead.', textAlign: TextAlign.center))),
            ),
          ),
          Center(child: scanFrame()),
          const Align(alignment: Alignment.bottomCenter, child: Padding(padding: EdgeInsets.all(28), child: Text('Hold the barcode on the student card inside the frame', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600), textAlign: TextAlign.center))),
        ]),
      );
}

void importSheet(BuildContext c, Store s) {
  final txt = TextEditingController();
  String? route, msg;
  String basis = qualBases.first;
  int until = defaultUntil();
  sheet(c, (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Import qualifying students', style: Theme.of(ctx).textTheme.titleLarge),
        const Text('Paste one student per line: name, student number, course, year, residence, card barcode number. Everything after the student number is optional. You can copy rows straight from Excel.'),
        Padding(padding: const EdgeInsets.only(top: 10), child: TextField(controller: txt, minLines: 6, maxLines: 10, decoration: const InputDecoration(hintText: 'Lindiwe Mthembu, 202630100, Dip. Information Technology, 2nd year, Campus residence A, 452230514555'))),
        dd('Route for all these students', route, [for (final r in s.t('routes')) (r['id'] as String, r['name'] as String)], (v) => set(() => route = v)),
        dd('Why they qualify', basis, [for (final b in qualBases) (b, b)], (v) => set(() => basis = v!)),
        untilButton(ctx, until, (v) => set(() => until = v)),
        if (msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(msg!, style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
          if (route == null) { set(() => msg = 'Select a route first'); return; }
          if (txt.text.trim().isEmpty) { set(() => msg = 'Paste the list of students first'); return; }
          final r = s.importStudents(txt.text, route!, basis, until);
          txt.clear();
          set(() => msg = r);
        }, child: const Text('Add students'))),
      ]));
}

void cardDialog(BuildContext c, M st) => showDialog(
      context: c,
      builder: (d) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              heroBox(padding: const EdgeInsets.fromLTRB(20, 22, 20, 24), child: Row(children: [
                Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: studentPhoto(st['photo'], st['name'], r: 38)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('UNIRIDE SHUTTLE PASS', style: TextStyle(color: gold, fontSize: 11, letterSpacing: 1.3, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(st['name'], style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                  Text('${st['no']}', style: const TextStyle(color: Colors.white70)),
                ])),
              ])),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  kv(Icons.school_outlined, 'Course', '${st['programme'] ?? ''}'),
                  kv(Icons.event_note_outlined, 'Year', '${st['year'] ?? ''}'),
                  kv(Icons.home_outlined, 'Residence', '${st['residence'] ?? ''}'),
                  kv(Icons.verified_outlined, 'Qualifies by', '${st['basis'] ?? ''}'),
                  kv(Icons.credit_card, 'Card no.', '${st['barcode'] ?? ''}'),
                  const SizedBox(height: 12),
                  Container(color: Colors.white, padding: const EdgeInsets.all(10), child: QrImageView(data: st['card'], size: 150)),
                  const SizedBox(height: 6),
                  Text(st['card'], style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Sample pass. In real use the driver scans the barcode on the student’s own card.', style: TextStyle(fontSize: 12), textAlign: TextAlign.center),
                  TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close')),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );

class StudentsPage extends StatefulWidget {
  const StudentsPage(this.s, {super.key});
  final Store s;
  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  String q = '', filter = 'All';
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final list = s.t('students').where((x) => (filter == 'All' || x['status'] == filter) && ('${x['name']} ${x['no']}'.toLowerCase().contains(q.toLowerCase()))).toList();
    final w = wide(context);
    return Pg(s, 'Students', '${list.length} of ${s.t('students').length} shown', fab: FloatingActionButton.extended(onPressed: () => studentSheet(context, s), icon: const Icon(Icons.person_add), label: const Text('Register')), [
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () => importSheet(context, s), icon: const Icon(Icons.upload_file), label: const Text('Import list of qualifying students'))),
      const SizedBox(height: 10),
      TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by name or student number'), onChanged: (v) => setState(() => q = v)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [for (final f in ['All', ...studentStatuses]) ChoiceChip(label: Text(f), selected: filter == f, onSelected: (_) => setState(() => filter = f))]),
      const SizedBox(height: 12),
      if (list.isEmpty) panel(context, empty(Icons.search_off, 'No students match')),
      if (list.isNotEmpty && w)
        panel(context, SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(showCheckboxColumn: false, columns: const [DataColumn(label: Text('Student')), DataColumn(label: Text('Number')), DataColumn(label: Text('Course')), DataColumn(label: Text('Year')), DataColumn(label: Text('Residence')), DataColumn(label: Text('Route')), DataColumn(label: Text('Valid until')), DataColumn(label: Text('Access')), DataColumn(label: Text('Pass'))], rows: [
          for (final x in list) DataRow(onSelectChanged: (_) => studentSheet(context, s, st: x), cells: [DataCell(Row(children: [studentPhoto(x['photo'], x['name'], r: 16), const SizedBox(width: 10), Text(x['name'])])), DataCell(Text(x['no'])), DataCell(Text('${x['programme']}')), DataCell(Text('${x['year'] ?? '—'}')), DataCell(Text('${x['residence'] ?? '—'}')), DataCell(Text(s.nameOf('routes', x['routeId']))), DataCell(Text(x['validUntil'] == null ? '—' : ymd(DateTime.fromMillisecondsSinceEpoch(x['validUntil'])))), DataCell(chip(accessLabel(s, x), accessColor(s, x))), DataCell(IconButton(icon: const Icon(Icons.badge_outlined), onPressed: () => cardDialog(context, x)))]),
        ])), p: EdgeInsets.zero),
      if (list.isNotEmpty && !w)
        panel(context, Column(children: [for (final x in list) ListTile(leading: studentPhoto(x['photo'], x['name']), title: Text(x['name'], style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text('${x['no']}${(x['residence'] ?? '').toString().isEmpty ? '' : ' · ${x['residence']}'}'), trailing: chip(accessLabel(s, x), accessColor(s, x)), onTap: () => studentSheet(context, s, st: x))]), p: const EdgeInsets.symmetric(vertical: 6, horizontal: 8)),
    ]);
  }
}

// ---------- admin: fleet ----------
class FleetPage extends StatefulWidget {
  const FleetPage(this.s, {super.key});
  final Store s;
  @override
  State<FleetPage> createState() => _FleetPageState();
}

class _FleetPageState extends State<FleetPage> {
  int seg = 0;
  Store get s => widget.s;
  void _toggle(String k, String id) { final e = s.toggleActive(k, id); if (e != null) snack(context, e); }

  void _add() {
    final a = TextEditingController(), b = TextEditingController(), c = TextEditingController();
    String lang = 'Zulu';
    String? err;
    sheet(context, (ctx, set) {
      final labels = [['Add driver', 'Full name', 'Email'], ['Add shuttle', 'Label', 'Registration'], ['Add route', 'Route name', 'Stops (comma separated)']][seg];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(labels[0], style: Theme.of(ctx).textTheme.titleLarge),
        tf(labels[1], a), tf(labels[2], b),
        if (seg == 0) dd('Home language', lang, [for (final l in greet.keys) (l, l)], (v) => lang = v!),
        if (seg == 1) tf('Seats', c, num: true),
        errText(ctx, err),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () {
          final e = seg == 0 ? s.addDriver(a.text, b.text, lang) : (seg == 1 ? s.addVehicle(a.text, b.text, int.tryParse(c.text)) : s.addRoute(a.text, b.text));
          if (e != null) { set(() => err = e); } else { Navigator.pop(ctx); }
        }, child: const Text('Save'))),
      ]);
    });
  }

  void _assign(M d) {
    String? v = d['vehicleId'], r = d['routeId'];
    sheet(context, (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Assign ${d['name']}', style: Theme.of(ctx).textTheme.titleLarge),
          dd('Shuttle', v, [for (final x in s.t('vehicles').where((x) => x['active'] == true)) (x['id'] as String, '${x['label']} · ${x['reg']}')], (x) => set(() => v = x)),
          dd('Route', r, [for (final x in s.t('routes').where((x) => x['active'] == true)) (x['id'] as String, x['name'] as String)], (x) => set(() => r = x)),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () { s.assignDriver(d['id'], v, r); Navigator.pop(ctx); }, child: const Text('Save assignment'))),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final drivers = s.t('users').where((u) => u['role'] == 'driver').toList();
    return Pg(s, 'Fleet', 'Drivers, shuttles and routes', fab: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: Text(['Driver', 'Shuttle', 'Route'][seg])), [
      const SizedBox(height: 8),
      SegmentedButton<int>(segments: const [ButtonSegment(value: 0, label: Text('Drivers'), icon: Icon(Icons.badge_outlined)), ButtonSegment(value: 1, label: Text('Shuttles'), icon: Icon(Icons.directions_bus_outlined)), ButtonSegment(value: 2, label: Text('Routes'), icon: Icon(Icons.alt_route))], selected: {seg}, onSelectionChanged: (v) => setState(() => seg = v.first)),
      const SizedBox(height: 12),
      if (seg == 0) for (final d in drivers) Padding(padding: const EdgeInsets.only(bottom: 10), child: panel(context, Row(children: [
        avatar(d['name']), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(d['name'], style: const TextStyle(fontWeight: FontWeight.w700)), Text(d['email'], style: Theme.of(context).textTheme.bodySmall), Text('${s.nameOf('vehicles', d['vehicleId'])} · ${s.nameOf('routes', d['routeId'])}')])),
        IconButton(icon: const Icon(Icons.edit_road), tooltip: 'Assign shuttle and route', onPressed: () => _assign(d)),
        Switch(value: d['active'] == true, onChanged: (_) => _toggle('users', d['id'])),
      ]))),
      if (seg == 1) for (final v in s.t('vehicles')) Padding(padding: const EdgeInsets.only(bottom: 10), child: panel(context, Row(children: [
        const Icon(Icons.directions_bus, color: brand), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(v['label'], style: const TextStyle(fontWeight: FontWeight.w700)), Text('${v['reg']} · ${v['cap']} seats')])),
        Switch(value: v['active'] == true, onChanged: (_) => _toggle('vehicles', v['id'])),
      ]))),
      if (seg == 2) for (final r in s.t('routes')) Padding(padding: const EdgeInsets.only(bottom: 10), child: panel(context, Row(children: [
        const Icon(Icons.alt_route, color: brand), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r['name'], style: const TextStyle(fontWeight: FontWeight.w700)), Text((r['stops'] as List).join('  →  '), style: Theme.of(context).textTheme.bodySmall)])),
        Switch(value: r['active'] == true, onChanged: (_) => _toggle('routes', r['id'])),
      ]))),
    ]);
  }
}

// ---------- admin: activity ----------
class ActivityPage extends StatefulWidget {
  const ActivityPage(this.s, {super.key});
  final Store s;
  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  String f = 'All';
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    var list = [...s.t('scans')]..sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
    if (f == 'Exceptions') list = list.where((x) => x['result'] != authorised).toList();
    if (f == 'Unreviewed') list = list.where((x) => x['reviewed'] != true).toList();
    list = list.take(100).toList();
    return Pg(s, 'Verification activity', 'Every scan, with its outcome and source', [
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [for (final x in ['All', 'Exceptions', 'Unreviewed']) ChoiceChip(label: Text(x), selected: f == x, onSelected: (_) => setState(() => f = x))]),
      const SizedBox(height: 12),
      if (list.isEmpty) panel(context, empty(Icons.fact_check_outlined, 'Nothing to show')),
      if (list.isNotEmpty && wide(context))
        panel(context, SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(showCheckboxColumn: false, columns: const [DataColumn(label: Text('Time')), DataColumn(label: Text('Student / card')), DataColumn(label: Text('Result')), DataColumn(label: Text('Reason')), DataColumn(label: Text('Route')), DataColumn(label: Text('Driver')), DataColumn(label: Text('Method')), DataColumn(label: Text('Review'))], rows: [
          for (final x in list) DataRow(onSelectChanged: x['result'] == authorised ? null : (_) => reviewSheet(context, s, x), cells: [DataCell(Text(dm(x['ts']))), DataCell(Text(scanName(s, x))), DataCell(chip(x['result'], resultColor(x['result']))), DataCell(Text(x['reason'])), DataCell(Text(s.nameOf('routes', s.find('trips', x['tripId'])?['routeId']))), DataCell(Text(s.nameOf('users', x['by']))), DataCell(Text(x['method'])), DataCell(x['result'] == authorised ? const Text('—') : chip(x['reviewed'] == true ? 'Reviewed' : 'Open', x['reviewed'] == true ? okC : warnC))]),
        ])), p: EdgeInsets.zero),
      if (list.isNotEmpty && !wide(context))
        panel(context, Column(children: [for (final x in list) scanTile(context, s, x, showTrip: true, onTap: x['result'] == authorised ? null : () => reviewSheet(context, s, x))]), p: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
    ]);
  }
}

// ---------- admin: reports ----------
class BarPainter extends CustomPainter {
  BarPainter(this.v, this.labels, this.color, this.text);
  final List<double> v;
  final List<String> labels;
  final Color color, text;
  @override
  void paint(Canvas c, Size s) {
    final mx = v.fold<double>(1, (a, b) => b > a ? b : a);
    final w = s.width / v.length, h = s.height - 18;
    final p = Paint()..color = color;
    for (var i = 0; i < v.length; i++) {
      final bh = v[i] / mx * h;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(i * w + w * .18, h - bh, w * .64, bh), const Radius.circular(5)), p);
      if (v.length <= 14 || i % 5 == 0) {
        final tp = TextPainter(text: TextSpan(text: labels[i], style: TextStyle(color: text, fontSize: 10)), textDirection: TextDirection.ltr)..layout();
        tp.paint(c, Offset(i * w + (w - tp.width) / 2, s.height - tp.height));
      }
    }
  }
  @override
  bool shouldRepaint(BarPainter o) => true;
}

class ReportsPage extends StatefulWidget {
  const ReportsPage(this.s, {super.key});
  final Store s;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  int days = 7;
  Future<void> _share(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {
      if (mounted) snack(context, 'Could not create the file. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s, cs = Theme.of(context).colorScheme;
    final sc = s.scansIn(days);
    int n(String r) => sc.where((x) => x['result'] == r).length;
    final rate = sc.isEmpty ? 0 : (n(authorised) * 100 / sc.length).round();
    final now = DateTime.now();
    final labels = [for (var i = days - 1; i >= 0; i--) '${now.subtract(Duration(days: i)).day}'];
    final tripRoute = {for (final t in s.t('trips')) t['id']: t['routeId']};
    final recent = (s.t('trips').toList()..sort((a, b) => (b['startedAt'] as int).compareTo(a['startedAt'] as int))).take(8).toList();
    return Pg(s, 'Reports', 'Verification results over time', [
      const SizedBox(height: 8),
      SegmentedButton<int>(segments: const [ButtonSegment(value: 7, label: Text('Last 7 days')), ButtonSegment(value: 30, label: Text('Last 30 days'))], selected: {days}, onSelectionChanged: (v) => setState(() => days = v.first)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: () => _share(() => shareReportPdf(s, days)), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Save report as PDF')),
        OutlinedButton.icon(onPressed: () => _share(() => shareScansCsv(s, days)), icon: const Icon(Icons.table_chart_outlined), label: const Text('Save as Excel (CSV)')),
        OutlinedButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: s.scansCsv(days))); snack(context, 'Report copied. Paste it into Excel or Word.'); }, icon: const Icon(Icons.copy_all), label: const Text('Copy')),
      ]),
      const SizedBox(height: 12),
      grid([
        stat(context, Icons.qr_code_scanner, 'Total scans', '${sc.length}', navy),
        stat(context, Icons.check_circle, 'Authorised ($rate%)', '${n(authorised)}', okC),
        stat(context, Icons.block, 'Not authorised', '${n(rejected)}', badC),
        stat(context, Icons.help, 'Unable to verify', '${n(unable)}', warnC),
      ]),
      title(context, 'Scans per day'),
      panel(context, SizedBox(height: 150, width: double.infinity, child: CustomPaint(painter: BarPainter(s.dailyScans(days), labels, brand, cs.onSurfaceVariant)))),
      title(context, 'By route'),
      panel(context, SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [DataColumn(label: Text('Route')), DataColumn(label: Text('Scans'), numeric: true), DataColumn(label: Text('Authorised'), numeric: true), DataColumn(label: Text('Rejected'), numeric: true), DataColumn(label: Text('Unable'), numeric: true)], rows: [
        for (final r in s.t('routes')) DataRow(cells: () {
          final x = sc.where((e) => tripRoute[e['tripId']] == r['id']).toList();
          int k(String res) => x.where((e) => e['result'] == res).length;
          return [DataCell(Text(r['name'])), DataCell(Text('${x.length}')), DataCell(Text('${k(authorised)}')), DataCell(Text('${k(rejected)}')), DataCell(Text('${k(unable)}'))];
        }()),
      ])), p: EdgeInsets.zero),
      title(context, 'Boarding registers (PDF and Excel)'),
      panel(context, Column(children: [
        for (final tr in recent)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined, color: brand),
            title: Text(s.nameOf('routes', tr['routeId']), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${dm(tr['startedAt'])} · ${s.nameOf('users', tr['driverId'])} · ${s.countOf(tr['id'], authorised)} boarded'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripReportPage(s, tr['id']))),
          ),
      ]), p: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
      const SizedBox(height: 12),
      Text(limits, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

// ---------- driver ----------
Widget counter(String label, int v, Color c) => Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: Colors.white.withOpacity(.14), borderRadius: BorderRadius.circular(12)), child: Column(children: [Text('$v', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11))])));

Widget ctaCard({required IconData icon, required String title, required String sub, required VoidCallback onTap}) => Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [brand, Color(0xFF4F46E5)]), borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: brand.withOpacity(.35), blurRadius: 18, offset: const Offset(0, 8))]),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Container(width: 60, height: 60, decoration: BoxDecoration(color: Colors.white.withOpacity(.18), borderRadius: BorderRadius.circular(18)), child: Icon(icon, color: Colors.white, size: 32)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(sub, style: const TextStyle(color: Colors.white70)),
              ])),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ]),
          ),
        ),
      ),
    );

class DriverTrip extends StatelessWidget {
  const DriverTrip(this.s, {super.key});
  final Store s;

  void _begin(BuildContext c) {
    final e = s.startTrip();
    if (e != null) { snack(c, e); return; }
    Navigator.push(c, MaterialPageRoute(builder: (_) => ScannerPage(s, s.activeTrip(s.meId)!['id'])));
  }

  void _finish(BuildContext c, M trip) => showDialog(
        context: c,
        builder: (d) => AlertDialog(
          title: const Text('Finish and save register?'),
          content: Text('Boarded: ${s.countOf(trip['id'], authorised)}\nNot authorised: ${s.countOf(trip['id'], rejected)}\nUnable to verify: ${s.countOf(trip['id'], unable)}\n\nThe trip ends and the boarding register is saved. You can then download it as a PDF or Excel file.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Keep scanning')),
            FilledButton(onPressed: () { Navigator.pop(d); s.endTrip(trip['id']); Navigator.push(c, MaterialPageRoute(builder: (_) => TripReportPage(s, trip['id'], justFinished: true))); }, child: const Text('Finish')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final u = s.me!, trip = s.activeTrip(s.meId);
    final v = s.find('vehicles', u['vehicleId']), r = s.find('routes', u['routeId']);
    final first = (u['name'] as String).split(' ').first;
    return Pg(s, '${greet[u['lang']]}, $first', trip == null ? 'Ready for student verification' : 'Verification in progress', max: 600, [
      const SizedBox(height: 8),
      if (v == null || r == null) panel(context, empty(Icons.assignment_late_outlined, 'No shuttle or route assigned yet.\nAsk the administrator.')),
      if (v != null && r != null && trip == null) ...[
        ctaCard(icon: Icons.qr_code_scanner, title: 'Start student verification', sub: 'Begin the trip, then scan each student’s card as they board.', onTap: () => _begin(context)),
        const SizedBox(height: 16),
        panel(context, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.alt_route, color: brand), const SizedBox(width: 8), Expanded(child: Text(r['name'], style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)))]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final x in r['stops'] as List) chip('$x', brand)]),
          const Divider(height: 28),
          Row(children: [const Icon(Icons.directions_bus, color: brand), const SizedBox(width: 8), Text('${v['label']} · ${v['reg']} · ${v['cap']} seats')]),
        ])),
      ],
      if (trip != null) ...[
        heroBox(
          radius: BorderRadius.circular(22),
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s.nameOf('routes', trip['routeId'])} · started ${hm(trip['startedAt'])}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('${s.countOf(trip['id'], authorised)}', style: const TextStyle(color: Colors.white, fontSize: 54, fontWeight: FontWeight.w800, height: 1)), const SizedBox(width: 8), Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('boarded · ${s.seatsOf(trip['id'])} seats', style: const TextStyle(color: Colors.white70, fontSize: 16)))]),
            const SizedBox(height: 14),
            Row(children: [counter('Authorised', s.countOf(trip['id'], authorised), okC), const SizedBox(width: 8), counter('Not authorised', s.countOf(trip['id'], rejected), badC), const SizedBox(width: 8), counter('Unable', s.countOf(trip['id'], unable), warnC)]),
          ]),
        ),
        const SizedBox(height: 14),
        ctaCard(icon: Icons.qr_code_scanner, title: 'Continue scanning', sub: 'Scan the next student’s card.', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScannerPage(s, trip['id'])))),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => _finish(context, trip), icon: const Icon(Icons.flag_outlined), label: const Text('Finish and save register'))),
        title(context, 'Boarded so far'),
        panel(context, s.scansOf(trip['id']).isEmpty ? empty(Icons.qr_code_2, 'No cards scanned yet') : Column(children: [for (final x in s.scansOf(trip['id'])) scanTile(context, s, x)]), p: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
      ],
      if (s.notices.isNotEmpty) ...[title(context, 'Notices from the administrator'), noticesPanel(context, s)],
      const SizedBox(height: 16),
      Text(limits, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage(this.s, this.tid, {super.key});
  final Store s;
  final String tid;
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  M? res;
  String? last;
  DateTime lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  final code = TextEditingController();
  final cam = MobileScannerController();
  Fix? fix;
  Timer? gpsTimer;

  @override
  void initState() {
    super.initState();
    _locate();
    gpsTimer = Timer.periodic(const Duration(seconds: 45), (_) => _locate());
  }

  Future<void> _locate() async {
    final f = await currentFix();
    if (mounted && f != null) setState(() => fix = f);
  }

  @override
  void dispose() {
    gpsTimer?.cancel();
    cam.dispose();
    super.dispose();
  }

  void _check(String raw, {bool manual = false}) {
    if (res != null) return;
    // ignore the same card still in front of the camera
    if (!manual && raw == last && DateTime.now().difference(lastAt).inSeconds < 4) return;
    final r = widget.s.verify(widget.tid, raw, manual: manual, lat: fix?.lat, lng: fix?.lng);
    last = raw;
    lastAt = DateTime.now();
    r['result'] == authorised ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
    setState(() => res = r);
    code.clear();
    if (r['result'] == authorised) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && identical(res, r)) setState(() => res = null);
      });
    }
  }

  Future<void> _finish() async {
    final s = widget.s, tid = widget.tid;
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Finish and save register?'),
        content: Text('Boarded: ${s.countOf(tid, authorised)}\nNot authorised: ${s.countOf(tid, rejected)}\nUnable to verify: ${s.countOf(tid, unable)}\n\nThe trip ends and the boarding register is saved. You can then download it as a PDF or Excel file.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep scanning')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Finish'))],
      ),
    );
    if (yes != true || !mounted) return;
    s.endTrip(tid);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TripReportPage(s, tid, justFinished: true)));
  }

  Widget _result(M r) {
    final col = resultColor(r['result']), st = r['student'] as M?;
    final hasPhoto = st != null && st['photo'] != null && (st['photo'] as String).isNotEmpty;
    return Container(
      color: col,
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      child: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height - 120),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (hasPhoto)
                Container(padding: const EdgeInsets.all(5), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: studentPhoto(st['photo'], st['name'], r: 78))
              else
                Icon(resultIcon(r['result']), color: Colors.white, size: 120),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(.2), borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(resultIcon(r['result']), color: Colors.white, size: 22), const SizedBox(width: 8), Text((r['result'] as String).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: .5))]),
              ),
              const SizedBox(height: 16),
              if (st != null) ...[
                Text(st['name'], textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${st['no']}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                Text('${st['programme']}${(st['year'] ?? '').toString().isEmpty ? '' : ' · ${st['year']}'}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                if ((st['residence'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.home_outlined, color: Colors.white70, size: 18), const SizedBox(width: 6), Text('${st['residence']}', style: const TextStyle(color: Colors.white70))])),
              ],
              const SizedBox(height: 12),
              Text(r['reason'], textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 17)),
              if (hasPhoto && r['result'] == authorised) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Check that the photo matches the student boarding.', style: TextStyle(color: Colors.white70), textAlign: TextAlign.center)),
              if (r['result'] == unable) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Check the card, or enter the number manually.', style: TextStyle(color: Colors.white70), textAlign: TextAlign.center)),
              if (r['over'] == true) const Padding(padding: EdgeInsets.only(top: 8), child: Text('The shuttle is already full. Tell the administrator.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
              const SizedBox(height: 26),
              SizedBox(width: 260, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: col), onPressed: () => setState(() => res = null), child: const Text('Scan next', style: TextStyle(fontWeight: FontWeight.w700)))),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s, tid = widget.tid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student verification'),
        actions: [
          IconButton(tooltip: 'Torch', icon: const Icon(Icons.flashlight_on_outlined), onPressed: () => cam.toggleTorch()),
          TextButton.icon(onPressed: _finish, icon: const Icon(Icons.flag_outlined), label: const Text('Finish')),
        ],
      ),
      body: Stack(children: [
        Positioned.fill(
          child: MobileScanner(
            controller: cam,
            onDetect: (cap) {
              for (final b in cap.barcodes) {
                final v = b.rawValue;
                if (v != null && v.isNotEmpty) { _check(v); break; }
              }
            },
            errorBuilder: (ctx, err, _) => const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Camera unavailable. Allow camera access, or enter the card number below.', textAlign: TextAlign.center))),
          ),
        ),
        Center(child: scanFrame()),
        Positioned(
          top: 14,
          left: 0,
          right: 0,
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
              child: Text('${s.countOf(tid, authorised)} boarded · ${s.countOf(tid, rejected)} refused · ${s.countOf(tid, unable)} unable', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            const Text('Hold the barcode on the student card inside the frame', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 6)])),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(fix == null ? Icons.location_off_outlined : Icons.my_location, color: Colors.white, size: 16), const SizedBox(width: 4), Text(fix == null ? 'Location not available' : 'GPS ${fix!.lat.toStringAsFixed(4)}, ${fix!.lng.toStringAsFixed(4)}', style: const TextStyle(color: Colors.white, fontSize: 12, shadows: [Shadow(blurRadius: 6)]))]),
          ]),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
            child: Row(children: [
              Expanded(child: TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(hintText: 'Or type the student or card number'), onSubmitted: (v) => _check(v, manual: true))),
              const SizedBox(width: 10),
              FilledButton(onPressed: () => _check(code.text, manual: true), child: const Text('Verify')),
            ]),
          ),
        ),
        if (res != null) Positioned.fill(child: _result(res!)),
      ]),
    );
  }
}

/// Boarding register of one trip: summary, student list, and the PDF / Excel downloads.
class TripReportPage extends StatefulWidget {
  const TripReportPage(this.s, this.tid, {this.justFinished = false, super.key});
  final Store s;
  final String tid;
  final bool justFinished;
  @override
  State<TripReportPage> createState() => _TripReportPageState();
}

class _TripReportPageState extends State<TripReportPage> {
  bool busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => busy = true);
    try {
      await f();
    } catch (_) {
      if (mounted) snack(context, 'Could not create the file. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s, tid = widget.tid, trip = s.find('trips', tid)!;
    final scans = s.scansOf(tid).reversed.toList();
    final endedAt = trip['endedAt'] as int?;
    final loc = s.lastLocated(tid);
    return Scaffold(
      appBar: AppBar(title: const Text('Boarding register')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              heroBox(
                radius: BorderRadius.circular(22),
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (widget.justFinished) const Row(children: [Icon(Icons.check_circle, color: gold), SizedBox(width: 8), Text('Trip complete. Register saved.', style: TextStyle(color: gold, fontWeight: FontWeight.w700))]),
                  if (widget.justFinished) const SizedBox(height: 10),
                  Text(s.nameOf('routes', trip['routeId']), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${ymd(DateTime.fromMillisecondsSinceEpoch(trip['startedAt']))} · ${hm(trip['startedAt'])}${endedAt == null ? ' (in progress)' : ' to ${hm(endedAt)}'}', style: const TextStyle(color: Colors.white70)),
                  Text('${s.nameOf('users', trip['driverId'])} · ${s.nameOf('vehicles', trip['vehicleId'])}', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  Row(children: [counter('Authorised', s.countOf(tid, authorised), okC), const SizedBox(width: 8), counter('Not authorised', s.countOf(tid, rejected), badC), const SizedBox(width: 8), counter('Unable', s.countOf(tid, unable), warnC)]),
                ]),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: busy ? null : () => _run(() => shareRegisterPdf(s, tid)), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Save register as PDF'))),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: busy ? null : () => _run(() => shareRegisterCsv(s, tid)), icon: const Icon(Icons.table_chart_outlined), label: const Text('Save as Excel file (CSV)'))),
              const SizedBox(height: 4),
              Align(alignment: Alignment.center, child: TextButton.icon(onPressed: busy ? null : () => _run(() => previewRegister(s, tid)), icon: const Icon(Icons.print_outlined), label: const Text('Preview or print'))),
              if (busy) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator()),
              if (loc != null) ...[
                const SizedBox(height: 12),
                panel(context, Row(children: [
                  const Icon(Icons.my_location, color: brand),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Last recorded location', style: TextStyle(fontWeight: FontWeight.w700)), Text('${fixOf(loc)} · ${hm(loc['ts'])}')])),
                  TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: linkOf(loc))); snack(context, 'Map link copied'); }, child: const Text('Copy map link')),
                ])),
              ],
              title(context, 'Students on this trip (${scans.length})'),
              panel(
                context,
                scans.isEmpty
                    ? empty(Icons.groups_outlined, 'No cards were scanned on this trip')
                    : Column(children: [
                        for (final x in scans)
                          () {
                            final st = s.find('students', x['studentId']);
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: st == null ? CircleAvatar(backgroundColor: warnC.withOpacity(.14), child: const Icon(Icons.help_outline, color: warnC)) : studentPhoto(st['photo'], st['name']),
                              title: Text(st?['name'] ?? 'Unknown card ${x['code']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(st == null ? '${x['reason']}' : '${st['no']} · ${(st['residence'] ?? '').toString().isEmpty ? 'no residence' : st['residence']} · ${hm(x['ts'])}${x['result'] == authorised ? '' : ' · ${x['reason']}'}'),
                              trailing: chip(x['result'], resultColor(x['result'])),
                            );
                          }(),
                      ]),
                p: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class DriverHistory extends StatelessWidget {
  const DriverHistory(this.s, {super.key});
  final Store s;
  @override
  Widget build(BuildContext context) {
    final trips = s.t('trips').where((x) => x['driverId'] == s.meId).toList()..sort((a, b) => (b['startedAt'] as int).compareTo(a['startedAt'] as int));
    return Pg(s, 'Trip history', '${trips.length} trips', max: 600, [
      const SizedBox(height: 8),
      if (trips.isEmpty) panel(context, empty(Icons.history, 'No trips yet')),
      for (final x in trips)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripReportPage(s, x['id']))),
            child: panel(context, Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.nameOf('routes', x['routeId']), style: const TextStyle(fontWeight: FontWeight.w700)), Text('${dm(x['startedAt'])}${x['endedAt'] == null ? '' : ' – ${hm(x['endedAt'])}'}', style: Theme.of(context).textTheme.bodySmall)])),
              chip('${s.countOf(x['id'], authorised)} ok', okC), const SizedBox(width: 6),
              if (s.countOf(x['id'], rejected) + s.countOf(x['id'], unable) > 0) chip('${s.countOf(x['id'], rejected) + s.countOf(x['id'], unable)} flagged', warnC),
            ])),
          ),
        ),
    ]);
  }
}

// ---------- settings ----------
class SettingsPage extends StatelessWidget {
  const SettingsPage(this.s, {super.key});
  final Store s;
  @override
  Widget build(BuildContext context) {
    final u = s.me;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings & help')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (u != null) panel(context, Row(children: [avatar(u['name'], r: 26), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(u['name'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)), Text('${u['role'] == 'admin' ? 'Administrator' : 'Driver'} · ${u['email']}')]))])),
            title(context, 'Privacy'),
            const Text('Only the details needed for access checks are stored: name, student number, programme, route, card number, photo and the reason for qualifying. A student’s photo is shown only to the driver while the card is scanned. You only see what your role allows. All names shown here are fictional.'),
            title(context, 'Limitations'),
            Text(limits),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(onPressed: () { Navigator.pop(context); s.signOut(); }, icon: const Icon(Icons.logout), label: const Text('Sign out')),
            if (s.isAdmin)
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('Reset saved data?'),
                      content: const Text('This removes every student, trip and notice you added and restores the sample data.'),
                      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Reset'))],
                    ),
                  );
                  if (ok == true && context.mounted) { Navigator.pop(context); s.reset(); }
                },
                child: const Text('Reset saved data'),
              ),
          ]),
        ),
      ),
    );
  }
}
