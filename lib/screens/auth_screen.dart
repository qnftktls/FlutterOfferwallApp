import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/settings_repository.dart';
import '../theme/app_theme.dart';

/// Email/password sign-in + sign-up screen (Firebase Auth), with a guest option.
///
/// Presented as a full screen the user can dismiss (guest) or complete (sign in).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _isSignUp = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validEmail(String v) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

  Future<void> _submit() async {
    final AppLocalizations l = context.l10n;
    final String email = _email.text.trim();
    final String password = _password.text;

    setState(() => _error = null);
    if (!_validEmail(email)) {
      setState(() => _error = l.t('invalid_email'));
      return;
    }
    if (password.length < 6) {
      setState(() => _error = l.t('weak_password'));
      return;
    }

    setState(() => _busy = true);
    final AuthService auth = AuthService.instance;
    final AuthResult res =
        _isSignUp ? await auth.signUp(email, password) : await auth.signIn(email, password);

    if (!mounted) return;
    setState(() => _busy = false);

    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = l.t('auth_error').replaceAll('{msg}', res.error ?? ''));
    }
  }

  Future<void> _forgot() async {
    final AppLocalizations l = context.l10n;
    final String email = _email.text.trim();
    if (!_validEmail(email)) {
      setState(() => _error = l.t('invalid_email'));
      return;
    }
    final AuthResult res = await AuthService.instance.sendPasswordReset(email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.ok ? l.t('reset_email_sent') : l.t('auth_error').replaceAll('{msg}', res.error ?? ''),
        ),
      ),
    );
  }

  void _guest() {
    AuthService.instance.continueAsGuest();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = context.l10n;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: l.t('language'),
            onPressed: SettingsRepository.instance.toggleLocale,
            icon: const Icon(Icons.translate_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: <Widget>[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[AppColors.brandPrimary, Color(0xFF14507F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.stars_rounded,
                  color: AppColors.brandAccent, size: 32),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              _isSignUp ? l.t('sign_up_title') : l.t('sign_in_title'),
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 4),
            Text(
              _isSignUp ? l.t('sign_up_sub') : l.t('sign_in_sub'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),

            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const <String>[AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l.t('email'),
                prefixIcon: const Icon(Icons.mail_outline_rounded),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const <String>[AutofillHints.password],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l.t('password'),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: const OutlineInputBorder(),
              ),
            ),

            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  const Icon(Icons.error_outline_rounded,
                      color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],

            if (!_isSignUp)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _forgot,
                  child: Text(l.t('forgot_password')),
                ),
              )
            else
              const SizedBox(height: AppSpacing.sm),

            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF04121F),
                        ),
                      )
                    : Text(
                        _isSignUp ? l.t('create_account') : l.t('sign_in'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _isSignUp = !_isSignUp;
                          _error = null;
                        }),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                child: Text(
                  _isSignUp
                      ? '${l.t('already_have')}${l.t('sign_in')}'
                      : '${l.t('no_account')}${l.t('create_account')}',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _busy ? null : _guest,
              child: Text(l.t('continue_guest')),
            ),
          ],
        ),
      ),
    );
  }
}
