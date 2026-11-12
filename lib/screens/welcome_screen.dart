import 'package:flutter/material.dart' hide Text;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n_text.dart';
import '../models.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _url = TextEditingController(text: 'http://192.168.1.100:1234');
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _connect({bool skipCheck = false}) async {
    final address = _url.text.trim();
    if (address.isEmpty) {
      setState(() => _error = 'Укажите адрес компьютера');
      return;
    }
    final state = context.read<AppState>();
    final server = ServerConfig(
      id: newId(),
      name: 'Мой ПК',
      baseUrl: address,
      apiKey: _key.text.trim(),
    );
    final security = server.securityError;
    if (security != null) {
      setState(() => _error = security);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    if (!skipCheck) {
      final result = await state.refreshModels(server);
      if (!mounted) return;
      if (result.error != null) {
        setState(() {
          _busy = false;
          _error = result.error;
        });
        return;
      }
    }

    if (!mounted) return;
    state.addServer(server);
    state.setActiveServer(server.id);
    state.completeSetup();
  }

  void _later() {
    final state = context.read<AppState>();
    if (state.servers.isEmpty) {
      final server = ServerConfig(
        id: newId(),
        name: 'LM Studio',
        baseUrl: 'http://192.168.1.100:1234',
      );
      state.addServer(server);
      state.setActiveServer(server.id);
    }
    state.completeSetup();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final intro = _IntroPanel(wide: wide);
            final form = _buildForm(context, scheme);

            if (wide) {
              return Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.surfaceContainerLow,
                            scheme.surfaceContainerLowest,
                          ],
                        ),
                        border: Border(
                          right: BorderSide(
                            color: scheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(48),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 430),
                            child: intro,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(40),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: form,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [intro, const SizedBox(height: 28), form],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Подключение к LM Studio',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 5),
        Text(
          'Укажите адрес компьютера в локальной сети.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: L10n.t('Адрес LM Studio'),
            hintText: 'http://192.168.1.50:1234',
            prefixIcon: const Icon(Icons.computer_rounded, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          obscureText: true,
          decoration: InputDecoration(
            labelText: L10n.t('API-токен (необязательно)'),
            prefixIcon: const Icon(Icons.key_rounded, size: 20),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 18, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _busy ? null : () => _connect(),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Подключиться', style: TextStyle(fontSize: 15)),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton(
              onPressed: _busy ? null : () => _connect(skipCheck: true),
              child: const Text('Сохранить без проверки'),
            ),
            TextButton(
              onPressed: _busy ? null : _later,
              child: const Text('Настроить позже'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Подготовка LM Studio',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '1. Developer → Start Server (порт 1234).\n'
                  '2. Включите «Serve on Local Network».\n'
                  '3. IP на Ubuntu: hostname -I.\n'
                  '4. Телефон и ПК – в одной Wi-Fi сети.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(height: 1.55, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IntroPanel extends StatelessWidget {
  const _IntroPanel({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.tertiary],
            ),
          ),
          child: Icon(Icons.forum_rounded, size: 36, color: scheme.onPrimary),
        ),
        const SizedBox(height: 22),
        Text(
          'LM Chat',
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Общайтесь с моделями, которые запущены на вашем компьютере. '
          'Запросы не покидают домашнюю сеть.',
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(height: 1.5, color: scheme.onSurfaceVariant),
        ),
        if (wide) ...[
          const SizedBox(height: 28),
          const _Benefit(
            icon: Icons.lock_outline_rounded,
            text: 'Без облака и аккаунтов',
          ),
          const SizedBox(height: 12),
          const _Benefit(
            icon: Icons.wifi_rounded,
            text: 'Работает в локальной сети и через Tailscale',
          ),
          const SizedBox(height: 12),
          const _Benefit(
            icon: Icons.devices_rounded,
            text: 'История, параметры и промпты остаются на устройстве',
          ),
        ],
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
