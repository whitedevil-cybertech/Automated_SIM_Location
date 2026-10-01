# Design

## Color Palette & Theme

**Design objective:** restrained, professional, high-legibility interface optimized for operational workflows and sensitive information.

### Theme

Use a **light-first neutral theme** with a dark theme available later if required.

The visual hierarchy should be created primarily through:

- Neutral surfaces
- Typography
- Spacing
- Borders
- Semantic status colors
- Controlled elevation

Avoid gradients, decorative illustrations, excessive shadows, glassmorphism, and highly saturated backgrounds.

Flutter's Material 3 `ColorScheme` provides an appropriate foundation for centralized color management.

### Proposed Light Palette

| Token | Example | Purpose |
|---|---|---|
| `primary` | `#17324D` | Main navigation and primary actions |
| `primaryContainer` | `#DCE8F2` | Selected/secondary primary surfaces |
| `secondary` | `#52677A` | Supporting actions |
| `surface` | `#F8FAFC` | Application background |
| `surfaceContainer` | `#FFFFFF` | Cards and elevated content |
| `textPrimary` | `#17212B` | Main text |
| `textSecondary` | `#52606D` | Supporting text |
| `border` | `#CBD5E1` | Dividers and field borders |
| `success` | `#18794E` | Completed/success state |
| `warning` | `#9A6700` | Warning/pending condition |
| `error` | `#B42318` | Failure/error state |
| `info` | `#175CD3` | Informational state |

> These hexadecimal values are **project design choices**, not official IFSO colors.

### Accessibility

Normal text should target at least **4.5:1 contrast**, while large text should target at least **3:1**, consistent with WCAG 2.2 AA guidance.

Status must never be communicated through color alone.

Example:

> 🟢 **COMPLETED**  
> Location response received and processed.

rather than displaying only a green indicator.

---

## Fonts

Use a simple two-font strategy.

### Primary UI Font

**Inter**

Use for:

- Navigation
- Buttons
- Forms
- Headings
- Tables
- Status labels
- General application content

If Inter is not bundled, use an appropriate platform sans-serif fallback.

### Monospace Font

**JetBrains Mono** or platform monospace fallback.

Use only for technical information:

- Request IDs
- Audit IDs
- Timestamps
- Hashes
- Raw SMS responses
- Technical error identifiers
- Log/event identifiers

Example:

```text
Request ID
REQ-7F2A91

SHA-256
7f3a...c821
```

Do not use monospace for normal UI text.

---

## Typography

The hierarchy should be compact but readable because the application may display relatively dense forensic information.

| Style | Size | Weight | Usage |
|---|---:|---:|---|
| Display | 28–32 px | 600–700 | Major screen heading |
| H1 | 24 px | 600 | Page heading |
| H2 | 20 px | 600 | Section heading |
| H3 | 17–18 px | 600 | Card/subsection heading |
| Body Large | 16 px | 400 | Important body content |
| Body | 14–16 px | 400 | Normal content |
| Label | 13–14 px | 500–600 | Form labels/status |
| Caption | 12 px | 400 | Secondary metadata |
| Technical | 12–14 px | 400 | IDs/raw evidence |

Prefer comfortable line height rather than tightly packed text.

Flutter's Material 3 typography system provides a structured `TextTheme`, making centralized typography preferable to individually styling every widget.

### Sensitive Information

Target numbers and location information should have deliberate visual hierarchy.

Example:

```text
TARGET NUMBER

+91 XXXXXXX123

STATUS
WAITING_RESPONSE
```

Where appropriate, default to partial masking rather than displaying sensitive identifiers unnecessarily.

---

## Design Tokens & Examples

All visual values should be represented as reusable tokens rather than hard-coded throughout the application.

### Color Tokens

```text
color.primary
color.primaryContainer

color.surface
color.surfaceContainer

color.textPrimary
color.textSecondary

color.border

color.success
color.warning
color.error
color.info
```

### Spacing Tokens

Use an 8-point spacing system:

```text
space.1 = 4px
space.2 = 8px
space.3 = 12px
space.4 = 16px
space.5 = 20px
space.6 = 24px
space.8 = 32px
space.10 = 40px
```

### Shape Tokens

```text
radius.small  = 6px
radius.medium = 10px
radius.large  = 16px
```

Avoid excessive rounding. This is an operational application rather than a consumer social application.

### Component Examples

#### Request Card

