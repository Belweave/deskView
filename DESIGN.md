# deskView() design

## Direction

A native Mac studio seen at blue hour: deep ink work surface, cool translucent Liquid Glass controls, clear white type, and a warm red record action. The user pinned SwiftUI and Liquid Glass. The camera content owns the visual attention. The interface is an operating surface, with standard Mac buttons, pickers, sliders, menus, keyboard shortcuts and resizable windows.

## Visual decisions

- System typography; SF Pro for controls and SF Mono only for timing, dimensions and frame rate.
- Ink canvas #101923, blue charcoal shell #192532, cool secondary type #A8BACB, ice accent #97D9EC, recording #FF635D.
- Use real `.glassEffect` on grouped floating controls; native material for the sidebar. Do not stack decorative glass cards.
- 8-point spacing rhythm, 20-point workspace gutters, 12-point grouped-control radius. Camera canvas scales at a fixed output aspect ratio.
- A single dominant composed preview; source setup to the left and framing to the right, subject to mockup approval.
- Recording states have text and an icon as well as color. Focus, disabled, unavailable, denied permission, disconnected input and saving states all remain explicit.
- Use system motion, respect Reduce Motion, and keep live previews steady while recording.

## Grounded directions considered

Contact-print margin; photographic monograph; museum caption system; blue enamel wayfinding; cinema intermission card; frosted projection booth; blue-hour drawing studio (assigned candidate 7). The last contributes the cool ink palette, precise type and a glass control shelf beneath an unbroken image.

## Challenger judgment

The graphite working surface is competitive for clarity but loses the committed cool palette; retain its quiet seams. The acetate manual loses identification and clarity; retain its text hierarchy. The catalog wall loses recording clarity; retain its disciplined aspect ratios. Transit mapping loses native familiarity; retain clear source-to-output relationships. The cassette inlay loses legibility and clarity; retain aligned duration figures. The type specimen loses source visibility; retain direct slider feedback. These raise the native studio without changing its navigation or controls.

## Imagery

Generated imagery appears only in design mockups, clearly labeled as illustrative. Production previews show actual capture frames. The optional demo uses an explicitly labeled generated test chart, never a simulated live camera. Symbols come from SF Symbols.

## Verification

Build locally on Apple Silicon. Inspect the complete window at its default and minimum sizes, both missing-device and demo states. Verify keyboard focus, contrast, recording state, source selection and the clean output window.
