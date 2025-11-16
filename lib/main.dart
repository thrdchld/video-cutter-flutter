// =============================================================
// Video Cutter – Flutter Native (using ffmpeg_kit_flutter_new ^4.1.0)
// =============================================================
// Fitur:
// - Pilih file video
// - Masukkan timestamp range (multi-line)
// - Preview & simple edit (list of segments)
// - Potong video menggunakan FFmpegKit (ffmpeg_kit_flutter_new)
// - Output ke folder aplikasi (getApplicationDocumentsDirectory)
// - Opsi ZIP
// -------------------------------------------------------------
// Pastikan pubspec.yaml mencantumkan:
// ffmpeg_kit_flutter_new: ^4.1.0
// file_picker, path_provider, permission_handler, archive
// =============================================================

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive_io.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/media_information_session.dart';
import 'package:ffmpeg_kit_flutter_new/media_information.dart';

void main() {
  runApp(const VideoCutterApp());
}

class VideoCutterApp extends StatelessWidget {
  const VideoCutterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Video Cutter Native",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

// ------------------------ Home ------------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<PlatformFile> pickedFiles = [];
  final TextEditingController timestampsCtrl = TextEditingController();
  final TextEditingController folderCtrl = TextEditingController();
  final TextEditingController mergeGapCtrl = TextEditingController(text: "0");
  bool overwrite = false;
  bool zipOutput = false;

  Future<void> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    if (result != null) {
      setState(() => pickedFiles = result.files);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Video Cutter — Native"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ElevatedButton.icon(
            onPressed: pickFiles,
            icon: const Icon(Icons.video_file),
            label: const Text("Pilih File Video"),
          ),
          if (pickedFiles.isNotEmpty)
            Column(
              children: pickedFiles.map((f) {
                return ListTile(
                  leading: const Icon(Icons.movie),
                  title: Text(f.name),
                  subtitle: Text("${(f.size / 1024 / 1024).toStringAsFixed(2)} MB"),
                );
              }).toList(),
            ),
          const SizedBox(height: 16),
          const Text("Timestamp (satu baris = satu range):"),
          TextField(
            controller: timestampsCtrl,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: "00:00:05.000 - 00:00:20.500\n00:00:30 - 00:00:45",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text("Nama folder output (opsional):"),
          TextField(
            controller: folderCtrl,
            decoration: const InputDecoration(
              hintText: "myfolder",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Text("Merge gap (detik):")),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: mergeGapCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              )
            ],
          ),
          SwitchListTile(
            title: const Text("Overwrite output"),
            value: overwrite,
            onChanged: (v) => setState(() => overwrite = v),
          ),
          SwitchListTile(
            title: const Text("ZIP semua hasil"),
            value: zipOutput,
            onChanged: (v) => setState(() => zipOutput = v),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              if (pickedFiles.isEmpty) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text("Pilih minimal 1 video")));
                return;
              }
              if (timestampsCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text("Masukkan timestamp")));
                return;
              }
              final mergeGap = double.tryParse(mergeGapCtrl.text) ?? 0.0;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PreviewPage(
                    files: pickedFiles,
                    timestamps: timestampsCtrl.text,
                    baseName: folderCtrl.text.trim(),
                    mergeGap: mergeGap,
                    overwrite: overwrite,
                    zipOutput: zipOutput,
                  ),
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text("Preview Segmen"),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------ Utilities ------------------------
double? parseTimeToSeconds(String input) {
  if (input == null || input.trim().isEmpty) return null;
  var s = input.trim().replaceAll(",", ".");
  if (s.contains(":")) {
    final parts = s.split(":").map((p) => p.trim()).toList();
    try {
      if (parts.length == 3) {
        final h = double.tryParse(parts[0]) ?? 0;
        final m = double.tryParse(parts[1]) ?? 0;
        final secParts = parts[2].split(".");
        final sec = double.tryParse(secParts[0]) ?? 0;
        final ms = secParts.length > 1 ? double.tryParse("0.${secParts[1]}") ?? 0 : 0;
        return h * 3600 + m * 60 + sec + ms;
      } else if (parts.length == 2) {
        final m = double.tryParse(parts[0]) ?? 0;
        final secParts = parts[1].split(".");
        final sec = double.tryParse(secParts[0]) ?? 0;
        final ms = secParts.length > 1 ? double.tryParse("0.${secParts[1]}") ?? 0 : 0;
        return m * 60 + sec + ms;
      }
    } catch (_) {
      return double.tryParse(s);
    }
  }
  return double.tryParse(s);
}

