import 'package:flutter/material.dart';

/// 配色体系：**中性灰 / 黑白 + 单一低饱和强调色**。
///
/// 刻意不用高饱和蓝紫，也不使用渐变、发光、玻璃拟态。
/// - 表面色阶（surface / surfaceContainer*）全部走低彩度中性灰，
///   深浅色都保持"纸张 + 石墨"的质感；
/// - 强调色只保留一个：低饱和松石绿（[accentSeed]），用于主按钮、
///   选中态、进度条；
/// - 语义色（error / tertiary）保持 MD3 默认语义，不额外装饰。
abstract final class AppColors {
  /// 唯一强调色种子（近黑，黑白线条风）。
  ///
  /// 主操作用黑（浅色）/白（深色），无彩色点缀；
  /// 语义色（error/tertiary）保留 MD3 语义用于错误等场景。
  static const Color accentSeed = Color(0xFF17181A);

  static ColorScheme light() {
    final base = ColorScheme.fromSeed(
      seedColor: accentSeed,
      brightness: Brightness.light,
    );
    return base.copyWith(
      primary: const Color(0xFF17181A),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFECEDEF),
      onPrimaryContainer: const Color(0xFF17181A),
      secondary: const Color(0xFF43474C),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFE4E6E9),
      onSecondaryContainer: const Color(0xFF1D2023),
      tertiary: const Color(0xFF5A5D6B),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFE1E2EC),
      onTertiaryContainer: const Color(0xFF2C2F3A),

      // 中性表面：明亮浅灰，保证"简白"
      surface: const Color(0xFFFAFAFB),
      onSurface: const Color(0xFF17181A),
      onSurfaceVariant: const Color(0xFF5C6064),
      surfaceDim: const Color(0xFFDCDDDF),
      surfaceBright: const Color(0xFFFCFCFD),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFFFFFFF),
      surfaceContainer: const Color(0xFFF3F4F5),
      surfaceContainerHigh: const Color(0xFFEDEEF0),
      surfaceContainerHighest: const Color(0xFFE7E9EB),

      outline: const Color(0xFF8A8F94),
      outlineVariant: const Color(0xFFDCDFE3),
      inverseSurface: const Color(0xFF2F3133),
      onInverseSurface: const Color(0xFFF1F2F3),
      inversePrimary: const Color(0xFFE4E6E9),
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      error: const Color(0xFFB3261E),
      onError: Colors.white,
      errorContainer: const Color(0xFFF9DEDC),
      onErrorContainer: const Color(0xFF410E0B),
    );
  }

  static ColorScheme dark() {
    final base = ColorScheme.fromSeed(
      seedColor: accentSeed,
      brightness: Brightness.dark,
    );
    return base.copyWith(
      primary: const Color(0xFFF2F3F5),
      onPrimary: const Color(0xFF17181A),
      primaryContainer: const Color(0xFF2A2C2F),
      onPrimaryContainer: const Color(0xFFE6E7E9),
      secondary: const Color(0xFFB3C0C7),
      onSecondary: const Color(0xFF1F2A2F),
      secondaryContainer: const Color(0xFF2A2C2F),
      onSecondaryContainer: const Color(0xFFE6E7E9),
      tertiary: const Color(0xFFC4C6D2),
      onTertiary: const Color(0xFF2D3039),
      tertiaryContainer: const Color(0xFF444650),
      onTertiaryContainer: const Color(0xFFE1E2EC),

      // 深色表面：石墨黑，不带彩色偏色
      surface: const Color(0xFF121315),
      onSurface: const Color(0xFFE6E7E9),
      onSurfaceVariant: const Color(0xFFA9ADB2),
      surfaceDim: const Color(0xFF121315),
      surfaceBright: const Color(0xFF383A3D),
      surfaceContainerLowest: const Color(0xFF0C0D0E),
      surfaceContainerLow: const Color(0xFF181A1C),
      surfaceContainer: const Color(0xFF1E2023),
      surfaceContainerHigh: const Color(0xFF282A2D),
      surfaceContainerHighest: const Color(0xFF333538),

      outline: const Color(0xFF8B9095),
      outlineVariant: const Color(0xFF3D4145),
      inverseSurface: const Color(0xFFE6E7E9),
      onInverseSurface: const Color(0xFF2F3133),
      inversePrimary: const Color(0xFF17181A),
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      error: const Color(0xFFF2B8B5),
      onError: const Color(0xFF601410),
      errorContainer: const Color(0xFF8C1D18),
      onErrorContainer: const Color(0xFFF9DEDC),
    );
  }
}
