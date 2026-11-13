abstract final class Labels {
  static const accountKey = 'sealed.account.v1';
  static const privateKey = 'sealed.private.v1';
  static const recovery = 'sealed.recovery.v1';
  static const localSecret = 'sealed.local.v1';
  static String itemKey(String itemId) => 'sealed.itemkey.v1:$itemId';
  static String item(String itemId) => 'sealed.item.v1:$itemId';
}
