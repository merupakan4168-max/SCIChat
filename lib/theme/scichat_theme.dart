import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SciChatColors extends ThemeExtension<SciChatColors> {
  final Color surface0;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color accent;
  final Color accentDim;
  final Color accentFaint;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color borderSubtle;
  final Color borderMedium;
  final Color tagCs;
  final Color tagTextCs;
  final Color tagPhys;
  final Color tagTextPhys;
  final Color tagMath;
  final Color tagTextMath;
  final Color tagBio;
  final Color tagTextBio;
  final Color tagEcon;
  final Color tagTextEcon;

  const SciChatColors({
    required this.surface0, required this.surface1, required this.surface2, required this.surface3,
    required this.accent, required this.accentDim, required this.accentFaint,
    required this.textPrimary, required this.textSecondary, required this.textMuted,
    required this.borderSubtle, required this.borderMedium,
    required this.tagCs, required this.tagTextCs,
    required this.tagPhys, required this.tagTextPhys,
    required this.tagMath, required this.tagTextMath,
    required this.tagBio, required this.tagTextBio,
    required this.tagEcon, required this.tagTextEcon,
  });

  @override
  SciChatColors copyWith({
    Color? surface0, Color? surface1, Color? surface2, Color? surface3,
    Color? accent, Color? accentDim, Color? accentFaint,
    Color? textPrimary, Color? textSecondary, Color? textMuted,
    Color? borderSubtle, Color? borderMedium,
    Color? tagCs, Color? tagTextCs,
    Color? tagPhys, Color? tagTextPhys,
    Color? tagMath, Color? tagTextMath,
    Color? tagBio, Color? tagTextBio,
    Color? tagEcon, Color? tagTextEcon,
  }) {
    return SciChatColors(
      surface0: surface0 ?? this.surface0, surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2, surface3: surface3 ?? this.surface3,
      accent: accent ?? this.accent, accentDim: accentDim ?? this.accentDim,
      accentFaint: accentFaint ?? this.accentFaint,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderMedium: borderMedium ?? this.borderMedium,
      tagCs: tagCs ?? this.tagCs, tagTextCs: tagTextCs ?? this.tagTextCs,
      tagPhys: tagPhys ?? this.tagPhys, tagTextPhys: tagTextPhys ?? this.tagTextPhys,
      tagMath: tagMath ?? this.tagMath, tagTextMath: tagTextMath ?? this.tagTextMath,
      tagBio: tagBio ?? this.tagBio, tagTextBio: tagTextBio ?? this.tagTextBio,
      tagEcon: tagEcon ?? this.tagEcon, tagTextEcon: tagTextEcon ?? this.tagTextEcon,
    );
  }

  @override
  SciChatColors lerp(ThemeExtension<SciChatColors>? other, double t) {
    if (other is! SciChatColors) return this;
    return SciChatColors(
      surface0: Color.lerp(surface0, other.surface0, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDim: Color.lerp(accentDim, other.accentDim, t)!,
      accentFaint: Color.lerp(accentFaint, other.accentFaint, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderMedium: Color.lerp(borderMedium, other.borderMedium, t)!,
      tagCs: Color.lerp(tagCs, other.tagCs, t)!,
      tagTextCs: Color.lerp(tagTextCs, other.tagTextCs, t)!,
      tagPhys: Color.lerp(tagPhys, other.tagPhys, t)!,
      tagTextPhys: Color.lerp(tagTextPhys, other.tagTextPhys, t)!,
      tagMath: Color.lerp(tagMath, other.tagMath, t)!,
      tagTextMath: Color.lerp(tagTextMath, other.tagTextMath, t)!,
      tagBio: Color.lerp(tagBio, other.tagBio, t)!,
      tagTextBio: Color.lerp(tagTextBio, other.tagTextBio, t)!,
      tagEcon: Color.lerp(tagEcon, other.tagEcon, t)!,
      tagTextEcon: Color.lerp(tagTextEcon, other.tagTextEcon, t)!,
    );
  }

  Color categoryColor(String category) {
    final cat = category.toLowerCase();
    if (cat.startsWith('cs')) return tagCs;
    if (cat.startsWith('physics') || cat.startsWith('quant') || cat.startsWith('astro')) return tagPhys;
    if (cat.startsWith('math')) return tagMath;
    if (cat.startsWith('q-bio') || cat.startsWith('bio')) return tagBio;
    if (cat.startsWith('econ') || cat.startsWith('q-fin')) return tagEcon;
    return surface3;
  }

  Color categoryTextColor(String category) {
    final cat = category.toLowerCase();
    if (cat.startsWith('cs')) return tagTextCs;
    if (cat.startsWith('physics') || cat.startsWith('quant') || cat.startsWith('astro')) return tagTextPhys;
    if (cat.startsWith('math')) return tagTextMath;
    if (cat.startsWith('q-bio') || cat.startsWith('bio')) return tagTextBio;
    if (cat.startsWith('econ') || cat.startsWith('q-fin')) return tagTextEcon;
    return textSecondary;
  }
}

extension SciChatThemeContext on BuildContext {
  SciChatColors get colors => Theme.of(this).extension<SciChatColors>()!;
  TextTheme get typography => Theme.of(this).textTheme;
}

class SciChatTheme {
  static const darkColors = SciChatColors(
    surface0: Color(0xFF050505), // Ultra dark OLED
    surface1: Color(0xFF111111), // Slightly elevated
    surface2: Color(0xFF1C1C1E), // Subtle separation
    surface3: Color(0xFF2C2C2E), // Borders, inputs
    accent: Color(0xFF7E84FA),   // Curated Soft Indigo
    accentDim: Color(0xFF5A61D9),// Deeper indigo
    accentFaint: Color(0xFF22244A),// Tinted indigo background
    textPrimary: Color(0xFFF0F0F0),// Sharp white
    textSecondary: Color(0xFFA0A0A5),// Cool gray
    textMuted: Color(0xFF707075),  // Dim gray
    borderSubtle: Color(0xFF222225),// Very subtle border
    borderMedium: Color(0xFF333336),// Medium border
    tagCs: Color(0xFF121B33),      
    tagTextCs: Color(0xFF86A8E7),
    tagPhys: Color(0xFF0D251A),    
    tagTextPhys: Color(0xFF70C295),
    tagMath: Color(0xFF331414),    
    tagTextMath: Color(0xFFE28B8B),
    tagBio: Color(0xFF1E2A0E),     
    tagTextBio: Color(0xFFA5C460),
    tagEcon: Color(0xFF301D0D),    
    tagTextEcon: Color(0xFFD3A26D),
  );

  static const lightColors = SciChatColors(
    surface0: Color(0xFFFCFCFC), // Crisp near-white
    surface1: Color(0xFFF4F4F5), // Soft subtle gray
    surface2: Color(0xFFEBEBEF), // Elevated gray
    surface3: Color(0xFFDFDFE3), // Interactive gray
    accent: Color(0xFF5257E5),   // Premium Indigo/Violet
    accentDim: Color(0xFF3F44BF),// Deeper Indigo
    accentFaint: Color(0xFFEDEEFC),// Very light indigo wash
    textPrimary: Color(0xFF111113),// Almost black, sharp
    textSecondary: Color(0xFF606068),// Medium gray
    textMuted: Color(0xFF8E8E96),  // Light gray text
    borderSubtle: Color(0xFFE5E5EA),// Crisp border
    borderMedium: Color(0xFFD1D1D6),// Stronger border
    tagCs: Color(0xFFE6EDFA),      
    tagTextCs: Color(0xFF3B66B5),
    tagPhys: Color(0xFFE1F5EB),    
    tagTextPhys: Color(0xFF2D7B54),
    tagMath: Color(0xFFFAEBEB),    
    tagTextMath: Color(0xFFB54545),
    tagBio: Color(0xFFF0F5E1),     
    tagTextBio: Color(0xFF6A8A25),
    tagEcon: Color(0xFFFDF5ED),    
    tagTextEcon: Color(0xFFB0722D),
  );

  static TextTheme _getTextTheme(SciChatColors c) => TextTheme(
    displayLarge: GoogleFonts.playfairDisplay(fontSize: 30, fontWeight: FontWeight.w700, color: c.textPrimary, letterSpacing: -0.5, height: 1.2),
    displayMedium: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.w600, color: c.textPrimary, letterSpacing: -0.3, height: 1.2),
    displaySmall: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w600, color: c.textPrimary, letterSpacing: -0.2, height: 1.25),
    headlineLarge: GoogleFonts.sourceSerif4(fontSize: 24, fontWeight: FontWeight.w600, color: c.textPrimary, height: 1.2),
    headlineMedium: GoogleFonts.sourceSerif4(fontSize: 20, fontWeight: FontWeight.w600, color: c.textPrimary, height: 1.25),
    headlineSmall: GoogleFonts.sourceSerif4(fontSize: 16, fontWeight: FontWeight.w600, color: c.textSecondary, height: 1.35),
    bodyLarge: GoogleFonts.sourceSerif4(fontSize: 16, fontWeight: FontWeight.w400, color: c.textPrimary, height: 1.55),
    bodyMedium: GoogleFonts.sourceSerif4(fontSize: 14, fontWeight: FontWeight.w400, color: c.textSecondary, height: 1.45),
    bodySmall: GoogleFonts.sourceSerif4(fontSize: 12, fontWeight: FontWeight.w400, color: c.textMuted, height: 1.35),
    labelLarge: GoogleFonts.sourceSerif4(fontSize: 14, fontWeight: FontWeight.w500, color: c.textPrimary, letterSpacing: 0.1),
    labelMedium: GoogleFonts.sourceSerif4(fontSize: 12, fontWeight: FontWeight.w500, color: c.textSecondary, letterSpacing: 0.2),
    labelSmall: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w400, color: c.textMuted, letterSpacing: 0.3),
  );

  static ThemeData getTheme(bool isDark) {
    final c = isDark ? darkColors : lightColors;
    
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: c.accent,
        onPrimary: isDark ? const Color(0xFF0D0F0E) : const Color(0xFFFFFFFF),
        secondary: c.accentDim,
        onSecondary: c.textPrimary,
        error: Colors.red.shade900,
        onError: Colors.white,
        surface: c.surface1,
        onSurface: c.textPrimary,
      ),
      scaffoldBackgroundColor: c.surface0,
      textTheme: _getTextTheme(c),
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface0,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.playfairDisplay(
          fontSize: 20, fontWeight: FontWeight.w700,
          color: c.textPrimary, letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: c.textSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface3,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.borderMedium)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.borderMedium)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.accent, width: 1.5)),
        hintStyle: GoogleFonts.sourceSerif4(color: c.textMuted, fontSize: 14),
      ),
      dividerTheme: DividerThemeData(color: c.borderSubtle, thickness: 1),
      cardTheme: CardThemeData(
        color: c.surface1,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.borderSubtle),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface3,
        selectedColor: c.accentFaint,
        side: BorderSide(color: c.borderMedium),
        labelStyle: GoogleFonts.sourceSerif4(fontSize: 12, color: c.textSecondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
    );
  }

  static ThemeData get dark => getTheme(true);
  static ThemeData get light => getTheme(false);
}

