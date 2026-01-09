class AuthSession {
  const AuthSession({
    required this.token,
    required this.user,
  });

  final String token;
  final AuthUser user;

  Map<String, dynamic> toJson() => {
        'token': token,
        'user': user.toJson(),
      };

  static AuthSession fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: (json['token'] as String?) ?? '',
      user: AuthUser.fromJson((json['user'] as Map).cast<String, dynamic>()),
    );
  }
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.role,
    this.email,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String role;
  final String? email;

  String get displayName {
    final name = '${firstName.trim()} ${lastName.trim()}'.trim();
    return name.isEmpty ? phoneNumber : name;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phoneNumber': phoneNumber,
        'role': role,
      };

  static AuthUser fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] as String?) ?? '',
      firstName: (json['firstName'] as String?) ?? '',
      lastName: (json['lastName'] as String?) ?? '',
      email: json['email'] as String?,
      phoneNumber: (json['phoneNumber'] as String?) ?? '',
      role: (json['role'] as String?) ?? '',
    );
  }
}
