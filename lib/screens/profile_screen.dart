import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/device_id.dart';
import '../services/friendship_api.dart';
import '../services/languages.dart';
import '../services/profile_api.dart';
import '../services/supabase_service.dart';
import '../services/user_prefs.dart';
import '../theme/whatsapp_call_theme.dart';
import 'onboarding_screen.dart';

/// Onglet 3 — synchronized with the user's own Supabase `profiles` row plus
/// live follower / following counts pulled from `friendships`. Falls back to
/// the locally-stored profile (UserPrefs) when Supabase is offline.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  String _deviceId = '';
  RemoteProfile? _remote;
  ProfileSnapshot? _local;
  FriendshipCounts _counts = const FriendshipCounts(followers: 0, following: 0);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reload();
    }
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final deviceId = await DeviceId.getOrCreate();
    final local = await UserPrefs.loadProfile();
    final remote = isSupabaseReady ? await ProfileApi.fetchById(deviceId) : null;
    final counts = isSupabaseReady
        ? await FriendshipApi.countsFor(deviceId)
        : const FriendshipCounts(followers: 0, following: 0);
    if (!mounted) return;
    setState(() {
      _deviceId = deviceId;
      _local = local;
      _remote = remote;
      _counts = counts;
      _loading = false;
    });
  }

  Future<void> _openEditor() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => OnboardingScreen(
          editing: true,
          onCompleted: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
    await _reload();
  }

  Future<void> _manualSync() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final deviceId = await DeviceId.getOrCreate();
    final local = await UserPrefs.loadProfile();
    if (local != null && local.firstName.isNotEmpty) {
      await ProfileApi.upsertMyProfile(
        deviceId: deviceId,
        displayName: local.firstName,
        language: local.sourceLang,
      );
    }
    await _reload();
  }

  String get _displayName {
    final remote = _remote?.displayName.trim() ?? '';
    if (remote.isNotEmpty) return remote;
    return _local?.firstName.trim() ?? '';
  }

  String get _languageCode {
    final remote = _remote?.language.trim() ?? '';
    if (remote.isNotEmpty) return remote;
    return _local?.sourceLang.trim() ?? '';
  }

  String get _handle {
    final h = _remote?.handle.trim() ?? '';
    if (h.isNotEmpty) return '@$h';
    return '@${_deviceId.replaceAll('-', '').substring(0, 8)}';
  }

  Color get _avatarColor {
    final hex = _remote?.avatarColor ?? '';
    final parsed = _parseHexColor(hex);
    if (parsed != null) return parsed;
    return _fallbackAvatarColor(_displayName.isEmpty ? _deviceId : _displayName);
  }

  static Color? _parseHexColor(String hex) {
    var v = hex.trim();
    if (v.isEmpty) return null;
    if (v.startsWith('#')) v = v.substring(1);
    if (v.length == 6) v = 'FF$v';
    if (v.length != 8) return null;
    final n = int.tryParse(v, radix: 16);
    return n == null ? null : Color(n);
  }

  static Color _fallbackAvatarColor(String seed) {
    const palette = <int>[
      0xFF00A884, 0xFF128C7E, 0xFF34B7F1, 0xFF1F6FEB, 0xFF7B61FF,
      0xFFA855F7, 0xFFEC4899, 0xFFF97316, 0xFFEAB308, 0xFF22C55E,
    ];
    if (seed.isEmpty) return Color(palette[0]);
    var hash = 0;
    for (final c in seed.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    return Color(palette[hash % palette.length]);
  }

  @override
  Widget build(BuildContext context) {
    final lang = findLanguageByCode(_languageCode);
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      appBar: AppBar(
        title: Text(AppStrings.t('profile_title')),
        actions: [
          IconButton(
            onPressed: _openEditor,
            tooltip: AppStrings.t('profile_edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: WhatsAppCallTheme.accent,
        backgroundColor: WhatsAppCallTheme.bar,
        onRefresh: _reload,
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(color: WhatsAppCallTheme.accent),
                        const SizedBox(height: 12),
                        Text(
                          AppStrings.t('profile_loading'),
                          style: const TextStyle(color: WhatsAppCallTheme.subtleText),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  _ProfileHeader(
                    displayName: _displayName.isEmpty
                        ? AppStrings.t('profile_anonymous')
                        : _displayName,
                    handle: _handle,
                    avatarColor: _avatarColor,
                  ),
                  const SizedBox(height: 24),
                  _StatsRow(counts: _counts),
                  const SizedBox(height: 24),
                  _LanguageCard(language: lang),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _openEditor,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(AppStrings.t('profile_edit')),
                    style: FilledButton.styleFrom(
                      backgroundColor: WhatsAppCallTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _DiagnosticsCard(
                    deviceId: _deviceId,
                    remoteFound: _remote != null,
                    onSync: _manualSync,
                  ),
                ],
              ),
      ),
    );
  }
}

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({
    required this.deviceId,
    required this.remoteFound,
    required this.onSync,
  });

  final String deviceId;
  final bool remoteFound;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final supabaseReady = isSupabaseReady;
    final sync = ProfileApi.lastSync;

    return Container(
      decoration: BoxDecoration(
        color: WhatsAppCallTheme.bar,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A3942)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Diagnostic',
            style: TextStyle(
              color: WhatsAppCallTheme.strongText,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          _DiagRow(
            label: 'Supabase',
            value: supabaseReady ? 'connecté' : 'NON connecté',
            ok: supabaseReady,
          ),
          _DiagRow(
            label: 'Profil en DB',
            value: remoteFound ? 'oui' : 'non',
            ok: remoteFound,
          ),
          _DiagRow(
            label: 'Mon ID',
            value: deviceId.isEmpty ? '—' : deviceId,
            ok: deviceId.isNotEmpty,
            wrap: true,
          ),
          if (sync != null) ...[
            const Divider(height: 18, color: Color(0xFF2A3942)),
            _DiagRow(
              label: 'Dernier sync',
              value: sync.ok ? 'OK' : 'ÉCHEC',
              ok: sync.ok,
            ),
            if (sync.error != null && sync.error!.isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText(
                sync.error!,
                style: const TextStyle(
                  color: Color(0xFFFFAB91),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onSync,
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Synchroniser maintenant'),
            style: FilledButton.styleFrom(
              backgroundColor: WhatsAppCallTheme.accentMuted,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({
    required this.label,
    required this.value,
    required this.ok,
    this.wrap = false,
  });

  final String label;
  final String value;
  final bool ok;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final valueWidget = SelectableText(
      value,
      maxLines: wrap ? null : 1,
      style: TextStyle(
        color: ok ? WhatsAppCallTheme.strongText : const Color(0xFFFFAB91),
        fontSize: 12,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: WhatsAppCallTheme.subtleText, fontSize: 12),
            ),
          ),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.handle,
    required this.avatarColor,
  });

  final String displayName;
  final String handle;
  final Color avatarColor;

  @override
  Widget build(BuildContext context) {
    final initial =
        displayName.isNotEmpty ? displayName.characters.first.toUpperCase() : '?';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: avatarColor,
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: WhatsAppCallTheme.strongText,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: WhatsAppCallTheme.subtleText,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.counts});
  final FriendshipCounts counts;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WhatsAppCallTheme.bar,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A3942)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatCell(
            value: counts.followers,
            label: AppStrings.t('profile_followers'),
          ),
          Container(
            width: 1,
            height: 32,
            color: const Color(0xFF2A3942),
          ),
          _StatCell(
            value: counts.following,
            label: AppStrings.t('profile_following'),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: const TextStyle(
            color: WhatsAppCallTheme.strongText,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: WhatsAppCallTheme.subtleText,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({required this.language});
  final AppLanguage? language;

  @override
  Widget build(BuildContext context) {
    final flag = language?.flag ?? '🌐';
    final label = language != null
        ? AppStrings.t('profile_speaks', args: {'lang': language!.label})
        : AppStrings.t('profile_no_language');
    return Container(
      decoration: BoxDecoration(
        color: WhatsAppCallTheme.bar,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A3942)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          Text(flag, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: WhatsAppCallTheme.strongText,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
