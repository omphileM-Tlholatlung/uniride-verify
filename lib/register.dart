// Boarding register: builds the PDF and Excel (CSV) files for a trip.
import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'data.dart';
import 'location.dart';

const _navy = PdfColor.fromInt(0xFF0B1F4B), _green = PdfColor.fromInt(0xFF16A34A), _red = PdfColor.fromInt(0xFFDC2626), _amber = PdfColor.fromInt(0xFFD97706), _soft = PdfColor.fromInt(0xFFF4F6FB);
PdfColor _col(String r) => r == authorised ? _green : (r == rejected ? _red : _amber);

/// The built-in PDF font only covers Western characters, so anything else is dropped.
String _t(Object? v) => (v ?? '').toString().replaceAll('’', "'").replaceAll(RegExp(r'[^\u0000-\u00FF]'), '');
String _initials(String n) => n.split(' ').where((e) => e.isNotEmpty).map((e) => e[0]).take(2).join().toUpperCase();
String _safe(String x) => x.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');

/// File name without extension, e.g. UniRide_Register_Route_1_Mdantsane_2026-11-10_0630
String registerName(Store s, String tid) {
  final trip = s.find('trips', tid)!;
  return 'UniRide_Register_${_safe(s.nameOf('routes', trip['routeId']))}_${ymd(DateTime.fromMillisecondsSinceEpoch(trip['startedAt']))}_${hm(trip['startedAt']).replaceAll(':', '')}';
}

/// Excel-friendly CSV (UTF-8 with a byte-order mark so Excel opens it correctly).
String registerCsv(Store s, String tid) {
  final trip = s.find('trips', tid)!;
  final route = s.nameOf('routes', trip['routeId']), veh = s.nameOf('vehicles', trip['vehicleId']), drv = s.nameOf('users', trip['driverId']);
  String q(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
  final rows = <String>['Date,Time,Student,Student number,Course,Year,Residence,Result,Details,Route,Vehicle,Driver,Latitude,Longitude'];
  for (final x in s.scansOf(tid).reversed) {
    final st = s.find('students', x['studentId']);
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
      route,
      veh,
      drv,
      x['lat'] ?? '',
      x['lng'] ?? '',
    ].map(q).join(','));
  }
  return '\uFEFF${rows.join('\r\n')}';
}

pw.Widget _photo(M? st) {
  final b = st?['photo'] as String?;
  if (b != null && b.isNotEmpty) {
    return pw.ClipOval(child: pw.Image(pw.MemoryImage(base64Decode(b)), width: 26, height: 26, fit: pw.BoxFit.cover));
  }
  return pw.Container(
    width: 26,
    height: 26,
    alignment: pw.Alignment.center,
    decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100, shape: pw.BoxShape.circle),
    child: pw.Text(_t(_initials(st?['name'] ?? '?')), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _navy)),
  );
}

