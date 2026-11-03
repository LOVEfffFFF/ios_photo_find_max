/// 显示用的格式化工具。全部手写，不引 intl —— 只为几个固定的中文格式，
/// 多一个依赖就多一份 CI 变数。

const List<String> _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

/// 1024 进制，和系统「照片」App 的口径一致
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '$bytes B';
  final digits = value >= 100 ? 0 : decimals;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// 精确到字节，详情页用
String formatBytesExact(int bytes) {
  if (bytes <= 0) return '—';
  final readable = formatBytes(bytes, decimals: 2);
  final grouped = _groupDigits(bytes);
  return '$readable（$grouped 字节）';
}

String _groupDigits(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

String formatDate(double timestamp) {
  if (timestamp <= 0) return '—';
  final date = DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).round());
  return '${date.year}年${date.month}月${date.day}日 ${_two(date.hour)}:${_two(date.minute)}';
}

String formatDay(double timestamp) {
  if (timestamp <= 0) return '—';
  final date = DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).round());
  final weekday = _weekdays[(date.weekday - 1).clamp(0, 6)];
  return '${date.year}年${date.month}月${date.day}日 星期$weekday';
}

String formatDuration(double seconds) {
  if (seconds <= 0) return '—';
  final total = seconds.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) return '$h:${_two(m)}:${_two(s)}';
  return '$m:${_two(s)}';
}

/// 网格角标用：0:05 / 1:23
String formatDurationShort(double seconds) {
  if (seconds <= 0) return '';
  return formatDuration(seconds);
}

String formatCoordinates(double lat, double lon) {
  if (lat == 0 && lon == 0) return '—';
  return '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
