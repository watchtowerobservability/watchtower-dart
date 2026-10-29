import 'dart:io';

import 'package:watchtower/src/tool/upload.dart';

Future<void> main(List<String> args) async => exit(await run(args, Platform.environment));