Future<Uint8List> registerPdf(Store s, String tid) async {
  final trip = s.find('trips', tid)!;
  final veh = s.find('vehicles', trip['vehicleId']);
  final start = DateTime.fromMillisecondsSinceEpoch(trip['startedAt']);
  final endedAt = trip['endedAt'] as int?;
  final scans = s.scansOf(tid).reversed.toList();
  final ok = s.countOf(tid, authorised), bad = s.countOf(tid, rejected), un = s.countOf(tid, unable);
  final doc = pw.Document(title: 'UniRide boarding register', author: 'UniRide Verify');

  pw.Widget cell(String text, {bool bold = false, PdfColor? color, double size = 8.5}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: pw.Text(_t(text), style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
      );
  pw.Widget info(String k, String v) => pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(k.toUpperCase(), style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
          pw.SizedBox(height: 2),
          pw.Text(_t(v), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ]),
      );
  pw.Widget box(String label, int n, PdfColor c) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 8),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(color: _soft, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('$n', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: c)),
            pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ]),
        ),
      );
  pw.Widget sig(String l) => pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(height: .6, color: PdfColors.grey700),
          pw.SizedBox(height: 3),
          pw.Text(l, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ]),
      );

  final rows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: const pw.BoxDecoration(color: _navy),
      children: [for (final h in ['#', '', 'Student', 'Student no.', 'Course', 'Year', 'Residence', 'Time', 'Result', 'Details']) cell(h, bold: true, color: PdfColors.white)],
    ),
  ];
  for (var i = 0; i < scans.length; i++) {
    final x = scans[i];
    final st = s.find('students', x['studentId']);
    final res = x['result'] as String;
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _soft),
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        cell('${i + 1}'),
        pw.Padding(padding: const pw.EdgeInsets.all(3), child: _photo(st)),
        cell('${st?['name'] ?? 'Unknown card ${x['code']}'}', bold: true),
        cell('${st?['no'] ?? '-'}'),
        cell('${st?['programme'] ?? '-'}'),
        cell('${st?['year'] ?? '-'}'),
        cell('${st?['residence'] ?? '-'}'),
        cell(hm(x['ts'])),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(color: _col(res), borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Text(_t(res), style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          ),
        ),
        cell('${res == authorised ? '' : x['reason']}${x['lat'] == null ? '' : '${res == authorised ? '' : '\n'}GPS ${fixOf(x)}'}', size: 7),
      ],
    ));
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 34),
    footer: (c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('UniRide Verify  |  Generated ${ymd(DateTime.now())} ${hm(nowMs())}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      pw.Text('Page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
    ]),
    build: (c) => [
      pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(color: _navy, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('UniRide Verify', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            pw.SizedBox(height: 2),
            pw.Text('Student shuttle boarding register', style: const pw.TextStyle(fontSize: 10, color: PdfColors.blue100)),
          ]),
          pw.Text(ymd(start), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
        ]),
      ),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        info('Route', s.nameOf('routes', trip['routeId'])),
        info('Vehicle', veh == null ? '-' : '${veh['label']} (${veh['reg']})'),
        info('Driver', s.nameOf('users', trip['driverId'])),
        info('Started', hm(trip['startedAt'])),
        info('Ended', endedAt == null ? 'In progress' : hm(endedAt)),
      ]),
      pw.SizedBox(height: 12),
      pw.Row(children: [box('Boarded (authorised)', ok, _green), box('Not authorised', bad, _red), box('Unable to verify', un, _amber), box('Total scans', scans.length, _navy)]),
      pw.SizedBox(height: 14),
      if (scans.isEmpty)
        pw.Text('No student cards were scanned on this trip.', style: const pw.TextStyle(fontSize: 10))
      else
        pw.Table(
          border: const pw.TableBorder(bottom: pw.BorderSide(color: PdfColors.grey400, width: .5)),
          columnWidths: const {
            0: pw.FixedColumnWidth(22),
            1: pw.FixedColumnWidth(34),
            2: pw.FlexColumnWidth(2.2),
            3: pw.FixedColumnWidth(62),
            4: pw.FlexColumnWidth(2),
            5: pw.FixedColumnWidth(58),
            6: pw.FlexColumnWidth(1.6),
            7: pw.FixedColumnWidth(34),
            8: pw.FixedColumnWidth(66),
            9: pw.FlexColumnWidth(1.6),
          },
          children: rows,
        ),
      pw.SizedBox(height: 34),
      pw.Row(children: [sig('Driver signature'), pw.SizedBox(width: 40), sig('Administrator signature'), pw.SizedBox(width: 40), sig('Date')]),
    ],
  ));
  return doc.save();
}

Future<void> shareRegisterPdf(Store s, String tid) async {
  final bytes = await registerPdf(s, tid);
  await Printing.sharePdf(bytes: bytes, filename: '${registerName(s, tid)}.pdf', subject: 'UniRide boarding register');
}

Future<void> previewRegister(Store s, String tid) async {
  await Printing.layoutPdf(onLayout: (_) => registerPdf(s, tid), name: registerName(s, tid));
}

Future<void> shareRegisterCsv(Store s, String tid) async {
  final name = '${registerName(s, tid)}.csv';
  final bytes = Uint8List.fromList(utf8.encode(registerCsv(s, tid)));
  await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'text/csv', name: name)], fileNameOverrides: [name], subject: 'UniRide boarding register');
}

Future<void> shareScansCsv(Store s, int days) async {
  final name = 'UniRide_Verification_Report_${ymd(DateTime.now())}_last_${days}_days.csv';
  final bytes = Uint8List.fromList(utf8.encode(s.scansCsv(days)));
  await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'text/csv', name: name)], fileNameOverrides: [name], subject: 'UniRide verification report');
}

