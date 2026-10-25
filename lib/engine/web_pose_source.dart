/// The browser's camera + MediaPipe pose source (web/rr_pose.js). On phones
/// the app uses [CameraPoseSource]; this stub keeps the import compiling there.
library;

export 'web_pose_source_stub.dart' if (dart.library.js_interop) 'web_pose_source_web.dart';
