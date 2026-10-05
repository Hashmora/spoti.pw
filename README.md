# pureglass

Liquid Glass for the Spotify iOS app below iOS 26: the glass tab bar, the now playing card, the round
header buttons, the sheets (queue, ⋯ menu, Connect, Create, sleep timer, artist credits), and the playlist,
album, artist, library, search and home pages dressed to match. From iOS 26 it does nothing, the system's
own glass is used there. Below it the glass is off until **Legacy Glass** is switched on. The switch is a row this tweak adds
to spoti.pw's Mod Settings > Appearance, under Redesigned UI (key `pureglass.legacyGlass`); restart Spotify
after flipping it.

Below iOS 26 the glass is `PGLegacyGlassView`, a `CABackdropLayer` blurred, saturated and displaced by a
mesh (geometry and filter values ported from Telegram-iOS, GPLv2). It uses private API; where the device
does not have it the panes fall back to a plain dark blur.

It is a tweak of its own and can be injected next to another one in the same IPA: its dylib is
`pureglass.dylib`, every class, symbol and preference key starts with `PG`/`pureglass` and none is shared.
With Legacy Glass on, this tweak is the only one that keeps a tab bar: if spoti.pw's Redesigned UI is on
too, its glass tab bar is taken out of the row (`dropForeignBar` in `TabBar.x`). Its other redesigned
screens are still restyled by both.

## Build

```sh
make release            # IPA from ipa/*.ipa (or IPA=path.ipa) -> out/pureglass-<version>.ipa
make install            # the same, signed with .signing.env and pushed to the phone on USB
make log                # the tweak's log lines from the phone
```

Needs Theos, an Xcode with the iPhoneOS 26 SDK, `gmake`, `ldid`, `dpkg-deb` and `cyan`
(see `scripts/pipeline.sh`). The IPA may already carry other tweaks; this one is added beside them.

`harness/tabbar` is a simulator app that runs the tab bar and now playing bar alone (`build.sh`).

## License

Derived from spoti.pw; its LICENSE (PolyForm Strict 1.0.0) is kept as it was. `Core/PGLegacyGlass.m`
ports geometry from Telegram-iOS (GPLv2).
