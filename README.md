# pureglass

Liquid Glass for the Spotify iOS app below iOS 26: the glass tab bar, the now playing card, the round
header buttons, the sheets (queue, ⋯ menu, Connect, Create, sleep timer, artist credits), and the playlist,
album, artist, library, search and home pages dressed to match. From iOS 26 it does nothing, the system's
own glass is used there. Below it the glass is off until **Glass UI** is switched on. The switch is the row at the top of
Spotify's own Settings page (key `pureglass.legacyGlass`), added by this tweak alone; restart Spotify
after flipping it. If the row does not show, `make log` lists the pages taken for Settings.

Below iOS 26 the glass is `PGLegacyGlassView`, a `CABackdropLayer` blurred, saturated and displaced by a
mesh (geometry and filter values ported from Telegram-iOS, GPLv2). It uses private API; where the device
does not have it the panes fall back to a plain dark blur.

It is a tweak of its own and can be injected next to another one in the same IPA: its dylib is
`pureglass.dylib`, every class, symbol and preference key starts with `PG`/`pureglass` and none is shared.
With Glass UI on, this tweak is the only one that keeps a tab bar: if spoti.pw's Redesigned UI is on
too, its glass tab bar is taken out of the row (`dropForeignBar` in `TabBar.x`). Its other redesigned
screens are no longer drawn twice either: with Glass UI on, spoti.pw's views that this tweak has a class of its
own for (`SGRHeaderInfo`, `SGRMirrorButton`, `SGRArtworkField`...) and its glass panes laid over this tweak's
are concealed (`Redesigned/Kit/PGRForeign.x`), except on the player screen.

## Build

```sh
make release            # IPA without FLEX from ipa/*.ipa (or IPA=path.ipa) -> out/pureglass-<version>.ipa
make build              # same, but with FLEX injected too (for debugging)
make install            # release build (no FLEX), signed with .signing.env and pushed to the phone on USB; FLEX=1 to include FLEX
make log                # the tweak's log lines from the phone
```

Needs Theos, an Xcode with the iPhoneOS 26 SDK, `gmake`, `ldid`, `dpkg-deb` and `cyan`
(see `scripts/pipeline.sh`). The IPA may already carry other tweaks; this one is added beside them.

`harness/tabbar` is a simulator app that runs the tab bar and now playing bar alone (`build.sh`).

## License

Derived from spoti.pw; its LICENSE (PolyForm Strict 1.0.0) is kept as it was. `Core/PGLegacyGlass.m`
ports geometry from Telegram-iOS (GPLv2).
