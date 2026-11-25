class JobApplication {
  final int id;
  final int jobId;
  final String firstName;
  final String lastName;
  final String email;
  final String cvFileName;
  final String cvOriginalName;
  final int cvSize;
  final String submissionId;
  final String fingerprint;
  final String createdAt;

  const JobApplication({
    required this.id,
    required this.jobId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.cvFileName,
    required this.cvOriginalName,
    required this.cvSize,
    required this.submissionId,
    required this.fingerprint,
    required this.createdAt,
  });

  factory JobApplication.fromJson(Map<String, dynamic> json) => JobApplication(
    id: json['id'] as int,
    jobId: json['jobId'] as int,
    firstName: json['firstName'] as String,
    lastName: json['lastName'] as String,
    email: json['email'] as String,
    cvFileName: json['cvFileName'] as String,
    cvOriginalName: json['cvOriginalName'] as String,
    cvSize: json['cvSize'] as int,
    submissionId: json['submissionId'] as String,
    fingerprint: json['fingerprint'] as String,
    createdAt: json['createdAt'] as String,
  );

  Map<String, dynamic> toJson() => {
    ...toReceiptJson(),
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'cvFileName': cvFileName,
    'cvOriginalName': cvOriginalName,
    'cvSize': cvSize,
    'submissionId': submissionId,
    'fingerprint': fingerprint,
  };

  // Al candidato restituiamo solo la ricevuta, senza esporre percorsi dei file.
  Map<String, dynamic> toReceiptJson() => {
    'id': id,
    'jobId': jobId,
    'createdAt': createdAt,
  };

  Map<String, dynamic> toCompanyJson(String jobTitle) => {
    ...toReceiptJson(),
    'jobTitle': jobTitle,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'cvOriginalName': cvOriginalName,
    'cvSize': cvSize,
  };
}
