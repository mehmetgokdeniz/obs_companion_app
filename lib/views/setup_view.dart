import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/obs_provider.dart';

/// Tek seferlik kurulum: API adresi ve erişim token'ı.
///
/// OBS kullanıcı adı/şifresi bu ekranda istenmez; giriş ve CAPTCHA ile
/// sunucunun kendisi ilgilenir.
class SetupView extends StatefulWidget {
  const SetupView({super.key});

  @override
  State<SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<SetupView> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final provider = context.read<ObsProvider>();
    final ok = await provider.connect(
      _urlController.text.trim(),
      _tokenController.text.trim(),
    );

    if (!mounted || ok) return;

    final message = provider.errorMessage ?? 'Bağlantı kurulamadı.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ObsProvider>();
    final busy = provider.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('OBS Companion Kurulum')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.link, size: 80, color: Colors.blue),
            const SizedBox(height: 12),
            Text(
              'API sunucuna bağlan',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Sunucudan aldığın adresi ve token\'ı gir. '
              'OBS giriş bilgilerin yalnızca sunucuda saklanır.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _urlController,
              enabled: !busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'API Adresi',
                hintText: 'https://xxxx.supabase.co/functions/v1',
                helperText: 'Supabase functions adresi ya da kendi sunucun',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.language),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tokenController,
              enabled: !busy,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Token',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: busy ? null : _submit,
                child: Text(
                  busy ? 'Bağlanıyor...' : 'Bağlan',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
            if (provider.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                provider.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
