import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../backend/sharing/library_transfer.dart';
import '../shared/pharmacy_state.dart';
import '../shared/screen.dart';

class LibrarySharingScreen extends StatelessWidget {
  const LibrarySharingScreen({super.key});

  @override
  Widget build(BuildContext context) => PharmacyScreen(
    children: [
      const Intro('', 'Передача аптеки', 'По QR-коду между двумя телефонами.'),
      PharmacyRow(
        icon: Icons.qr_code_2,
        title: 'Отправить',
        subtitle: 'Передать всю библиотеку',
        onTap: () => openScreen(context, const _SendLibrary()),
      ),
      const SizedBox(height: 10),
      PharmacyRow(
        icon: Icons.qr_code_scanner,
        title: 'Принять',
        subtitle: 'Загрузить библиотеку с другого телефона',
        onTap: () => openScreen(context, const _ReceiveLibrary()),
      ),
    ],
  );
}

class _SendLibrary extends StatefulWidget {
  const _SendLibrary();

  @override
  State<_SendLibrary> createState() => _SendLibraryState();
}

class _SendLibraryState extends State<_SendLibrary> {
  bool _busy = false;
  List<String>? _frames;
  String? _error;

  Future<void> _scan(String qr) async {
    if (_busy || _frames != null || !qr.startsWith('FPK1.')) return;
    final TransferRequest request;
    try {
      request = TransferRequest.parse(qr);
    } on FormatException {
      setState(() => _error = 'Не удалось прочитать QR принимающего телефона.');
      return;
    }
    final library = PharmacyScope.read(context).exportLibrary();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final frames = await LibraryTransfer.encode(request, library);
      if (mounted) setState(() => _frames = frames);
    } on FormatException {
      if (mounted) {
        setState(
          () => _error =
              'Ключ QR недействителен или библиотека слишком велика для передачи.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Не удалось зашифровать библиотеку.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final frames = _frames;
    return PharmacyScreen(
      children: [
        const Intro('', 'Отправить библиотеку', ''),
        if (frames != null) ...[
          const Text(
            'На принимающем телефоне нажмите «Сканировать библиотеку» и наведите камеру на этот экран.',
          ),
          const SizedBox(height: 16),
          _TransferCodes(frames: frames),
        ] else ...[
          const Text(
            'На другом телефоне откройте «Принять» и отсканируйте показанный там QR.',
          ),
          const SizedBox(height: 16),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else
            _QrCamera(onCode: _scan),
        ],
        if (_error != null) ...[const SizedBox(height: 12), Text(_error!)],
      ],
    );
  }
}

class _ReceiveLibrary extends StatefulWidget {
  const _ReceiveLibrary();

  @override
  State<_ReceiveLibrary> createState() => _ReceiveLibraryState();
}

class _ReceiveLibraryState extends State<_ReceiveLibrary> {
  LibraryRecipient? _recipient;
  LibraryFrames? _frames;
  Map<String, dynamic>? _library;
  bool _scanning = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
    unawaited(_keepScreenOn(true));
  }

  Future<void> _initialize() async {
    try {
      final recipient = await LibraryRecipient.create();
      if (!mounted) {
        recipient.dispose();
        return;
      }
      setState(() {
        _recipient = recipient;
        _frames = LibraryFrames(recipient.request.id);
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось создать ключ передачи.');
    }
  }

  Future<void> _scan(String qr) async {
    if (!_scanning || _busy || _library != null) return;
    final frames = _frames!;
    final before = frames.received;
    final received = frames.add(qr);
    if (received == null) {
      if (frames.received != before) setState(() {});
      return;
    }
    setState(() {
      _busy = true;
      _scanning = false;
      _error = null;
    });
    try {
      final library = await _recipient!.decrypt(received);
      if (mounted) setState(() => _library = library);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Не удалось подтвердить целостность библиотеки. Отсканируйте её заново.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _beginScan() => setState(() {
    _frames = LibraryFrames(_recipient!.request.id);
    _library = null;
    _scanning = true;
    _error = null;
  });

  Future<void> _replace() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Заменить библиотеку?'),
        content: const Text(
          'Текущие места, лекарства, расписания и корзина будут заменены полученными данными. Настройки телефона сохранятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Заменить'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PharmacyScope.read(context).replaceLibrary(_library!);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Библиотека принята')));
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Не удалось сохранить библиотеку. Текущие записи сохранены.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _recipient?.dispose();
    unawaited(_keepScreenOn(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recipient = _recipient;
    final library = _library;
    final received = _frames?.received ?? 0;
    final total = _frames?.total;

    return PopScope(
      canPop: !_busy,
      child: PharmacyScreen(
        children: [
          const Intro('', 'Принять библиотеку', ''),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else if (library != null) ...[
            const Text('Библиотека расшифрована.'),
            if (library['medicines'] case final List medicines)
              Text('Лекарств: ${medicines.length}'),
            const SizedBox(height: 16),
            PrimaryAction('Заменить библиотеку', onPressed: _replace),
          ] else if (_scanning) ...[
            Text(
              total == null
                  ? 'Наведите камеру на экран отправителя.'
                  : 'Кадры: $received из $total',
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: total == null ? 0 : received / total,
            ),
            const SizedBox(height: 16),
            _QrCamera(onCode: _scan),
            TextButton(
              onPressed: () => setState(() => _scanning = false),
              child: const Text('Показать мой QR'),
            ),
          ] else if (recipient != null) ...[
            const Text(
              'Покажите этот QR отправителю. Затем отсканируйте библиотеку с его экрана.',
            ),
            const SizedBox(height: 16),
            _QrTile(data: recipient.request.qr),
            const SizedBox(height: 16),
            PrimaryAction('Сканировать библиотеку', onPressed: _beginScan),
          ] else if (_error == null)
            const Center(child: CircularProgressIndicator())
          else
            TextButton(onPressed: _initialize, child: const Text('Повторить')),
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!)],
        ],
      ),
    );
  }
}

class _QrCamera extends StatefulWidget {
  const _QrCamera({required this.onCode});
  final ValueChanged<String> onCode;

  @override
  State<_QrCamera> createState() => _QrCameraState();
}

class _QrCameraState extends State<_QrCamera> {
  final _controller = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
    detectionTimeoutMs: 200,
  );

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              for (final code in capture.barcodes) {
                final value = code.rawValue;
                if (value != null) widget.onCode(value);
              }
            },
            errorBuilder: (context, _) => const Center(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Камера недоступна. Проверьте разрешение камеры в настройках Android.',
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _QrTile extends StatelessWidget {
  const _QrTile({required this.data});
  final String data;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: QrImageView(
        data: data,
        backgroundColor: Colors.white,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        padding: const EdgeInsets.all(18),
      ),
    ),
  );
}

class _TransferCodes extends StatefulWidget {
  const _TransferCodes({required this.frames});
  final List<String> frames;

  @override
  State<_TransferCodes> createState() => _TransferCodesState();
}

class _TransferCodesState extends State<_TransferCodes> {
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;
  bool _playing = true;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: _start,
      onPause: _pause,
      onInactive: _pause,
    );
    _start();
    unawaited(_keepScreenOn(true));
  }

  void _start() {
    if (!_playing || _timer != null || widget.frames.length <= 1) return;
    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) => _step(1));
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
  }

  void _step(int change) =>
      setState(() => _index = (_index + change) % widget.frames.length);

  @override
  void dispose() {
    _pause();
    _lifecycle.dispose();
    unawaited(_keepScreenOn(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _QrTile(data: widget.frames[_index]),
      if (widget.frames.length > 1) ...[
        const SizedBox(height: 10),
        Text('Кадр ${_index + 1} из ${widget.frames.length}'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Предыдущий кадр',
              onPressed: _playing ? null : () => _step(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: _playing ? 'Пауза' : 'Продолжить',
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                setState(() => _playing = !_playing);
                if (_playing) {
                  _start();
                } else {
                  _pause();
                }
              },
            ),
            IconButton(
              tooltip: 'Следующий кадр',
              onPressed: _playing ? null : () => _step(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    ],
  );
}

Future<void> _keepScreenOn(bool enabled) async {
  try {
    await const MethodChannel(
      'com.localpharmacy.app/sharing',
    ).invokeMethod<void>('keepScreenOn', enabled);
  } on MissingPluginException {
    // Screen-on control is optional outside the Android app.
  }
}