String secondsToHhmmssms(double sec) {
  final total = sec.floor();
  final ms = ((sec - total) * 1000).round();
  final s = total % 60;
  final m = (total ~/ 60) % 60;
  final h = total ~/ 3600;
  return '${h.toString().padLeft(2, "0")}:${m.toString().padLeft(2, "0")}:${s.toString().padLeft(2, "0")}.${ms.toString().padLeft(3, "0")}';
}

List<Map<String, double>> parseRanges(String text) {
  final out = <Map<String, double>>[];
  final lines = text.split('\n');
  for (var ln in lines) {
    ln = ln.trim();
    if (ln.isEmpty) continue;
    // normalize separators
    ln = ln.replaceAll('\u2013', '-').replaceAll('\u2014', '-').replaceAll('->', '-').replaceAll('\u2192', '-');
    final separators = [' to ', ',', '\t', ' - ', '-', ' '];
    bool parsed = false;
    for (var sep in separators) {
      if (ln.contains(sep)) {
        final parts = ln.split(sep);
        if (parts.length >= 2) {
          final s = parseTimeToSeconds(parts[0]);
          final e = parseTimeToSeconds(parts.sublist(1).join(sep));
          if (s != null && e != null && e > s) {
            out.add({'start': s, 'end': e});
            parsed = true;
            break;
          }
        }
      }
    }
    if (!parsed) {
      // try whitespace split
      final toks = ln.split(RegExp('\\s+'));
      if (toks.length >= 2) {
        final s = parseTimeToSeconds(toks[0]);
        final e = parseTimeToSeconds(toks[1]);
        if (s != null && e != null && e > s) out.add({'start': s, 'end': e});
      }
    }
  }
  return out;
}

// ------------------------ Preview Page ------------------------
class PreviewPage extends StatefulWidget {
  final List<PlatformFile> files;
  final String timestamps;
  final String baseName;
  final double mergeGap;
  final bool overwrite;
  final bool zipOutput;

  const PreviewPage({
    super.key,
    required this.files,
    required this.timestamps,
    required this.baseName,
    required this.mergeGap,
    required this.overwrite,
    required this.zipOutput,
  });

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  late List<Map<String, double>> ranges;

  @override
  void initState() {
    super.initState();
    ranges = parseRanges(widget.timestamps);
    // optional: merge ranges if mergeGap > 0
    if (widget.mergeGap > 0 && ranges.isNotEmpty) {
      ranges = mergeRanges(ranges, widget.mergeGap);
    }
  }

  List<Map<String, double>> mergeRanges(List<Map<String, double>> r, double gap) {
    final list = r.map((e) => [e['start']!, e['end']!]).toList();
    list.sort((a, b) => a[0].compareTo(b[0]));
    final merged = <List<double>>[];
    merged.add([list[0][0], list[0][1]]);
    for (var i = 1; i < list.length; i++) {
      final cur = list[i];
      final last = merged.last;
      if (cur[0] <= last[1] + gap) {
        last[1] = cur[1] > last[1] ? cur[1] : last[1];
      } else {
        merged.add([cur[0], cur[1]]);
      }
    }
    return merged.map((m) => {'start': m[0], 'end': m[1]}).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview Segmen'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: ranges.length,
                itemBuilder: (context, idx) {
                  final seg = ranges[idx];
                  return Card(
                    child: ListTile(
                      title: Text('Seg #${idx + 1}'),
                      subtitle: Text('${secondsToHhmmssms(seg['start']!)} — ${secondsToHhmmssms(seg['end']!)}'),
                    ),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: ranges.isEmpty
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProcessPage(
                            files: widget.files,
                            ranges: ranges,
                            baseName: widget.baseName,
                            overwrite: widget.overwrite,
                            zipOutput: widget.zipOutput,
                          ),
                        ),
                      );
                    },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Start Processing'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------ Process Page ------------------------
class ProcessPage extends StatefulWidget {
  final List<PlatformFile> files;
  final List<Map<String, double>> ranges;
  final String baseName;
  final bool overwrite;
  final bool zipOutput;

