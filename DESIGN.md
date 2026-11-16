---
name: Paperwhite Monochrome
colors:
  surface: '#f9f9f9'
  surface-dim: '#dadada'
  surface-bright: '#f9f9f9'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f4f3f3'
  surface-container: '#eeeeee'
  surface-container-high: '#e8e8e8'
  surface-container-highest: '#e2e2e2'
  on-surface: '#1a1c1c'
  on-surface-variant: '#4c4546'
  inverse-surface: '#2f3131'
  inverse-on-surface: '#f1f1f1'
  outline: '#7e7576'
  outline-variant: '#cfc4c5'
  surface-tint: '#5e5e5e'
  primary: '#000000'
  on-primary: '#ffffff'
  primary-container: '#1b1b1b'
  on-primary-container: '#848484'
  inverse-primary: '#c6c6c6'
  secondary: '#5e5e5e'
  on-secondary: '#ffffff'
  secondary-container: '#e1dfdf'
  on-secondary-container: '#626262'
  tertiary: '#000000'
  on-tertiary: '#ffffff'
  tertiary-container: '#1b1b1b'
  on-tertiary-container: '#848484'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#e2e2e2'
  primary-fixed-dim: '#c6c6c6'
  on-primary-fixed: '#1b1b1b'
  on-primary-fixed-variant: '#474747'
  secondary-fixed: '#e4e2e2'
  secondary-fixed-dim: '#c7c6c6'
  on-secondary-fixed: '#1b1c1c'
  on-secondary-fixed-variant: '#464747'
  tertiary-fixed: '#e2e2e2'
  tertiary-fixed-dim: '#c6c6c6'
  on-tertiary-fixed: '#1b1b1b'
  on-tertiary-fixed-variant: '#474747'
  background: '#f9f9f9'
  on-background: '#1a1c1c'
  surface-variant: '#e2e2e2'
typography:
  display:
    fontFamily: Literata
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg:
    fontFamily: Literata
    fontSize: 26px
    fontWeight: '600'
    lineHeight: 34px
    letterSpacing: -0.005em
  headline-lg-mobile:
    fontFamily: Literata
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
  headline-md:
    fontFamily: Literata
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 26px
  headline-sm:
    fontFamily: Literata
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-lg:
    fontFamily: Literata
    fontSize: 17px
    fontWeight: '400'
    lineHeight: 26px
  body-md:
    fontFamily: Literata
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 22px
  body-sm:
    fontFamily: Literata
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 18px
    letterSpacing: 0.02em
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.03em
  label-sm:
    fontFamily: Inter
    fontSize: 10px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.05em
spacing:
  gutter: 1rem
  gutter-compact: 0.5rem
  margin: 1.25rem
  margin-mobile: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.25rem
---

## Brand & Style

This design system is engineered specifically for 300 PPI electrophoretic ink (E-Ink) displays, tailored for reflective reading environments and high-ambient-sunlight legibility. The aesthetic is strictly rooted in print editorial minimalism: zero gradients, zero dynamic blur effects, and zero multi-stop drop shadows. 

The emotional signature is quiet, durable, and literary. Interactions prioritize instant optical clarity, deterministic contrast transitions, and total elimination of grayscale antialiasing artifacts that trigger uneven E-Ink screen refreshes (ghosting). Visual hierarchy relies entirely on typographic weight, whitespace rhythm, and razor-sharp geometric framing.

## Colors

The palette adheres strictly to a 4-tier monochrome scale optimized for electrophoretic capsule states (black, white, and stable dithered/mid-tone grays):

- **Primary (`#000000`)**: Deep Carbon. Applied to primary text, active tap targets, high-emphasis icons, and structural 1px borders. Ensures 100% black pigment orientation for max reflectance delta.
- **Secondary (`#666666`)**: Mineral Gray. Formulated strictly for secondary metadata, timestamps, author bylines, and inactive toggles. Preserves WCAG AAA contrast against pure white backgrounds on reflective E-Ink stacks.
- **Hairline / Neutral (`#E5E5E5`)**: Ash White. Reserved for 1px hairline segmentations, structural card outlines, and inactive track indicators.
- **Surface Canvas (`#FFFFFF`)**: Pure White. The primary canvas substrate mirroring reflective micro-capsule paper.

Never introduce intermediate alpha channels, transparencies, or colored tints; all color steps must be discrete hex values to minimize display waveform processing overhead.

## Typography

The type system blends literary tradition with surgical interface legibility. 

