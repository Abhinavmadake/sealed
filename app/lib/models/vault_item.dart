enum ItemType { login, note }

class VaultItem {
  const VaultItem({
    required this.id,
    this.type = ItemType.login,
    this.title = '',
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.favorite = false,
    required this.modifiedAt,
  });

  final String id;
  final ItemType type;
  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final bool favorite;
  final DateTime modifiedAt;

  static const mergeFields = ['type', 'title', 'username', 'password', 'url', 'notes', 'favorite'];

  static const fieldLabels = {
    'type': 'Type',
    'title': 'Title',
    'username': 'Username',
    'password': 'Password',
    'url': 'Website',
    'notes': 'Notes',
    'favorite': 'Favourite',
  };

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'favorite': favorite,
        'modified': modifiedAt.toUtc().toIso8601String(),
      };

  factory VaultItem.fromJson(String id, Map<String, dynamic> json) => VaultItem(
        id: id,
        type: ItemType.values.firstWhere((t) => t.name == json['type'], orElse: () => ItemType.login),
        title: json['title'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        url: json['url'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        favorite: json['favorite'] as bool? ?? false,
        modifiedAt: DateTime.tryParse(json['modified'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  VaultItem copyWith({
    String? id,
    ItemType? type,
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    bool? favorite,
    DateTime? modifiedAt,
  }) =>
      VaultItem(
        id: id ?? this.id,
        type: type ?? this.type,
        title: title ?? this.title,
        username: username ?? this.username,
        password: password ?? this.password,
        url: url ?? this.url,
        notes: notes ?? this.notes,
        favorite: favorite ?? this.favorite,
        modifiedAt: modifiedAt ?? this.modifiedAt,
      );
}
