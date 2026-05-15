import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/app_strings.dart';
import '../services/block_api.dart';
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
import 'settings_screen.dart';

/// Profile view. Two modes:
///
///   * `userId` is null (default): "my own" profile — editable, shows the
///     Free Account / Premium card, Edit + Paramètres buttons.
///   * `userId` is set: another user's profile, viewed read-only. Camera /
///     edit affordances are hidden, premium card and the call-language
///     warning are dropped (private to me), and the action row becomes
///     Bloquer / Débloquer instead of Edit / Paramètres.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.userId});

  /// When non-null, render the profile of the given Supabase auth user id
  /// in read-only "viewer" mode rather than my own profile.
  final String? userId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  String _deviceId = '';
  RemoteProfile? _remote;
  ProfileSnapshot? _local;
  FriendshipCounts _counts = const FriendshipCounts(followers: 0, following: 0);
  bool _loading = true;
  // Viewer-mode only: am I currently blocking the displayed user?
  bool _peerBlocked = false;

  bool get _isViewingOther => widget.userId != null;
  String get _targetId => widget.userId ?? _deviceId;

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
    final targetId = widget.userId ?? deviceId;
    // Local prefs only matter for my own profile (offline fallback). When
    // viewing someone else there's no local cache to consult.
    final local = _isViewingOther ? null : await UserPrefs.loadProfile();
    final remote =
        isSupabaseReady ? await ProfileApi.fetchById(targetId) : null;
    final counts = isSupabaseReady
        ? await FriendshipApi.countsFor(targetId)
        : const FriendshipCounts(followers: 0, following: 0);
    final blocked = _isViewingOther && isSupabaseReady && deviceId.isNotEmpty
        ? await BlockApi.isBlocked(blockerId: deviceId, otherId: targetId)
        : false;
    if (!mounted) return;
    setState(() {
      _deviceId = deviceId;
      _local = local;
      _remote = remote;
      _counts = counts;
      _peerBlocked = blocked;
      _loading = false;
    });
  }

  Future<void> _toggleBlock() async {
    if (_targetId.isEmpty || _deviceId.isEmpty) return;
    final wasBlocked = _peerBlocked;
    final name = _displayName.isEmpty ? 'cette personne' : _displayName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WhatsAppCallTheme.bar,
        title: Text(
          wasBlocked ? 'Débloquer $name ?' : 'Bloquer $name ?',
          style: const TextStyle(color: WhatsAppCallTheme.strongText),
        ),
        content: Text(
          wasBlocked
              ? 'Cette personne pourra à nouveau te trouver, te contacter et voir tes messages.'
              : 'Cette personne ne pourra plus te trouver, te contacter ni t\'appeler. Tu peux annuler depuis Paramètres → Bloqués.',
          style: const TextStyle(color: WhatsAppCallTheme.subtleText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: wasBlocked
                  ? WhatsAppCallTheme.accent
                  : const Color(0xFFE53935),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(wasBlocked ? 'Débloquer' : 'Bloquer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (wasBlocked) {
        await BlockApi.unblock(blockerId: _deviceId, blockedId: _targetId);
      } else {
        await BlockApi.block(blockerId: _deviceId, blockedId: _targetId);
      }
      if (!mounted) return;
      setState(() => _peerBlocked = !wasBlocked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
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

  Future<void> _upgradeToPremium() async {
    // For now this just opens a confirmation sheet describing the offer.
    // The actual IAP / receipt-validation hook will go here once App Store /
    // Play Store products are wired up. No price is displayed on purpose —
    // the storefront will be the source of truth.
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: WhatsAppCallTheme.bar,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('💎', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Text(
                  AppStrings.t('premium_title'),
                  style: const TextStyle(
                    color: WhatsAppCallTheme.strongText,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.t('premium_offer_label'),
              style: const TextStyle(
                color: WhatsAppCallTheme.accent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _bullet(AppStrings.t('premium_bullet_minutes')),
            const SizedBox(height: 8),
            _bullet(AppStrings.t('premium_bullet_unlimited_calls')),
            const SizedBox(height: 8),
            _bullet(AppStrings.t('premium_bullet_priority')),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: WhatsAppCallTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(
                AppStrings.t('premium_continue'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(AppStrings.t('cancel')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || _deviceId.isEmpty) return;
    // TODO(billing): replace with real IAP receipt validation. For now we
    // flip the flag directly so the rest of the UI can be developed end-to-end.
    try {
      await ProfileApi.activatePremiumWeek(_deviceId);
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('premium_activated'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _bullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Icon(Icons.check_circle,
              color: WhatsAppCallTheme.accent, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: WhatsAppCallTheme.strongText,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAndUploadDiscoverPhoto() async {
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
      // The Discover card is portrait — keep more pixels than the avatar
      // (1024² → 1600 max edge) so the photo doesn't look soft full-screen.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 88,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final ext = file.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    try {
      await ProfileApi.uploadDiscoverPhoto(
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

  Future<void> _saveBio(String bio) async {
    if (_deviceId.isEmpty) return;
    final saved = await ProfileApi.updateMyBio(userId: _deviceId, bio: bio);
    if (saved == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sauvegarde échouée.')),
      );
      return;
    }
    if (!mounted || _remote == null) return;
    setState(() {
      _remote = RemoteProfile(
        id: _remote!.id,
        handle: _remote!.handle,
        displayName: _remote!.displayName,
        language: _remote!.language,
        avatarColor: _remote!.avatarColor,
        avatarUrl: _remote!.avatarUrl,
        discoverPhotoUrl: _remote!.discoverPhotoUrl,
        bio: saved,
        isPro: _remote!.isPro,
        creditsSeconds: _remote!.creditsSeconds,
        creditsResetAt: _remote!.creditsResetAt,
        lifetimeCallSeconds: _remote!.lifetimeCallSeconds,
        proExpiresAt: _remote!.proExpiresAt,
      );
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    // Profile data may have changed (e.g. account deleted → ignored;
    // sign-out → routed away by the auth listener).
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final lang = findLanguageByCode(_languageCode);
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      // AppBar only when pushed as a route to view someone else — gives a
      // back button. The "my profile" tab is mounted in IndexedStack, no
      // back navigation, so no AppBar needed.
      appBar: _isViewingOther
          ? AppBar(
              backgroundColor: WhatsAppCallTheme.scaffold,
              foregroundColor: WhatsAppCallTheme.strongText,
              elevation: 0,
              title: Text(
                _displayName.isEmpty ? 'Profil' : _displayName,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700),
              ),
            )
          : null,
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
                // Reserve room for the floating bottom nav (height 54 + 12 gap)
                // plus the device's bottom safe-area inset, otherwise the last
                // card gets occluded.
                // Horizontal gutter matches the chat / discover headers so
                // the avatar and bio don't run into the screen edge.
                padding: EdgeInsets.fromLTRB(
                  28, 20, 28,
                  32 + 64 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  _IdentitySection(
                    displayName: _displayName.isEmpty
                        ? AppStrings.t('profile_anonymous')
                        : _displayName,
                    handle: _handle,
                    avatarColorHex: _remote?.avatarColor,
                    avatarUrl: _remote?.avatarUrl,
                    bio: _remote?.bio ?? '',
                    counts: _counts,
                    discoverPhotoUrl: _remote?.discoverPhotoUrl ?? '',
                    viewerMode: _isViewingOther,
                    peerBlocked: _peerBlocked,
                    onTapAvatar: _pickAndUploadAvatar,
                    onEditBio: _saveBio,
                    onTapFollowers: () => _openFriendsList(FriendDirection.followers),
                    onTapFollowing: () => _openFriendsList(FriendDirection.following),
                    onPickDiscoverPhoto: _pickAndUploadDiscoverPhoto,
                    onEdit: _openEditor,
                    onSettings: _openSettings,
                    onToggleBlock: _toggleBlock,
                  ),
                  const SizedBox(height: 20),
                  _LanguageCard(
                    language: lang,
                    showCallWarning: !_isViewingOther,
                  ),
                  if (!_isViewingOther) ...[
                    const SizedBox(height: 16),
                    _CreditsCard(
                      profile: _remote,
                      onUpgrade: _remote != null && !_remote!.isPro
                          ? _upgradeToPremium
                          : null,
                    ),
                  ],
                ],
              ),
        ),
      ),
    );
  }
}

class _CreditsCard extends StatelessWidget {
  const _CreditsCard({required this.profile, required this.onUpgrade});

  final RemoteProfile? profile;

  /// Null when the user is already Pro (button is hidden).
  final VoidCallback? onUpgrade;

  String _formatMinutes(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final isPro = p?.isPro ?? false;
    final creditsSeconds = p?.creditsSeconds ?? 0;
    final lifetimeSeconds = p?.lifetimeCallSeconds ?? 0;

    return Container(
      decoration: BoxDecoration(
        gradient: isPro
            ? const LinearGradient(
                colors: [Color(0xFF1F3A34), Color(0xFF0F2A26)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isPro ? null : WhatsAppCallTheme.bar,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPro
              ? WhatsAppCallTheme.accent.withValues(alpha: 0.45)
              : const Color(0xFF2A3942),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💎', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isPro
                      ? AppStrings.t('credits_pro_title')
                      : AppStrings.t('credits_free_title'),
                  style: const TextStyle(
                    color: WhatsAppCallTheme.strongText,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isPro)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: WhatsAppCallTheme.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'PRO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatCellInline(
                  label: AppStrings.t('credits_remaining'),
                  value: _formatMinutes(creditsSeconds),
                  accent: true,
                ),
              ),
              Container(
                width: 1,
                height: 32,
                color: const Color(0xFF2A3942),
              ),
              Expanded(
                child: _StatCellInline(
                  label: AppStrings.t('credits_used_total'),
                  value: _formatMinutes(lifetimeSeconds),
                  accent: false,
                ),
              ),
            ],
          ),
          if (onUpgrade != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onUpgrade,
              icon: const Text('💎', style: TextStyle(fontSize: 14)),
              label: Text(AppStrings.t('credits_upgrade_cta')),
              style: FilledButton.styleFrom(
                backgroundColor: WhatsAppCallTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                minimumSize: const Size.fromHeight(42),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCellInline extends StatelessWidget {
  const _StatCellInline({
    required this.label,
    required this.value,
    required this.accent,
  });
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: TextStyle(
            color: accent
                ? WhatsAppCallTheme.accent
                : WhatsAppCallTheme.strongText,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: WhatsAppCallTheme.subtleText,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({required this.language, this.showCallWarning = true});
  final AppLanguage? language;
  /// The "during calls you have to speak only X" hint only makes sense on
  /// my own profile — not when peeking at someone else's.
  final bool showCallWarning;

  @override
  Widget build(BuildContext context) {
    final flag = language?.flag ?? '🌐';
    final label = language != null
        ? AppStrings.t('profile_speaks', args: {'lang': language!.label})
        : AppStrings.t('profile_no_language');
    final warning = (showCallWarning && language != null)
        ? AppStrings.t('profile_call_language_warning',
            args: {'lang': language!.label})
        : null;
    return Container(
      decoration: BoxDecoration(
        color: WhatsAppCallTheme.bar,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A3942)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          if (warning != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.info_outline,
                      size: 14, color: WhatsAppCallTheme.subtleText),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warning,
                    style: const TextStyle(
                      color: WhatsAppCallTheme.subtleText,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Insta-style identity section: avatar with camera badge on the left,
/// followers/following counts inline on the right; below, the display name,
/// handle, bio (tap-to-edit) and a compact Discover photo preview, then a
/// row with Edit and Settings buttons. Replaces the previous bunch of
/// separate stacked cards (header / stats / bio / discover photo / buttons).
class _IdentitySection extends StatelessWidget {
  const _IdentitySection({
    required this.displayName,
    required this.handle,
    required this.avatarColorHex,
    required this.avatarUrl,
    required this.bio,
    required this.counts,
    required this.discoverPhotoUrl,
    required this.onTapAvatar,
    required this.onEditBio,
    required this.onTapFollowers,
    required this.onTapFollowing,
    required this.onPickDiscoverPhoto,
    required this.onEdit,
    required this.onSettings,
    this.viewerMode = false,
    this.peerBlocked = false,
    this.onToggleBlock,
  });

  final String displayName;
  final String handle;
  final String? avatarColorHex;
  final String? avatarUrl;
  final String bio;
  final FriendshipCounts counts;
  final String discoverPhotoUrl;
  final VoidCallback onTapAvatar;
  final Future<void> Function(String) onEditBio;
  final VoidCallback onTapFollowers;
  final VoidCallback onTapFollowing;
  final VoidCallback onPickDiscoverPhoto;
  final VoidCallback onEdit;
  final VoidCallback onSettings;
  /// True when this section is rendering someone else's profile read-only.
  /// Hides the camera badge, the bio edit affordance, the discover-photo
  /// upload affordance, and swaps Edit/Paramètres for Bloquer.
  final bool viewerMode;
  final bool peerBlocked;
  final VoidCallback? onToggleBlock;

  static const _bioPlaceholder = 'Présente-toi en 2 mots ✏️';

  Future<void> _openBioEditor(BuildContext context) async {
    final ctrl = TextEditingController(text: bio);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WhatsAppCallTheme.bar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 16, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ta présentation',
              style: TextStyle(
                color: WhatsAppCallTheme.strongText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: profileBioMaxLength,
              maxLines: 3,
              minLines: 2,
              cursorColor: WhatsAppCallTheme.accent,
              style: const TextStyle(color: WhatsAppCallTheme.strongText),
              decoration: const InputDecoration(
                hintText: _bioPlaceholder,
                hintStyle: TextStyle(color: WhatsAppCallTheme.subtleText),
                filled: true,
                fillColor: WhatsAppCallTheme.scaffold,
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              style: FilledButton.styleFrom(
                backgroundColor: WhatsAppCallTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (result != null && result != bio) {
      await onEditBio(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final emptyBio = bio.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Insta-style header: avatar + stats inline.
        Row(
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
                  onTap: viewerMode ? null : onTapAvatar,
                ),
                if (!viewerMode)
                  Container(
                    width: 26, height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: WhatsAppCallTheme.accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: WhatsAppCallTheme.scaffold, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt,
                        size: 14, color: Colors.white),
                  ),
              ],
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _InlineStat(
                    value: counts.followers,
                    label: AppStrings.t('profile_followers'),
                    onTap: onTapFollowers,
                  ),
                  _InlineStat(
                    value: counts.following,
                    label: AppStrings.t('profile_following'),
                    onTap: onTapFollowing,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Display name + handle.
        Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: WhatsAppCallTheme.strongText,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          handle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: WhatsAppCallTheme.subtleText, fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        // Bio: tap-to-edit on my own profile; flat read-only text when
        // viewing someone else. Skip rendering an empty bio in viewer mode
        // (showing "Présente-toi" makes no sense for a third person).
        if (!viewerMode)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openBioEditor(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                emptyBio ? _bioPlaceholder : bio,
                style: TextStyle(
                  color: emptyBio
                      ? WhatsAppCallTheme.subtleText
                      : WhatsAppCallTheme.strongText,
                  fontSize: 14,
                  height: 1.4,
                  fontStyle: emptyBio ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          )
        else if (!emptyBio)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              bio,
              style: const TextStyle(
                color: WhatsAppCallTheme.strongText,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        const SizedBox(height: 14),
        // Action buttons row — Edit + Settings on my profile, Bloquer /
        // Débloquer on someone else's.
        Row(
          children: [
            if (!viewerMode) ...[
              Expanded(
                child: _PillButton(
                  icon: Icons.edit_outlined,
                  label: AppStrings.t('profile_edit'),
                  onTap: onEdit,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PillButton(
                  icon: Icons.settings_outlined,
                  label: 'Paramètres',
                  onTap: onSettings,
                ),
              ),
            ] else
              Expanded(
                child: _PillButton(
                  icon: peerBlocked ? Icons.lock_open : Icons.block,
                  label: peerBlocked ? 'Débloquer' : 'Bloquer',
                  onTap: onToggleBlock ?? () {},
                  destructive: !peerBlocked,
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        // Instagram-style 3-column grid. Slot 0 is the Discover photo
        // (the only real one for now). Slots 1-2 tease where future
        // photos will live — tappable on my own profile (opens the
        // gallery picker), inert when viewing someone else.
        _PhotosGrid(
          discoverPhotoUrl: discoverPhotoUrl,
          viewerMode: viewerMode,
          onPick: onPickDiscoverPhoto,
        ),
      ],
    );
  }
}

class _PhotosGrid extends StatelessWidget {
  const _PhotosGrid({
    required this.discoverPhotoUrl,
    required this.viewerMode,
    required this.onPick,
  });

  final String discoverPhotoUrl;
  final bool viewerMode;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = discoverPhotoUrl.isNotEmpty;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      // Square cells like Instagram's posts grid. Discover photo is
      // portrait but BoxFit.cover handles the crop.
      children: [
        _PhotoCell(
          photoUrl: hasPhoto ? discoverPhotoUrl : null,
          viewerMode: viewerMode,
          onTap: onPick,
        ),
        _PhotoCell(
          photoUrl: null,
          viewerMode: viewerMode,
          onTap: onPick,
        ),
        _PhotoCell(
          photoUrl: null,
          viewerMode: viewerMode,
          onTap: onPick,
        ),
      ],
    );
  }
}

class _PhotoCell extends StatelessWidget {
  const _PhotoCell({
    required this.photoUrl,
    required this.viewerMode,
    required this.onTap,
  });

  final String? photoUrl;
  final bool viewerMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    final tappable = !viewerMode;
    return Material(
      color: WhatsAppCallTheme.bar,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tappable ? onTap : null,
        child: hasPhoto
            ? Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: WhatsAppCallTheme.subtleText),
                ),
              )
            : Center(
                child: Icon(
                  tappable
                      ? Icons.add_a_photo_outlined
                      : Icons.image_not_supported_outlined,
                  color: tappable
                      ? WhatsAppCallTheme.accent
                      : WhatsAppCallTheme.subtleText,
                  size: 22,
                ),
              ),
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({
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
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: const TextStyle(
                color: WhatsAppCallTheme.strongText,
                fontSize: 20,
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

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  /// When true, renders the label/icon in red — used for the "Bloquer"
  /// state of the viewer-mode action button.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final fg = destructive
        ? const Color(0xFFE53935)
        : WhatsAppCallTheme.strongText;
    return Material(
      color: WhatsAppCallTheme.bar,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
                color: destructive
                    ? fg.withValues(alpha: 0.35)
                    : const Color(0xFF2A3942)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
