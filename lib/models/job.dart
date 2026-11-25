class Job {
  final int id;
  final int companyId;
  final String title;
  final String description;
  final String createdAt;

  const Job({
    required this.id,
    required this.companyId,
    required this.title,
    required this.description,
    required this.createdAt,
  });

  factory Job.fromJson(Map<String, dynamic> json) => Job(
    id: json['id'] as int,
    companyId: json['companyId'] as int,
    title: json['title'] as String,
    description: json['description'] as String,
    createdAt: json['createdAt'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'companyId': companyId,
    'title': title,
    'description': description,
    'createdAt': createdAt,
  };

  Map<String, dynamic> toPublicJson(String companyName) => {
    ...toJson(),
    'companyName': companyName,
  };
}