```text
┌──────────────────────────────────────────┐
│ Request #REQ-7F2A91       CREATED        │
│                                          │
│ Target     +91 XXXXXXX123                │
│ Operator   [Approved Profile]            │
│ Created    01 Oct 2026 · 13:42           │
│                                          │
│                    View Request →        │
└──────────────────────────────────────────┘
```

#### IO Review

```text
┌──────────────────────────────────────────┐
│ LOCATION REQUEST                         │
│                                          │
│ Target       +91 XXXXXXX123              │
│ Operator     Approved Operator Profile   │
│ Submitted by Officer                     │
│                                          │
│ [ Review Details ]                       │
│                                          │
│       [ Execute Location Request ]       │
└──────────────────────────────────────────┘
```

The execution action must be visually distinct from ordinary navigation.

#### Waiting State

```text
┌──────────────────────────────────────────┐
│ WAITING_RESPONSE                         │
│                                          │
│ Request transmitted from authorized     │
│ device.                                  │
│                                          │
│ Awaiting response...                     │
└──────────────────────────────────────────┘
```

#### Completed State

```text
┌──────────────────────────────────────────┐
│ ✓ COMPLETED                              │
│                                          │
│ Response received                        │
│ Received: 01 Oct 2026 · 13:47            │
│                                          │
│ [ View Result ] [ Share Result ]          │
└──────────────────────────────────────────┘
```

#### Audit Timeline

```text
13:42  CREATED
       Request submitted

13:44  PENDING_IO_REVIEW
       Request opened by IO

13:45  EXECUTING
       Location request initiated

13:47  COMPLETED
       Response received
```

### State Design

The UI should directly reflect the backend request lifecycle.

| State | UI Meaning | Visual Treatment |
|---|---|---|
| `CREATED` | Request submitted | Neutral |
| `PENDING_IO_REVIEW` | Waiting for IO | Informational |
| `EXECUTING` | IO initiated request | Active/emphasized |
| `WAITING_RESPONSE` | Awaiting response | Warning/pending |
| `COMPLETED` | Response processed | Success |
| `SMS_FAILED` | SMS transmission failed | Error |
| `TIMEOUT` | Response not received in expected window | Warning/Error |
| `RESPONSE_INVALID` | Response could not be validated | Error |

These are **application states**, not claims about any telecom provider's internal status terminology.

---

## Style Guide: Do’s & Don’ts

### Do

- Use consistent Material 3 components.
- Use centralized theme tokens.
- Keep primary actions visually obvious.
- Require deliberate confirmation before executing a location request.
- Display request state explicitly.
- Show timestamps for important actions.
- Preserve a clear audit trail.
- Mask sensitive information when full visibility is unnecessary.
- Use icons **and text** for important statuses.
- Provide clear loading, offline, timeout, and failure states.
- Maintain sufficient spacing between consequential actions.
- Test interfaces with larger text settings.

WCAG 2.2 specifies a minimum pointer target size of **24 × 24 CSS pixels** or equivalent spacing; for this application, important mobile controls should preferably be larger than that minimum.

### Don't

- Don't use color alone to communicate status.
- Don't hide the execution action inside a generic menu.
- Don't use vague buttons such as **"Continue"** when the action actually triggers a location request.
- Don't automatically execute a request simply because an IO opened a link.
- Don't expose complete sensitive information unnecessarily.
- Don't put sensitive information into URLs.
- Don't use real target numbers or operational telecom data in mockups.
- Don't display raw responses as ordinary user-facing prose without distinguishing them as evidence/raw data.
- Don't use excessive animations.
- Don't use large decorative graphics that compete with operational information.
- Don't create multiple competing primary buttons.
- Don't hard-code colors throughout Flutter widgets.
- Don't claim the visual system represents official IFSO branding without an approved brand specification.

### MVP Design Rule

For the 10–15 day MVP, build **one coherent visual system**, not a large design system:

1. Central `ColorScheme`
2. Central `TextTheme`
3. Spacing/radius tokens
4. Reusable request card
5. Reusable status badge
6. Reusable confirmation dialog
7. Reusable audit timeline
8. Reusable error/loading states
9. Reusable sensitive-data display/masking component

Flutter explicitly supports centralized `ThemeData`, `ColorScheme`, and `TextTheme`, so this approach maps cleanly onto the planned Flutter implementation.

---

## Design Sources

- Flutter Material 3 documentation and migration guidance.
- W3C WCAG 2.2 accessibility guidance.