  const ProcessPage({
    super.key,
    required this.files,
    required this.ranges,
    required this.baseName,
    required this.overwrite,
    required this.zipOutput,
  });

  @override
  State<ProcessPage> createState() => _ProcessPageState();
}

class _ProcessPageState extends State<ProcessPage> {
  int totalSegments = 0;
  int doneSegments = 0;
  String status = 'Idle';
  late Directory outputBase;

  @override
  void initState() {
    super.initState();
    totalSegments = widget.ranges.length * widget.files.length;
    _startProcessing();
  }

  Future<void> _startProcessing() async {
    setState(() => status = 'Preparing storage...');
    await _ensurePermissions();
    outputBase = await _prepareOutputFolder(widget.baseName);
    setState(() => status = 'Starting cuts...');

    int fileIdx = 0;
    for (final pf in widget.files) {
      fileIdx++;
      final srcPath = pf.path;
      if (srcPath == null) {
        setState(() => status = 'Skipping ${pf.name} (no path)');
        continue;
      }

      final localCopy = await _copyToAppTemp(File(srcPath));

      int segIdx = 0;
      for (final r in widget.ranges) {
        segIdx++;
        final s = r['start']!;
        final e = r['end']!;
        final outName = '${fileIdx}_${segIdx}.mp4';
        final outPath = '${outputBase.path}/$outName';

        // avoid overwrite unless requested
        if (File(outPath).existsSync() && !widget.overwrite) {
          setState(() {
            doneSegments++;
          });
          continue;
        }

        setState(() => status = 'Cutting ${pf.name} seg $segIdx');

        // FFmpeg command: copy codec for fast trim
        final cmd = '-y -ss $s -to $e -i "${localCopy.path}" -c copy "$outPath"';

        final session = await FFmpegKit.execute(cmd);
        final rc = await session.getReturnCode();

        if (ReturnCode.isSuccess(rc)) {
          setState(() {
            doneSegments++;
          });
        } else {
          final failMessage = 'FFmpeg failed for ${pf.name} seg $segIdx (rc=${rc?.getValue() ?? "null"})';
          setState(() => status = failMessage);
          // continue to next segment
        }
      }
    }

    if (widget.zipOutput) {
      setState(() => status = 'Creating ZIP...');
      await _createZip(outputBase);
    }

    setState(() => status = 'Finished');
  }

  Future<void> _ensurePermissions() async {
    // we use FilePicker so READ permission may be needed on some devices
    if (Platform.isAndroid) {
      final st = await Permission.storage.status;
      if (!st.isGranted) {
        await Permission.storage.request();
      }
    }
  }

  Future<Directory> _prepareOutputFolder(String baseName) async {
    final doc = await getApplicationDocumentsDirectory();
    final date = DateTime.now();
    final dateStr = '${date.year.toString().padLeft(4, "0")}${date.month.toString().padLeft(2, "0")}${date.day.toString().padLeft(2, "0")}';
    final sanitized = (baseName.isEmpty) ? 'default' : baseName.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    final dir = Directory('${doc.path}/outputs/$sanitized/$dateStr-run1');
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _copyToAppTemp(File src) async {
    final tmp = await getTemporaryDirectory();
    final dst = File('${tmp.path}/${src.uri.pathSegments.last}');
    await dst.writeAsBytes(await src.readAsBytes());
    return dst;
  }

  Future<void> _createZip(Directory dir) async {
    final zipEncoder = ZipFileEncoder();
    final zipPath = '${dir.path}/all_results.zip';
    zipEncoder.create(zipPath);
    for (final f in dir.listSync()) {
      if (f is File && (f.path.endsWith('.mp4') || f.path.endsWith('.zip'))) {
        zipEncoder.addFile(f);
      }
    }
    zipEncoder.close();
  }

  @override
  Widget build(BuildContext context) {
    final pct = totalSegments == 0 ? 0.0 : (doneSegments / totalSegments);
    return Scaffold(
      appBar: AppBar(title: const Text('Processing')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(status),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: pct),
            const SizedBox(height: 12),
            Text('Done: $doneSegments / $totalSegments'),
            const Spacer(),
            if (status == 'Finished')
              ElevatedButton(
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                child: const Text('Selesai'),
              ),
          ],
        ),
      ),
    );
  }
}
