import 'package:flutter/material.dart';

// Free, no-API-key avatar generator (DiceBear) seeded by user id, so every
// rep gets a stable, unique, randomly-generated face — lets reps recognize
// each other on the map without a photo upload feature.
// Swap this for real profile photo uploads later if reps want that instead.
String avatarUrlFor(String seed, {int size = 96}) =>
    'https://api.dicebear.com/9.x/avataaars/png?seed=${Uri.encodeComponent(seed)}&size=$size';

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.userId, this.radius = 16, this.ringColor});

  final String userId;
  final double radius;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    // `child` is always painted (on top of backgroundColor, then over
    // backgroundImage once it loads) — without it, a slow or failed image
    // fetch just shows a flat grey circle, easy to mistake for nothing
    // rendering at all. This icon is the always-visible fallback.
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey.shade300,
      foregroundImage: NetworkImage(avatarUrlFor(userId, size: (radius * 2).round())),
      onForegroundImageError: (error, stackTrace) {
        debugPrint('UserAvatar: failed to load avatar for $userId: $error');
      },
      child: Icon(Icons.person, size: radius, color: Colors.grey.shade600),
    );
    if (ringColor == null) return avatar;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, color: ringColor),
      child: avatar,
    );
  }
}
