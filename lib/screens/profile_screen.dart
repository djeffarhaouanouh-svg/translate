import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/app_strings.dart';
import '../services/auth_service.dart';
import '../services/device_id.dart';
import '../services/friendship_api.dart';
import '../services/languages.dart';
import '../services/profile_api.dart';
import '../services/supabase_service.dart';
import '../services/user_prefs.dart';
import '../theme/whatsapp_call_theme.dart';
import '../widgets/profile_avatar.dart';
import 'friends_list_screen.dart';
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

  Future<void> _openFriendsList(FriendDirection direction) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FriendsListScreen(direction: direction),
      ),
    );
    // Counts may have changed (follow-back).
    await _reload();
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_deviceId.isEmpty) return;
    if (!isSupabaseReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supabase non configuré.')),
      );
      return;
    }
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final ext = file.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    try {
      await ProfileApi.uploadAvatar(
        deviceId: _deviceId,
        bytes: bytes,
        contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
      );
      if (!mounted) return;
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload échoué : $e'),
          duration: const Duration(seconds: 8),
        ),
      );
    }
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

  /// Email comes from Supabase Auth (`auth.users.email`), never from the
  /// public `profiles` table — that's how we keep it private from other users.
  String get _email => AuthService.currentEmail;

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WhatsAppCallTheme.bar,
        title: Text(
          AppStrings.t('profile_signout_confirm_title'),
          style: const TextStyle(color: WhatsAppCallTheme.strongText),
        ),
        content: Text(
          AppStrings.t('profile_signout_confirm_body'),
          style: const TextStyle(color: WhatsAppCallTheme.subtleText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppStrings.t('profile_signout')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuthService.signOut();
      // Parent (`LiveKitTranslateApp`) listens for auth state changes and
      // routes us back to the login screen automatically.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = findLanguageByCode(_languageCode);
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
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
                    avatarColorHex: _remote?.avatarColor,
                    avatarUrl: _remote?.avatarUrl,
                    onTapAvatar: _pickAndUploadAvatar,
                  ),
                  if (_email.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _EmailCard(email: _email),
                  ],
                  const SizedBox(height: 24),
                  _StatsRow(
                    counts: _counts,
                    onTapFollowers: () => _openFriendsList(FriendDirection.followers),
                    onTapFollowing: () => _openFriendsList(FriendDirection.following),
                  ),
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
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout, color: Color(0xFFE53935)),
                    label: Text(
                      AppStrings.t('profile_signout'),
                      style: const TextStyle(color: Color(0xFFE53935)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF2A3942)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.handle,
    required this.avatarColorHex,
    required this.avatarUrl,
    required this.onTapAvatar,
  });

  final String displayName;
  final String handle;
  final String? avatarColorHex;
  final String? avatarUrl;
  final VoidCallback onTapAvatar;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            ProfileAvatar(
              displayName: displayName,
              avatarUrl: avatarUrl,
              avatarColorHex: avatarColorHex,
              size: 84,
              fontSize: 36,
              onTap: onTapAvatar,
            ),
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: WhatsAppCallTheme.accent,
                shape: BoxShape.circle,
                border: Border.all(color: WhatsAppCallTheme.scaffold, width: 2),
              ),
              child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
            ),
          ],
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
  const _StatsRow({
    required this.counts,
    required this.onTapFollowers,
    required this.onTapFollowing,
  });
  final FriendshipCounts counts;
  final VoidCallback onTapFollowers;
  final VoidCallback onTapFollowing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WhatsAppCallTheme.bar,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A3942)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: _StatCell(
              value: counts.followers,
              label: AppStrings.t('profile_followers'),
              onTap: onTapFollowers,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: const Color(0xFF2A3942),
          ),
          Expanded(
            child: _StatCell(
              value: counts.following,
              label: AppStrings.t('profile_following'),
              onTap: onTapFollowing,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.value,
    required this.label,
    required this.onTap,
  });
  final int value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
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
        ),
      ),
    );
  }
}

class _EmailCard extends StatelessWidget {
  const _EmailCard({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WhatsAppCallTheme.bar,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A3942)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          const Icon(Icons.alternate_email,
              color: WhatsAppCallTheme.accent, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WhatsAppCallTheme.strongText,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.lock_outline,
                        color: WhatsAppCallTheme.subtleText, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      AppStrings.t('profile_email_private'),
                      style: const TextStyle(
                        color: WhatsAppCallTheme.subtleText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
