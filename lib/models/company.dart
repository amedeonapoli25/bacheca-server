class Company {
  final int id;
  final String name;
  final String email;
  final String passwordHash;
  final String salt;
  final String createdAt;

  const Company({
    required this.id,
    required this.name,
    required this.email,
    required this.passwordHash,
    required this.salt,
    required this.createdAt,
  });

  factory Company.fromJson(Map<String, dynamic> json) => Company(
    id: json['id'] as int,
    name: json['name'] as String,
    email: json['email'] as String,
    passwordHash: json['passwordHash'] as String,
    salt: json['salt'] as String,
    createdAt: json['createdAt'] as String,
  );

  // Solo per il file sul server: include i dati necessari a verificare la password.
  Map<String, dynamic> toJson() => {
    ...toPublicJson(),
    'passwordHash': passwordHash,
    'salt': salt,
  };

  // Le risposte HTTP non contengono hash e sale.
  Map<String, dynamic> toPublicJson() => {
    'id': id,
    'name': name,
    'email': email,
    'createdAt': createdAt,
  };
}
