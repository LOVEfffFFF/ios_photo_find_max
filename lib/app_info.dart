/// 版本信息。
///
/// build 号由 CI 通过 `--dart-define=BUILD_TAG=...` 注入真实构建时间，
/// 这样「手机上装的是哪一版」有据可查 —— 侧载没有升级提示，版本号是唯一证据。
class AppInfo {
  const AppInfo._();

  static const String name = '大小相册';
  static const String version = '1.0.0';
  static const int buildNumber = 1;
  static const String buildTag =
      String.fromEnvironment('BUILD_TAG', defaultValue: 'dev');

  static String get display => '$version ($buildNumber) · $buildTag';
}
