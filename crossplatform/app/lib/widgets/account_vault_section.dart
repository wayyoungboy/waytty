import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:waytty_l10n/waytty_l10n.dart';

import '../providers/account_vault_provider.dart';
import '../providers/host_provider.dart';
import '../providers/sync_provider.dart';
import '../services/sync_service.dart';
import 'confirm_dialog.dart';

/// Shared account experience for desktop and Android layouts.
class AccountVaultSection extends StatefulWidget {
  const AccountVaultSection({super.key});

  @override
  State<AccountVaultSection> createState() => _AccountVaultSectionState();
}

class _AccountVaultSectionState extends State<AccountVaultSection> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _vaultPassword = TextEditingController();
  final _vaultConfirm = TextEditingController();
  final _code = TextEditingController();
  Timer? _countdown;
  final _form = GlobalKey<FormState>();
  final _vaultForm = GlobalKey<FormState>();
  bool _register = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          context.read<SyncProvider>().account.pendingEmail != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _code.dispose();
    for (final controller in [
      _email,
      _password,
      _confirm,
      _vaultPassword,
      _vaultConfirm,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _authenticate(AccountVaultProvider account) async {
    if (!_form.currentState!.validate()) return;
    final pending = account.authenticate(
      _email.text,
      _password.text,
      register: _register,
    );
    _password.clear();
    _confirm.clear();
    await pending;
  }

  Future<String> _snapshot(HostProvider hosts) async {
    await hosts.ready;
    if (hosts.loadError != null) {
      throw StateError('Local connections unavailable');
    }
    return SyncService.buildPayload(
      hosts: hosts.allHosts,
      passwords: await hosts.loadAllPasswords(),
    );
  }

  String _contents(String snapshot) {
    final data = jsonDecode(snapshot) as Map<String, dynamic>;
    data.remove('updated_at');
    return jsonEncode(data);
  }

  Future<void> _save(SyncProvider sync) async {
    final hosts = context.read<HostProvider>();
    if (sync.account.hasRemoteVault) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Replace cloud backup?',
        message:
            'Save this device’s connections to the cloud? Existing cloud passwords are kept when not re-entered; removing a connection removes its password from the backup. Other devices are not changed automatically.',
        confirmLabel: 'Save to cloud',
      );
      if (!confirmed || !mounted || sync.mode != DataMode.cloudAccount) return;
    }
    await sync.account.save(() => _snapshot(hosts));
  }

  Future<void> _restore(SyncProvider sync) async {
    final hosts = context.read<HostProvider>();
    final confirmed = await showConfirmDialog(
      context,
      title: 'Restore cloud connections?',
      message:
          'This replaces this device’s connection list and saved connection passwords. Local notes, private key files and other settings are kept.',
      confirmLabel: 'Restore',
      destructive: true,
    );
    if (!confirmed || !mounted || sync.mode != DataMode.cloudAccount) return;
    setState(() => _restoring = true);
    final generation = sync.modeGeneration;
    try {
      final before = _contents(await _snapshot(hosts));
      final payload = await sync.account.download();
      if (payload == null || !mounted || generation != sync.modeGeneration) {
        return;
      }
      if (_contents(await _snapshot(hosts)) != before) {
        sync.account.reportRestore(success: false);
        return;
      }
      if (!mounted || generation != sync.modeGeneration) return;
      await hosts.replaceAll(
        payload.hosts,
        payload.passwords,
        clearMissingPasswords: true,
      );
      sync.account.reportRestore(success: true);
    } catch (_) {
      if (generation == sync.modeGeneration) {
        sync.account.reportRestore(success: false);
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
    String? Function(String?)? validator,
    Iterable<String>? autofillHints,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: controller,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: !secret,
      keyboardType: secret
          ? TextInputType.visiblePassword
          : TextInputType.emailAddress,
      autofillHints: autofillHints,
      decoration: InputDecoration(
        labelText: tr(context, label),
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    final account = sync.account;
    final cloud = sync.mode == DataMode.cloudAccount;
    final busy = account.busy || _restoring;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LText(
              'Connection storage',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const LText('Local offline'),
                  selected: sync.mode == DataMode.local,
                  onSelected: _restoring
                      ? null
                      : (_) {
                          _password.clear();
                          _confirm.clear();
                          _vaultPassword.clear();
                          _vaultConfirm.clear();
                          sync.selectMode(DataMode.local);
                        },
                ),
                ChoiceChip(
                  label: const LText('Cloud account'),
                  selected: cloud,
                  onSelected: _restoring
                      ? null
                      : (_) => sync.selectMode(DataMode.cloudAccount),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!cloud)
              LText(
                'No account required. Connections stay on this device and cloud backup is disabled.',
              ),
            if (cloud) ...[
              const LText(
                'Connections work offline too. Save and restore cloud backups manually.',
              ),
              const SizedBox(height: 8),
              if (!account.config.isConfigured)
                const LText(
                  'Cloud service is not configured in this build. Local mode is available.',
                )
              else if (account.pendingEmail != null) ...[
                const SizedBox(height: 12),
                LText(
                  LMessage('Verify your email: {0}', [account.pendingEmail!]),
                ),
                const SizedBox(height: 8),
                const LText(
                  'Enter the 6-digit code from your latest email. The code expires after 10 minutes.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  autocorrect: false,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Email verification code'),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: busy
                      ? null
                      : (_) => account.verifyEmail(_code.text),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final verification = account.verifyEmail(
                                _code.text,
                              );
                              _code.clear();
                              await verification;
                            },
                      child: const LText('Verify email'),
                    ),
                    TextButton(
                      onPressed: busy || account.resendSeconds > 0
                          ? null
                          : account.resendVerification,
                      child: LText(
                        account.resendSeconds > 0
                            ? LMessage('Resend in {0}s', [
                                account.resendSeconds,
                              ])
                            : 'Resend code',
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              _code.clear();
                              account.disconnect();
                            },
                      child: const LText('Use another email'),
                    ),
                  ],
                ),
              ] else if (!account.signedIn)
                Form(
                  key: _form,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _field(
                          _email,
                          'Account email',
                          autofillHints: const [AutofillHints.email],
                          validator: (v) =>
                              AccountVaultProvider.validEmail((v ?? '').trim())
                              ? null
                              : tr(context, 'Enter a valid email address.'),
                        ),
                        _field(
                          _password,
                          'Login password (9–16 characters)',
                          secret: true,
                          autofillHints: [
                            _register
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          validator: (v) =>
                              AccountVaultProvider.validPassword(v ?? '')
                              ? null
                              : tr(
                                  context,
                                  'Password must be 9–16 characters.',
                                ),
                        ),
                        if (_register)
                          _field(
                            _confirm,
                            'Confirm login password',
                            secret: true,
                            validator: (v) => v == _password.text
                                ? null
                                : tr(context, 'Passwords do not match.'),
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => _authenticate(account),
                              child: LText(
                                _register ? 'Create account' : 'Sign in',
                              ),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(() {
                                      _register = !_register;
                                      _password.clear();
                                      _confirm.clear();
                                    }),
                              child: LText(
                                _register
                                    ? 'Already have an account? Sign in'
                                    : 'Create an email account',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                const SizedBox(height: 12),
                Text(account.email ?? ''),
                const SizedBox(height: 8),
                const LText(
                  'Your separate vault password stays on this device. Keep it safe: resetting your login password cannot recover the vault password.',
                ),
                if (!account.unlocked) ...[
                  Form(
                    key: _vaultForm,
                    child: Column(
                      children: [
                        _field(
                          _vaultPassword,
                          'Vault password (9–16 characters)',
                          secret: true,
                          validator: (v) =>
                              AccountVaultProvider.validPassword(v ?? '')
                              ? null
                              : tr(
                                  context,
                                  'Password must be 9–16 characters.',
                                ),
                        ),
                        if (account.creatingVault)
                          _field(
                            _vaultConfirm,
                            'Confirm vault password',
                            secret: true,
                            validator: (v) => v == _vaultPassword.text
                                ? null
                                : tr(context, 'Passwords do not match.'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (!_vaultForm.currentState!.validate()) return;
                            final pending = account.unlock(_vaultPassword.text);
                            _vaultPassword.clear();
                            _vaultConfirm.clear();
                            await pending;
                          },
                    child: const LText('Unlock / create vault'),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: busy ? null : () => _save(sync),
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const LText('Save to cloud'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy || !account.hasRemoteVault
                            ? null
                            : () => _restore(sync),
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const LText('Restore to this device'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const LText(
                    'Backs up connection settings and login passwords. Private key files, sudo/proxy passwords and AI keys stay on this device.',
                  ),
                ],
                TextButton(
                  onPressed: _restoring
                      ? null
                      : () => sync.selectMode(DataMode.local),
                  child: const LText('Sign out and use locally'),
                ),
              ],
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (account.message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LText(
                    account.message!,
                    style: TextStyle(
                      color: account.hasError
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
