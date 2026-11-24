# Changelog

## v1.5.0 (2026-11-24)

- **WoW: Forever support** (client 1.60.1): the addon now loads on
  Forever with its own data set, read straight from the Forever client
  data - 18 pet families including the new **Fox**, 31 abilities / 153
  ranks with the new family specials (Web, Swipe, Dismember, Pinch,
  Savage Rend, Dust Cloud, Tendon Rip, Mine!, Trickster's Dance,
  Thunderstomp rank 4, and the bats' **Sonic Blast**) and the Forever
  changes to old abilities (Dash on more families, Screech only on
  carrion birds). Pet trainer prices are the ones charged on Forever.
- The training list lives inside Forever's new spellbook: a PetTips tab
  sits next to the spellbook's own tabs at the top, and the list opens on
  the book page (`/pettips show` jumps to it). Beast Training is read
  from the trainer window it now opens in.
- The Forever list is drawn like the book itself (same style as the
  reworked What's Training): ink on parchment under the book's own page
  header, colored section bands, icon rows with rank, TP or price and
  level columns. Search and settings sit where the book's own are, and the
  settings menu has the taming/trainer filters, "Known by pet" and the
  ability filter. A maximized book uses both pages and flips with the
  book's page buttons or the mouse wheel. With What's Training installed,
  both tabs sit side by side and only one list is open at a time.
- Which beast teaches which rank: 468 beasts, with the new Forever zones
  (Riverglades, Mount Hyjal, Zephras Isle, Moonglade, the new dungeons).
  172 of them are confirmed in game: reports from the beta and the live
  servers up to November 22, among them sources of every new family
  special up to rank 4 or 5. The others come from Petopia's Forever list
  and keep a gray **?** on each rank until someone confirms them. Only
  four ranks still have no known beast: Dismember 5, Sonic Blast 5,
  Thunderstomp 4 and Web 5.
- **Tame collector** (Forever): every beast you tame is recorded with the
  ranks it knows, compared with the list (matches / new source /
  differs) and used for your tooltips and list right away.
  `/pettips tamelog` shows what was recorded. The beast is identified by
  the target you tamed, never by the pet (on Forever every pet shares one
  generic creature ID).
- Classic Era and TBC Anniversary are unchanged.

## v1.4.0 (2026-08-16)

- Russian (ruRU) translation: the training list, the missing-ranks
  panel, beast and grimoire tooltips, the chat messages and the whole
  options panel now speak Russian.
- Wording follows the Russian client — «Дрессировка», «очки обучения»,
  «дрессировщик», «наставник демонов», «гримуар».

## v1.3.0 (2026-07-24)

- Beast tooltips now show the pet family's combat classification
  (Offense / Defense / General) and its S/A/B/C tier grade, colored
  like the reference tier lists.
- The line appears on every wild beast of a known pet family — not just
  ability-teaching mobs — and on hunter pets, both yours and other
  players'.
- New option: "Show family type and tier".
- Translated for deDE, frFR, esES/esMX and ptBR.

## v1.2.2 (2026-07-24)

- Maintenance release: release notes now come from a curated changelog
  instead of raw commit output. No in-game changes.

## v1.2.1 (2026-07-22)

- Bumped Interface to 11509 for Classic Era 1.15.9.

## v1.2.0 (2026-07-21)

- TBC Anniversary support.
- Added the CurseForge project ID to the TOC.

## v1.1.1 (2026-07-21)

- Documentation: family selector, first-run sync button.
- Internal: headless test suite (36 tests).

## v1.1.0 (2026-07-21)

- Warlock demon training support.

## v1.0.4 (2026-07-20)

- Localized mob names and UI translations.

## v1.0.3 (2026-07-20)

- Locale-safe zone matching and localized zone names.

## v1.0.2 (2026-07-20)

- Ability filter popup and family selector.

## v1.0.1 (2026-07-20)

- Version bump.

## v1.0.0 (2026-07-20)

- Initial release: hunter pet training overview for Classic Era.
