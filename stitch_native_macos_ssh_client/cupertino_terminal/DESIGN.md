# Design System: The Kinetic Command

## 1. Overview & Creative North Star: "The Digital Artisan"
This design system moves beyond the cold, utilitarian nature of traditional terminal emulators. Our Creative North Star is **The Digital Artisan**. We treat code and connectivity as a craft, demanding a workspace that feels like a high-end physical studio—think of a bespoke walnut desk paired with precision-engineered aluminum tools.

We break the "standard app" template by embracing **intentional negative space** and **tonal layering**. While we strictly follow macOS Human Interface Guidelines (HIG), we elevate the experience through "Atmospheric Functionalism." This means we don't just show data; we curate it through a hierarchy that feels airy yet authoritative. We replace rigid grid lines with soft transitions of light and shadow, ensuring the developer feels focused, not fatigued.

---

## 2. Colors & Surface Philosophy
The palette is rooted in deep obsidian and slate tones, designed to make the terminal's syntax highlighting pop while keeping the chrome of the app secondary.

### The "No-Line" Rule
**Explicit Instruction:** Traditional 1px solid borders are strictly prohibited for sectioning. Boundaries must be defined solely through background color shifts.
*   **Implementation:** A `surface_container_low` sidebar should sit directly against a `surface` main window. The eye perceives the transition through the tonal shift, maintaining a seamless, premium feel.

### Surface Hierarchy & Nesting
Treat the UI as a series of physical layers, like stacked sheets of frosted glass.
*   **Level 0 (Base):** `surface` (#131313) - The window floor.
*   **Level 1 (Sub-sections):** `surface_container_low` (#1b1b1c) - Use for secondary utility panels.
*   **Level 2 (Active Areas):** `surface_container` (#202020) - The main terminal workspace.
*   **Level 3 (Floating/Contextual):** `surface_container_highest` (#353535) - Popovers and modals.

### The "Glass & Gradient" Rule
To honor macOS "Vibrancy," use Glassmorphism for floating elements.
*   **Floating Panels:** Apply `surface_variant` at 70% opacity with a `backdrop-filter: blur(20px)`.
*   **Signature Textures:** For primary action buttons, use a subtle linear gradient from `primary` (#adc6ff) to `primary_container` (#4b8eff) at a 135° angle. This adds a "jewel" quality that flat colors lack.

---

## 3. Typography: Editorial Precision
We utilize **Inter** (as a high-performance alternative to SF Pro for cross-platform alignment, while maintaining the HIG aesthetic) to create an editorial feel.

*   **Display Scale:** Use `display-sm` (2.25rem) for connection status or large metrics. It should feel like a magazine headline.
*   **The Power of Labels:** Use `label-md` (#0.75rem) in `on_surface_variant` (#c1c6d7) for metadata. The reduced contrast against the surface makes the actual SSH output (Body-LG) the hero of the screen.
*   **Monospace Integration:** While the system uses Inter for UI, the terminal output must use SF Mono. Maintain a 1.5 line-height for terminal text to ensure "breathability" in dense code blocks.

---

## 4. Elevation & Depth
Hierarchy is achieved through **Tonal Layering** rather than structural lines.

*   **The Layering Principle:** Place a `surface_container_lowest` card on a `surface_container_low` section. This creates a "recessed" look, perfect for grouping server credentials.
*   **Ambient Shadows:** For floating popovers (e.g., Quick Connect), use an extra-diffused shadow: `box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4)`. The shadow should feel like a soft glow, never a harsh outline.
*   **The "Ghost Border" Fallback:** If accessibility requires a container definition, use the `outline_variant` token at **15% opacity**. This creates a "whisper" of a boundary that disappears into the background at a glance.

---

## 5. Components

### Buttons
*   **Primary:** Gradient fill (`primary` to `primary_container`). Border-radius: `md` (0.75rem). Text: `on_primary` (#002e69).
*   **Tertiary (Ghost):** No background. Text uses `primary` color. Highlighting on hover uses `surface_container_high` with 0.5s ease-in-out.

### Input Fields (The "Soft Inset")
*   **Standard:** Use `surface_container_highest`. No border. Instead of a flashing cursor for the whole box, use a 2px bottom-accent in `primary` that animates width from 0% to 100% on focus.

### Cards & Lists
*   **Forbidden:** Divider lines.
*   **Alternative:** Use `sm` (0.25rem) spacing between list items, and use `surface_container_low` for the item background. On hover, shift the background to `surface_container_high`.

### Terminal Tabs
*   **Active:** `surface_container`.
*   **Inactive:** `surface_dim`.
*   **Visual Cue:** A subtle `primary` dot (4px) next to the tab label to indicate active traffic, rather than a heavy underline.

---

## 6. Do's and Don'ts

### Do:
*   **Embrace Asymmetry:** Align terminal output to the left, but keep server metadata in a right-aligned, low-contrast "info rail."
*   **Use SF Symbols:** Utilize the 'thin' or 'light' weight of SF Symbols to match the Inter typography scale.
*   **Respect the "Breath":** Give the terminal at least 24px of internal padding. Code should never touch the edge of the window.

### Don't:
*   **Don't use pure black (#000000):** Use `surface_container_lowest` (#0e0e0e) for the deepest blacks to maintain "ink depth" and avoid OLED smearing.
*   **Don't use 100% white for text:** Use `on_surface` (#e5e2e1) to prevent eye strain during late-night root-access sessions.
*   **Don't use standard system alerts:** Build custom "Glass" modals that blur the terminal behind them, keeping the user in the context of their work.