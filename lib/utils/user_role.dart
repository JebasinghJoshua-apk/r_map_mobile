enum UserRole {
  admin,
  promoter,
  user,
  layoutDigitizer,
  unknown,
}

/// Parses a role value coming from the backend/mobile-bff.
///
/// The API/MobileBFF may represent roles as:
/// - enum names: "Admin", "Promoter", "User"
/// - enum numbers (as string): "1", "2", "3"
///
/// Keep the numeric mapping aligned with `R.MAP.Domain.Enums.UserRole`.
UserRole parseUserRole(String? raw) {
  final normalized = (raw ?? '').trim();
  if (normalized.isEmpty) return UserRole.unknown;

  switch (normalized.toLowerCase()) {
    case 'admin':
      return UserRole.admin;
    case 'promoter':
      return UserRole.promoter;
    case 'user':
      return UserRole.user;
    case 'layoutdigitizer':
      return UserRole.layoutDigitizer;
  }

  // Numeric enum values (string) from upstream.
  switch (normalized) {
    case '1':
      return UserRole.admin;
    case '2':
      return UserRole.promoter;
    case '3':
      return UserRole.user;
    case '4':
      return UserRole.layoutDigitizer;
  }

  return UserRole.unknown;
}

String userRoleName(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return 'Admin';
    case UserRole.promoter:
      return 'Promoter';
    case UserRole.user:
      return 'User';
    case UserRole.layoutDigitizer:
      return 'Layout Digitizer';
    case UserRole.unknown:
      return 'Unknown';
  }
}
