# SCIChat Design System

This document serves as the single source of truth for all UI/UX decisions in the SCIChat app. It is designed to ensure visual consistency, premium feel, and avoidance of generic "AI slop" patterns.

## 1. Visual Principles & Character

- **Editorial & Academic:** SCIChat is a research tool, not a social media app. It should feel like reading a high-end digital academic journal (e.g., The Atlantic, MIT Technology Review).
- **Premium Restraint:** Use space, typography, and subtle contrast rather than loud colors or heavy boxes to define hierarchy.
- **Anti-Slop:** Avoid default Material/Cupertino components out of the box. Avoid generic 8px border radii everywhere. Avoid predictable symmetry.

## 2. Typography

Typography is the core of SCIChat's identity.

- **Display & Large Headers:** `Playfair Display` (Weight: 700/600). Used for app bars, empty state heroes, and major section titles. Tight letter spacing (`-0.2` to `-0.5`).
- **Body & Reading Text:** `Source Serif 4` (Weight: 400/500/600). Used for chat bubbles, paper summaries, and general text. Excellent legibility for long-form reading. High line-height (`1.45` to `1.7`).
- **Data & Metadata:** `JetBrains Mono` (Weight: 400). Used for IDs, dates, and technical metadata. Small font size (`11px`), slight letter spacing (`0.3`).
- **Labels (Optional fallback):** `Inter` or standard sans-serif only for strict UI elements like button labels if Serif feels too heavy, but Serif is preferred for consistency.

## 3. Color System

SCIChat uses a custom "Midnight Slate & Indigo" palette, strictly avoiding default Material purple/blue.

- **Surfaces (Dark Mode Focus):**
  - `surface0` (`#050505`): Ultra-dark OLED background.
  - `surface1` (`#111111`): Slightly elevated cards/bubbles.
  - `surface2` (`#1C1C1E`): Subtle separations or chips.
  - `surface3` (`#2C2C2E`): Borders, input fields.
- **Accents:**
  - `accent` (`#7E84FA`): Curated Soft Indigo.
  - `accentDim` (`#5A61D9`): Deeper indigo for pressed states.
- **Text:**
  - `textPrimary` (`#F0F0F0`): Sharp white (never pure #FFFFFF for reading comfort).
  - `textSecondary` (`#A0A0A5`): Cool gray.
  - `textMuted` (`#707075`): Dim gray for metadata.
- **Categorical Tags:** Tailored soft colors for specific disciplines (e.g., Physics is deep green `tagPhys`, CS is deep blue `tagCs`).

## 4. Spacing & Sizing

- **Avoid Generic 8px:** Do not default to 8px padding/margin everywhere. Use intentional spacing to create hierarchy.
- **Reading Width:** Keep line lengths comfortable. Chat bubbles shouldn't stretch edge-to-edge on tablets.
- **Asymmetric Padding:** E.g., `padding: EdgeInsets.fromLTRB(16, 12, 16, 24)` to ground elements visually.

## 5. Components

### Buttons

- **Primary:** Solid `textPrimary` (white) background with `surface0` (black) text. Gives a brutalist, high-end feel.
- **Secondary:** Outlined or subtle background (`surface2`).
- **Interaction:** Must include scale down on press (`AnimatedScale` to 0.94 or 0.96) and haptic feedback.

### Cards (Paper Cards)

- Flat design (`elevation: 0`).
- Subtle borders (`borderSubtle` 1px).
- Generous internal padding (e.g., 16px to 20px).

### Input Area (Composer)

- **Current Pattern:** Floating Pill.
  - *Rule:* If floating, use a generous radius (e.g., `24px`), heavy soft shadow (`blurRadius: 16`, `offset: 0, 4`), and dynamic border colors that react to focus. Do *not* use a generic pill with weak shadows.

## 6. Interaction States & Feedback

- **Haptics:** Always use `HapticFeedback.lightImpact()` on:
  - Sending a message.
  - Tapping a button/paper.
  - Toggling a favorite.
- **Tap States:** Avoid default Material ripple. Use opacity changes (`GestureDetector` + `setState`) or `AnimatedScale`.

## 7. Motion & Animation Principles

- **Library:** `flutter_animate`.
- **Durations:** Fast and snappy (150ms - 300ms).
- **Curves:** `Curves.easeOutCubic` or `Curves.easeOutExpo`. Never linear.
- **Entrance:** Fade in + slight slide up (`.slideY(begin: 0.05)`).
- **Micro-interactions:** Buttons scale down on press. Input borders transition smoothly.

## 8. AI States (Loading, Empty, Error)

- **No "AI Slop" Spinners:** Avoid generic "Memahami pertanyaan..." loading text.
- **Dynamic Status:** AI loading states must be granular and intent-based (e.g., "Mencari paper...", "Membaca dokumen...", "Menyusun tabel...").
- **Empty States:** Do not use static lists of questions. Use randomized, curated suggestions that appear gracefully (e.g., typewriter effect).

## 9. Accessibility

- Maintain high contrast for `textPrimary` and `textSecondary`.
- Ensure touch targets are at least 44x44 (e.g., wrapping `Icon` in `IconButton` or adding padding to `GestureDetector`).

## 10. Navigation Patterns

- **Primary Flows:** Standard push/pop for deep dives (e.g., Chat -> Paper Detail).
- **Contextual Actions:** Use `showModalBottomSheet` for heavy secondary actions (e.g., Summarize Paper) so the user doesn't lose their chat context.
- **Top Bar:** Keep it minimal. No heavy drop shadows on AppBars. Use a 1px hairline border at the bottom of the AppBar to separate it from the body.

## 11. Rules for AI-Generated UI (Anti-Slop Guidelines)

When adding new UI, ask:

1. Is it perfectly symmetrical? If yes, try making it asymmetrical.
2. Is the color palette purely out-of-the-box Material? If yes, use `SciChatColors`.
3. Are the corners exactly 8px? Consider if it needs sharper edges (4px) for data or rounder edges (24px) for distinct floating elements.
4. Is it a default CircularProgressIndicator in the middle of the screen? Use skeleton loaders or inline text states instead.

---
*(Drafted during initial AI-User planning phase. Subject to evolution as the app grows.)*
