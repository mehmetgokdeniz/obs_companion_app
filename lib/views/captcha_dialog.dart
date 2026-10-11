import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/obs_provider.dart';

/// Manuel güvenlik kodu diyalogunu açar.
Future<void> showCaptchaDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const CaptchaDialog(),
  );
}

/// Sunucu OCR ile çözemediğinde gösterilen görsel + giriş diyalogu.
class CaptchaDialog extends StatefulWidget {
  const CaptchaDialog({super.key});

  @override
  State<CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<CaptchaDialog> {
  final _codeController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Görsel henüz indirilmediyse açılışta iste.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ObsProvider>();
      if (provider.captchaImage == null) {
        provider.fetchCaptcha();
      }
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit(ObsProvider provider) async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _submitting = true);
    final ok = await provider.submitCaptcha(code);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    // Başarısız: sunucu taze görsel döndürmüş olabilir; alanı temizle.
    _codeController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ObsProvider>();
    final busy = _submitting || provider.isLoading;
    final image = provider.captchaImage;

    return AlertDialog(
      title: const Text('Güvenlik kodu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Görseldeki rakamların toplamını yaz.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: image == null
                ? const SizedBox(
                    width: 140,
                    height: 48,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Image.memory(
                    image,
                    width: 140,
                    height: 48,
                    fit: BoxFit.fill,
                    errorBuilder: (_, __, ___) =>
                        const Text('Görsel okunamadı.'),
                  ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeController,
            enabled: !busy,
            autofocus: true,
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _submit(provider),
            decoration: const InputDecoration(
              labelText: 'Cevap',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (provider.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              provider.errorMessage!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => provider.fetchCaptcha(),
          child: const Text('Yeni görsel'),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
        FilledButton(
          onPressed: busy ? null : () => _submit(provider),
          child: Text(busy ? 'Deneniyor...' : 'Gönder'),
        ),
      ],
    );
  }
}
