import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:termini/checkmytime/pages/user_page.dart';

class ParticipatePage extends StatelessWidget {
  final String eventId;
  final String eventTitle;
  final String createdBy;
  final String createdByName;
  final List<String> acceptedIds;
  final List<String> maybeIds;
  final List<String> invitedPendingIds;
  final List<String> requestPendingIds;
  final List<String> declinedIds;
  final Set<String> invitedUserIds;
  final String currentUserId;
  final String joinMode;
  final Map<String, dynamic> inviteSeenAtMap;
  final bool isOwner;

  const ParticipatePage({
    super.key,
    required this.eventId,
    required this.eventTitle,
    required this.createdBy,
    required this.createdByName,
    required this.acceptedIds,
    required this.maybeIds,
    required this.invitedPendingIds,
    required this.requestPendingIds,
    required this.declinedIds,
    required this.invitedUserIds,
    required this.currentUserId,
    required this.joinMode,
    required this.inviteSeenAtMap,
    required this.isOwner,
  });

  Future<Map<String, _ParticipantUserData>> _loadUserData() async {
    final idsToLoad = <String>{
      createdBy,
      ...acceptedIds,
      ...maybeIds,
      ...invitedPendingIds,
      ...requestPendingIds,
      ...declinedIds,
    }..removeWhere((id) => id.trim().isEmpty);

    final result = <String, _ParticipantUserData>{};
    for (final id in idsToLoad) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(id).get();
        final data = doc.data() ?? <String, dynamic>{};
        final name = (data['displayName'] ?? data['name'] ?? '').toString().trim();
        final imageUrl = (data['profileImageUrl'] ?? '').toString().trim();
        result[id] = _ParticipantUserData(
          name: name.isEmpty ? 'Unbekannt' : name,
          imageUrl: imageUrl,
        );
      } catch (_) {
        result[id] = const _ParticipantUserData(name: 'Unbekannt', imageUrl: '');
      }
    }
    return result;
  }

  Future<void> _openProfile(BuildContext context, _ParticipantItemData person) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => UserPage(
          userId: person.userId,
          initialName: person.name,
          initialImageUrl: person.imageUrl,
        ),
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  String _inviteStageForPendingUser(String userId) {
    if (inviteSeenAtMap[userId] != null) return 'seen';
    return 'invited';
  }

  String _participantCountText() {
    final count = acceptedIds.length;
    return count == 1 ? '1 Teilnehmer' : '$count Teilnehmer';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final acceptedLabel = isOwner && joinMode == 'invite_only' ? 'Angenommen' : 'Bestätigt';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Teilnehmer'),
      ),
      body: FutureBuilder<Map<String, _ParticipantUserData>>(
        future: _loadUserData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final loadedUsers = snapshot.data ?? <String, _ParticipantUserData>{};
          final resolvedCreatorName = createdByName.isNotEmpty
              ? createdByName
              : (loadedUsers[createdBy]?.name ?? 'Unbekannt');

          final creator = [
            _ParticipantItemData(
              userId: createdBy,
              name: resolvedCreatorName,
              imageUrl: loadedUsers[createdBy]?.imageUrl ?? '',
              status: 'Ersteller',
              inviteStage: 'creator',
              isCurrentUser: createdBy == currentUserId,
            ),
          ];
          final accepted = acceptedIds.map((id) => _ParticipantItemData(
            userId: id,
            name: loadedUsers[id]?.name ?? 'Unbekannt',
            imageUrl: loadedUsers[id]?.imageUrl ?? '',
            status: acceptedLabel,
            inviteStage: invitedUserIds.contains(id) ? 'accepted' : 'pending',
            isCurrentUser: id == currentUserId,
          )).toList();
          final maybe = maybeIds.map((id) => _ParticipantItemData(
            userId: id,
            name: loadedUsers[id]?.name ?? 'Unbekannt',
            imageUrl: loadedUsers[id]?.imageUrl ?? '',
            status: 'Vielleicht',
            inviteStage: invitedUserIds.contains(id) ? 'maybe' : 'pending',
            isCurrentUser: id == currentUserId,
          )).toList();
          final invited = invitedPendingIds.map((id) => _ParticipantItemData(
            userId: id,
            name: loadedUsers[id]?.name ?? 'Unbekannt',
            imageUrl: loadedUsers[id]?.imageUrl ?? '',
            status: inviteSeenAtMap[id] != null ? 'Gesehen' : 'Eingeladen',
            inviteStage: _inviteStageForPendingUser(id),
            isCurrentUser: id == currentUserId,
          )).toList();
          final requests = requestPendingIds.map((id) => _ParticipantItemData(
            userId: id,
            name: loadedUsers[id]?.name ?? 'Unbekannt',
            imageUrl: loadedUsers[id]?.imageUrl ?? '',
            status: 'Ausstehend',
            inviteStage: 'pending',
            isCurrentUser: id == currentUserId,
          )).toList();
          final declined = declinedIds.map((id) => _ParticipantItemData(
            userId: id,
            name: loadedUsers[id]?.name ?? 'Unbekannt',
            imageUrl: loadedUsers[id]?.imageUrl ?? '',
            status: 'Abgelehnt',
            inviteStage: invitedUserIds.contains(id) ? 'declined' : 'pending',
            isCurrentUser: id == currentUserId,
          )).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                '${_participantCountText()}${eventTitle.trim().isEmpty ? '' : ' • $eventTitle'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _ParticipantSection(
                title: 'Erstellt von',
                people: creator,
                onUserTap: (person) => _openProfile(context, person),
              ),
              const SizedBox(height: 16),
              _ParticipantSection(
                title: _participantCountText(),
                people: accepted,
                emptyLabel: acceptedLabel == 'Angenommen'
                    ? 'Noch keine angenommenen Einladungen.'
                    : 'Noch keine Bestätigungen.',
                onUserTap: (person) => _openProfile(context, person),
              ),
              if (maybe.isNotEmpty) ...[
                const SizedBox(height: 16),
                _ParticipantSection(
                  title: 'Vielleicht',
                  people: maybe,
                  onUserTap: (person) => _openProfile(context, person),
                ),
              ],
              if (invited.isNotEmpty) ...[
                const SizedBox(height: 16),
                _ParticipantSection(
                  title: 'Eingeladen',
                  people: invited,
                  onUserTap: (person) => _openProfile(context, person),
                ),
              ],
              if (requests.isNotEmpty) ...[
                const SizedBox(height: 16),
                _ParticipantSection(
                  title: 'Ausstehend',
                  people: requests,
                  onUserTap: (person) => _openProfile(context, person),
                ),
              ],
              if (declined.isNotEmpty) ...[
                const SizedBox(height: 16),
                _ParticipantSection(
                  title: 'Abgelehnt',
                  people: declined,
                  onUserTap: (person) => _openProfile(context, person),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ParticipantUserData {
  final String name;
  final String imageUrl;

  const _ParticipantUserData({
    required this.name,
    required this.imageUrl,
  });
}

class _ParticipantItemData {
  final String userId;
  final String name;
  final String imageUrl;
  final String status;
  final String inviteStage;
  final bool isCurrentUser;

  const _ParticipantItemData({
    required this.userId,
    required this.name,
    required this.imageUrl,
    required this.status,
    required this.inviteStage,
    required this.isCurrentUser,
  });
}

class _ParticipantSection extends StatelessWidget {
  final String title;
  final List<_ParticipantItemData> people;
  final String? emptyLabel;
  final ValueChanged<_ParticipantItemData>? onUserTap;

  const _ParticipantSection({
    required this.title,
    required this.people,
    this.emptyLabel,
    this.onUserTap,
  });

  Color _badgeColor(BuildContext context, String status) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'Ersteller':
      case 'Ausstehend':
      case 'Eingeladen':
      case 'Gesehen':
        return colorScheme.primary;
      case 'Bestätigt':
      case 'Angenommen':
        return Colors.green;
      case 'Vielleicht':
        return Colors.orange;
      case 'Abgelehnt':
        return colorScheme.error;
      default:
        return colorScheme.primary;
    }
  }

  bool _showInviteTimeline(_ParticipantItemData person) {
    return person.inviteStage != 'creator' && person.inviteStage != 'pending';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (people.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Text(
              emptyLabel ?? 'Keine Einträge vorhanden.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...people.map((person) {
            final initials = person.name.trim().isEmpty
                ? '?'
                : person.name.trim().split(RegExp(r'\s+')).take(2).map((part) => part[0]).join().toUpperCase();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onUserTap == null ? null : () => onUserTap!(person),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: colorScheme.primary.withValues(alpha: 0.10),
                              backgroundImage: person.imageUrl.isNotEmpty ? NetworkImage(person.imageUrl) : null,
                              child: person.imageUrl.isEmpty
                                  ? Text(
                                initials,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    person.isCurrentUser ? '${person.name} (Du)' : person.name,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    person.status,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            _PillBadge(
                              label: person.status,
                              color: _badgeColor(context, person.status),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                        if (_showInviteTimeline(person)) ...[
                          const SizedBox(height: 12),
                          _InviteProgressTimeline(stage: person.inviteStage),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _PillBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _PillBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InviteProgressTimeline extends StatelessWidget {
  final String stage;

  const _InviteProgressTimeline({required this.stage});

  int _stageIndex(String value) {
    switch (value) {
      case 'accepted':
      case 'maybe':
      case 'declined':
        return 2;
      case 'seen':
        return 1;
      default:
        return 0;
    }
  }

  String _finalStageLabel(String value) {
    switch (value) {
      case 'accepted':
        return 'Angenommen';
      case 'maybe':
        return 'Vielleicht';
      case 'declined':
        return 'Abgelehnt';
      default:
        return 'Antwort';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final activeIndex = _stageIndex(stage);
    final labels = ['Eingeladen', 'Gesehen', _finalStageLabel(stage)];

    Widget buildStep({required int index, required String label}) {
      final isActive = index <= activeIndex;
      final isDone = index < activeIndex;
      final isCurrent = index == activeIndex;
      final fillColor = isActive ? colorScheme.primary : colorScheme.outlineVariant;
      final textColor = isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant;

      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: fillColor.withValues(alpha: isCurrent || isDone ? 0.12 : 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(color: fillColor, width: isCurrent ? 2 : 1.4),
                  ),
                  child: isDone
                      ? Icon(Icons.check_rounded, size: 12, color: fillColor)
                      : isCurrent
                      ? Icon(Icons.radio_button_checked, size: 11, color: fillColor)
                      : null,
                ),
                if (index < labels.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: index < activeIndex
                            ? colorScheme.primary.withValues(alpha: 0.5)
                            : colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: textColor,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [for (var i = 0; i < labels.length; i++) buildStep(index: i, label: labels[i])],
    );
  }
}
