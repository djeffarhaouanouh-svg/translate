import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/app_strings.dart';
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
                  const SizedBox(height: 20),
                  _StatsRow(
                    counts: _counts,
                    onTapFollowers: () => _openFriendsList(FriendDirection.followers),
                    onTapFollowing: () => _openFriendsList(FriendDirection.following),
                  ),
                  const SizedBox(height: 20),
                  _BioCard(
                    bio: _remote?.bio ?? '',
                    onSave: _saveBio,
                  ),
                  const SizedBox(height: 16),
                  _DiscoverPhotoCard(
                    photoUrl: _remote?.discoverPhotoUrl ?? '',
                    onPick: _pickAndUploadDiscoverPhoto,
                  ),
                  const SizedBox(height: 20),
                  _CreditsCard(
                    profile: _remote,
                    onUpgrade: _remote != null && !_remote!.isPro
                        ? _upgradeToPremium
                        : null,
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
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings_outlined,
                        color: WhatsAppCallTheme.subtleText),
                    label: const Text(
                      'Paramètres',
                      style: TextStyle(color: WhatsAppCallTheme.subtleText),
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
  const _LanguageCard({required this.language});
  final AppLanguage? language;

  @override
  Widget build(BuildContext context) {
    final flag = language?.flag ?? '🌐';
    final label = language != null
        ? AppStrings.t('profile_speaks', args: {'lang': language!.label})
        : AppStrings.t('profile_no_language');
    final warning = language != null
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

/// Single Discover-card photo. Tap → opens the gallery picker, uploads via
/// [ProfileApi.uploadDiscoverPhoto] (Supabase storage `avatars/discover/`).
/// Empty state shows a dashed placeholder with an Add Photo affordance.
class _DiscoverPhotoCard extends StatelessWidget {
  const _DiscoverPhotoCard({required this.photoUrl, required this.onPick});

  final String photoUrl;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final has = photoUrl.isNotEmpty;
    // Centred portrait preview — ~160 wide × 200 tall (4:5, the Discover
    // card aspect). Compact but recognisable as "what your card looks like".
    return Center(
      child: SizedBox(
        width: 160,
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPick,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: WhatsAppCallTheme.bar,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: has
                      ? const Color(0xFF2A3942)
                      : WhatsAppCallTheme.accent.withValues(alpha: 0.5),
                  width: has ? 1 : 1.5,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (has)
                    Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _PhotoEmptyState(),
                    )
                  else
                    const _PhotoEmptyState(),
                  if (has)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit,
                            size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoEmptyState extends StatelessWidget {
  const _PhotoEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_a_photo_outlined,
              color: WhatsAppCallTheme.accent, size: 28),
          SizedBox(height: 8),
          Text(
            'Ajouter',
            style: TextStyle(
              color: WhatsAppCallTheme.strongText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Editable short tagline shown on the user's profile (and later on their
/// Discover card). Tap → bottom sheet with a TextField (max
/// [profileBioMaxLength] chars). Empty → placeholder hint.
class _BioCard extends StatelessWidget {
  const _BioCard({required this.bio, required this.onSave});

  final String bio;
  final Future<void> Function(String) onSave;

  static const _placeholder = 'Présente-toi en 2 mots ✏️';

  Future<void> _open(BuildContext context) async {
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
          20,
          16,
          20,
          16 + MediaQuery.of(ctx).viewInsets.bottom,
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
                hintText: _placeholder,
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
      await onSave(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final empty = bio.trim().isEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(context),
      child: Container(
        decoration: BoxDecoration(
          color: WhatsAppCallTheme.bar,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2A3942)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                empty ? _placeholder : bio,
                style: TextStyle(
                  color: empty
                      ? WhatsAppCallTheme.subtleText
                      : WhatsAppCallTheme.strongText,
                  fontSize: 14,
                  height: 1.4,
                  fontStyle: empty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.edit_outlined,
                color: WhatsAppCallTheme.subtleText, size: 18),
          ],
        ),
      ),
    );
  }
}
