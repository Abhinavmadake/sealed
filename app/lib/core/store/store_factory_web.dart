import 'package:sembast_web/sembast_web.dart';

Future<Database> openSealedDatabase() => databaseFactoryWeb.openDatabase('sealed');
