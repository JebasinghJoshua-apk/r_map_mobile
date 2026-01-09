import 'package:flutter/material.dart';

enum ProfileMenuAction {
  myProperties,
  logout,
}

class ProfileMenuButton extends StatelessWidget {
  const ProfileMenuButton({
    super.key,
    required this.displayName,
    required this.phoneNumber,
    this.onMyProperties,
    this.onLogout,
  });

  final String displayName;
  final String phoneNumber;
  final VoidCallback? onMyProperties;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ProfileMenuAction>(
      tooltip: 'Profile',
      position: PopupMenuPosition.under,
      onSelected: (value) {
        switch (value) {
          case ProfileMenuAction.myProperties:
            onMyProperties?.call();
            break;
          case ProfileMenuAction.logout:
            onLogout?.call();
            break;
        }
      },
      icon: const Icon(Icons.person_outline),
      itemBuilder: (context) {
        return <PopupMenuEntry<ProfileMenuAction>>[
          PopupMenuItem<ProfileMenuAction>(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hi, $displayName',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  phoneNumber,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<ProfileMenuAction>(
            value: ProfileMenuAction.myProperties,
            child: Row(
              children: [
                Icon(Icons.business_outlined, size: 18),
                SizedBox(width: 10),
                Text('My Properties'),
              ],
            ),
          ),
          const PopupMenuItem<ProfileMenuAction>(
            value: ProfileMenuAction.logout,
            child: Row(
              children: [
                Icon(Icons.logout, size: 18),
                SizedBox(width: 10),
                Text('Logout'),
              ],
            ),
          ),
        ];
      },
    );
  }
}
