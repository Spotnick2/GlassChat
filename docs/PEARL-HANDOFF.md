# GlassChat Pearl — Claude handoff

## Goal and scope

Make GlassChat visually fit the shared Pearl direction while preserving chat readability.
The owner confirmed that all five pills in the reference belong to GlassChat, including the
two above the left column. The selected-tab yellow may change. This branch implements the
in-game candidate; the mockup is a direction, not proof of rendering on Forever.

LibGlass r11 now owns the Pearl recipe. GlassChat selects that preset on its own instance and
adds consumer-specific contrast. GlassUI remains the intended future suite orchestrator;
this branch is independently usable and does not require GlassUI. Do not expand this beta
pass into a new preset manager. The suite's Clean, Classic, Smoked, Clear and Reflective naming
and mapping need a separate decision; they are not all interchangeable LibGlass preset names.

## What changed

| Surface | Behaviour |
| --- | --- |
| Reading area and edit box | Neutral charcoal, default alpha 0.82, no wash or grain over words |
| Tab strip | Independent shell alpha 0.68, subdued edge light, same rounded panel mask |
| Selected tab, menu bubble, copy/search hover | Soft ice blue (`Skin.ACCENT`) |
| All five pill backgrounds | Shared `Skin.PillLook`, Pearl rim and wash, shell alpha |
| Alerts and Spam & Ignore symbols | Existing gold idle / green pending, counts and pulse |
| Native voice and friends symbols | Existing stateful artwork and behaviour |

`.pkgmeta` pins LibGlass r11. `Glass.lua` requests `preset = "pearl"` when the active library
minor is at least 11; an older dev library falls back to its default material to avoid a load
failure, but that fallback is not the intended preview. There are no edits to shared LibGlass.

The main window uses two **adjacent** fills, not layered dark rectangles. The header and reading
area meet at the existing separator and use the same mask. Reading opacity therefore remains
independent even when shell opacity is higher. Stock frame placement and the existing tab lift
are unchanged. The edit box follows reading opacity.

`Buttons.RefreshSides` now reapplies styling and frame levels to already-created custom pills.
Previously those pills retained their creation-time opacity while the standard buttons updated.

## Deploy the candidate

1. Fetch and check out this GlassChat branch in the owner's normal checkout. Preserve unrelated
   local edits. Read `CLAUDE.md` before continuing.
2. Use a clean LibGlass checkout at the **r11 tag**, plus LibAccountSync at the `.pkgmeta` pin.
   Set `LIBGLASS` / `LIBACCOUNTSYNC` to separate checkouts if the sibling repositories contain
   ongoing work. The deploy script prints a pin mismatch; resolve it before comparing visuals.
3. Run `pwsh tests/run.ps1` in the owner's environment, where the API dump is available.
4. Run `pwsh Tools/deploy.ps1 -Probe` to deploy GlassChat, its plugin, and ChatProbe. The probe
   option also needs the existing ForeverProbe checkout. Without the probe, omit `-Probe`.
5. Reload the client. Check the active library and instance with:

   ```lua
   /run local _,v=LibStub:GetLibrary("LibGlass-1.0"); print("LibGlass",v,"GlassChat preset",GlassChat.Glass.preset)
   ```

   Expect minor 11 or newer and `pearl`. Use the exact tagged r11 build for the initial comparison:
   LibStub chooses the newest loaded minor, and two different dev/released copies with the same
   minor can make load order decide the winner. Check other embedded copies if results disagree.

## Compare the proposed defaults

Saved custom `alpha` and `/gchat tune` values are deliberately preserved. Record existing values
with `/gchat` and `/gchat tune` before trying this baseline; `tune reset` clears custom edge values.

```text
/gchat glass on
/gchat alpha 0.82
/gchat shellalpha 0.68
/gchat tune reset
/gchat spam icon on
```

`/gchat alpha` adjusts the reading area and input. `/gchat shellalpha` adjusts the tab strip and
every pill. Both accept 0–1 and update immediately. The Spam icon remains opt-in; restore its
previous setting after comparing if desired. Existing settings sync includes `shellAlpha`.

## In-game acceptance checks

- Capture populated chat over bright terrain and a dark interior at the owner's normal UI scale.
  Include say, guild, party, whispers, system text, class-coloured names and item links. Confirm
  the text remains easy to read while the header and pills retain visible depth.
- Include **all five pills**: menu, channel/voice, friends, alerts and Spam & Ignore. Check their
  rims and contrast, friend/pending counts, tooltips, click actions and the existing stack.
  Check TTS, mute/deafen and connected voice states when available; keep native state colours.
- Change `shellalpha` with the Spam pill visible, hidden and newly enabled. Change reading alpha
  independently. Test 0 and 1 briefly to expose compounded fills or a header/body seam, then
  restore the comparison values. Do the rim and edge still read cleanly at the separator?
- Select several tabs, hover copy/search, focus the input, detach/resize a window and reload.
  Check for clipping, a gap or overlap at the separator, duplicate layers and washed-out text.
- Toggle `/gchat glass off` then `on`. Check stock artwork restoration, pending alert pulses and
  subsequent refreshes. Repeat normal chat/voice use in combat; inspect `/gchat failures` and
  `/fp chat state` with the probe deployed. Watch for blocked-action reports.
- Open Copy, Focus, URLs, alerts and the spam log; these also share the instance and must remain
  readable. No recolouring of actual chat messages is part of this visual pass.

Return screenshots and the active LibGlass minor with any tuning request. Adjust consumer
values here first. If a shared renderer defect remains, file a minimal LibGlass issue with the
active tag, reproduction and screenshot; don't patch the sibling library from this task.

## Validation and limits

Local validation uses the real r11 Lua with the repository's WoW stubs under Lua 5.1. The new
`test_pearl.lua` checks saved settings, separate fills, all five pill opacities, late creation,
repeated refreshes, live commands, settings-sync export and glass toggles. Existing button,
alert and plugin tests cover symbol state, counts and pulse behaviour. Mutation checks verify
that stale custom-pill styling and incorrect header opacity make the new test fail.

The API-dump method check is unavailable in the remote environment. Rendering, taint and actual
combat/voice states require the owner's client. Keep the PR draft until these checks and the
owner-launched review are complete. Do not merge, tag a release or start a review automatically.