- **Display & Body (`Literata`)**: A bookish, warm transitional serif designed specifically for digital reading screens. Its horizontal proportions, sturdy stems, and open counters maintain structural integrity across fluctuating front-light levels without filling in or dithering.
- **Labels & System Meta (`Inter`)**: A neutral, systematic neo-grotesque sans-serif deployed for persistent chrome, battery/clock status indicators, pagination markers, buttons, and system controls.

All line heights are deliberately tall to compensate for the micro-textural spread of E-Ink capsules.

## Layout & Spacing

Designed for the 6.8-inch display of the Paperwhite 5 (1236 x 1648 physical pixels at 300 PPI). The layout adheres to a fixed-width grid model anchored by 16px (`1rem`) column gutters and safe margins of 20px (`1.25rem`) to accommodate hardware bezel grip thresholds.

Horizontal layouts utilize 4-column structures for library and store views, collapsing to single-column streams with full horizontal bleed for active book reading surfaces. All layout pacing is calculated on a 4px baseline sub-grid (`0.25rem` intervals) to ensure pixel-perfect 1:1 hardware pixel snaps, preventing anti-aliased subpixel blurring during page turns.

## Elevation & Depth

This design system avoids all raster shadows, layered blurs, and pseudo-3D lighting models. Depth is achieved exclusively through **structural containment** and **binary inversion**:

1. **Base Tier (0dp)**: Surface canvas in `#FFFFFF`.
2. **Contained Tier (1dp)**: Surfaces outlined with crisp, non-anti-aliased `1px solid #E5E5E5` hairline borders or delineated by single horizontal dividers.
3. **Modal & Floating Chrome Tier (2dp)**: Flyouts, context menus, and dictionary popups use a pure `#FFFFFF` background bound by a crisp `1px solid #000000` perimeter border. A 1px `#FFFFFF` inset separates content from the black edge.
4. **Active State / Selection**: Full binary inversion—background transitions to `#000000` with foreground text and icons switching instantly to `#FFFFFF`.

## Shapes

The design system enforces a strict **Sharp (`0`)** shape language. All corners for buttons, input fields, cards, modal sheets, and notification banners are strictly `0px` (`roundedness: 0`).

Sharp corners eliminate the circular arc sub-pixel graying common to low-refresh electrophoretic screens. Every boundary renders as a single, contiguous horizontal or vertical line aligned strictly to the pixel matrix, ensuring maximal edge crispness under direct ambient sunlight.

## Components

### Buttons
- **Primary**: Solid `#000000` fill with `#FFFFFF` text in `Inter` semi-bold. Border: none. Zero radius.
- **Secondary**: `#FFFFFF` background with `1px solid #000000` border, `#000000` text.
- **Tertiary / Ghost**: `#FFFFFF` background, no border, `#000000` text with an explicit underline (`1px solid #000000`, 2px offset).
- **Pressed / Active State**: Instant binary inversion (White inverted to Black, Black inverted to White) with no easing transitions or opacity dips.

### Cards & Tile Items
- Books and reading panels are housed in flat containers with a `1px solid #E5E5E5` perimeter border and `#FFFFFF` background.
- Cover art sits flush without drop shadows. If metadata is included, it is separated by a horizontal `1px solid #E5E5E5` hairline.

### Chips & Filters
- Compact horizontal rectangles. Unselected: `#FFFFFF` background, `1px solid #E5E5E5` border, `#666666` text (`label-sm`).
- Selected: `#000000` fill, `1px solid #000000` border, `#FFFFFF` text.

### Form Inputs & Search Fields
- Rectangular boxes framed in `1px solid #000000`. 
- Placeholder text set in `#666666`. 
- Active focus is signaled by a thick `2px solid #000000` outline (never colored glows).

### Checkboxes & Radio Buttons
- **Checkboxes**: Sharp square (`16px × 16px`) with `1px solid #000000`. Checked state contains a solid `#000000` square inset (10px × 10px).
- **Radio Buttons**: Sharp diamond or square token with a centered 6px solid `#000000` dot.

### Lists & Navigation Rows
- Full-width tap targets with bottom-only `1px solid #E5E5E5` dividers.
- Chevron icons rendered strictly in high-contrast solid stroke vectors at 1.5px thickness. No faint gray tap ripples.

### Progress & Scrubbers
- Solid `2px solid #E5E5E5` track background.
- Active progress filled with solid `#000000`. Scrubber handle is a crisp `8px × 16px` vertical black block.