/// Summary report for the last [days] days: totals, results by route, and the exceptions list.
Future<Uint8List> reportPdf(Store s, int days) async {
  final sc = s.scansIn(days)..sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
  int n(List<M> l, String r) => l.where((x) => x['result'] == r).length;
  final rate = sc.isEmpty ? 0 : (n(sc, authorised) * 100 / sc.length).round();
  final tripRoute = {for (final t in s.t('trips')) t['id']: t['routeId']};
  final exceptions = sc.where((x) => x['result'] != authorised).take(40).toList();
  final doc = pw.Document(title: 'UniRide verification report', author: 'UniRide Verify');

  pw.Widget cell(String text, {bool bold = false, PdfColor? color, double size = 9}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: pw.Text(_t(text), style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
      );
  pw.Widget box(String label, String v, PdfColor c) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 8),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: _soft, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(v, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: c)),
            pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ]),
        ),
      );
  pw.TableRow head(List<String> h) => pw.TableRow(decoration: const pw.BoxDecoration(color: _navy), children: [for (final x in h) cell(x, bold: true, color: PdfColors.white)]);
  pw.Widget heading(String t) => pw.Padding(padding: const pw.EdgeInsets.only(top: 16, bottom: 6), child: pw.Text(t, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _navy)));

  final routeRows = <pw.TableRow>[head(['Route', 'Scans', 'Authorised', 'Not authorised', 'Unable to verify'])];
  final routes = s.t('routes');
  for (var i = 0; i < routes.length; i++) {
    final r = routes[i];
    final l = sc.where((x) => tripRoute[x['tripId']] == r['id']).toList();
    routeRows.add(pw.TableRow(decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _soft), children: [cell('${r['name']}', bold: true), cell('${l.length}'), cell('${n(l, authorised)}'), cell('${n(l, rejected)}'), cell('${n(l, unable)}')]));
  }
  final exRows = <pw.TableRow>[head(['Time', 'Student / card', 'Result', 'Reason', 'Reviewed'])];
  for (var k = 0; k < exceptions.length; k++) {
    final x = exceptions[k], st = s.find('students', x['studentId']);
    exRows.add(pw.TableRow(decoration: pw.BoxDecoration(color: k.isEven ? PdfColors.white : _soft), children: [
      cell(dm(x['ts']), size: 8),
      cell('${st?['name'] ?? 'Unknown card ${x['code']}'}', size: 8),
      cell('${x['result']}', size: 8, color: _col(x['result'])),
      cell('${x['reason']}', size: 8),
      cell(x['reviewed'] == true ? 'Yes' : 'No', size: 8),
    ]));
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 38),
    footer: (c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('UniRide Verify  |  Generated ${ymd(DateTime.now())} ${hm(nowMs())}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      pw.Text('Page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
    ]),
    build: (c) => [
      pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(color: _navy, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('UniRide Verify', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          pw.SizedBox(height: 2),
          pw.Text('Verification report: last $days days (to ${ymd(DateTime.now())})', style: const pw.TextStyle(fontSize: 10, color: PdfColors.blue100)),
        ]),
      ),
      pw.SizedBox(height: 14),
      pw.Row(children: [box('Total scans', '${sc.length}', _navy), box('Authorised ($rate%)', '${n(sc, authorised)}', _green), box('Not authorised', '${n(sc, rejected)}', _red), box('Unable to verify', '${n(sc, unable)}', _amber)]),
      heading('Results by route'),
      pw.Table(columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1.4), 3: pw.FlexColumnWidth(1.6), 4: pw.FlexColumnWidth(1.6)}, children: routeRows),
      heading('Exceptions (most recent ${exceptions.length})'),
      if (exceptions.isEmpty)
        pw.Text('No exceptions in this period.', style: const pw.TextStyle(fontSize: 10))
      else
        pw.Table(columnWidths: const {0: pw.FixedColumnWidth(70), 1: pw.FlexColumnWidth(2), 2: pw.FixedColumnWidth(78), 3: pw.FlexColumnWidth(2.4), 4: pw.FixedColumnWidth(50)}, children: exRows),
    ],
  ));
  return doc.save();
}

Future<void> shareReportPdf(Store s, int days) async {
  final bytes = await reportPdf(s, days);
  await Printing.sharePdf(bytes: bytes, filename: 'UniRide_Verification_Report_${ymd(DateTime.now())}_last_${days}_days.pdf', subject: 'UniRide verification report');
}
