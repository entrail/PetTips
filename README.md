# PetTips

**What can your pet learn — right now, later, and from which beast (or
grimoire)?**

PetTips is a hunter **and warlock** addon for WoW Classic Era / Hardcore.

For **hunters** it merges BOTH ways of learning pet abilities — **pet
trainers** (for money) and **taming wild beasts** (learn the skill, teach
it to every future pet) — into one WhatsTraining-style list inside your
spellbook, and tells you exactly which mobs to tame for the rest.

For **warlocks** the same list covers your demons: every **grimoire** your
Imp, Voidwalker, Succubus and Felhunter can learn, with price and required
level, plus tooltip hints on the grimoires themselves so you never buy a
rank your demon already knows.

## The training list

A tab on the spellbook (right edge, in the Spellbook AND the Pet view —
also with no pet out) opens a dark, searchable list of every ability rank
for your current pet, grouped by what is actionable:

- **Available now** — you know it, your pet meets the level, the points
  are there. The highest affordable rank per ability, no bait entries
  that a better rank would replace.
- **From your current pet** — your freshly tamed pet knows a rank YOU
  don't: let it use the ability and you learn to teach it. Never lose
  track of why you tamed that boar.
- **Needs pet level / points** — known, but the pet has to catch up.
- **Not learned by you yet** — tagged **(trainer)** or **(taming)** so you
  always know your errand.
- **Known by pet** and an optional **Other pet families** planning section
  (what to tame for FUTURE pets, with "usable by" info) round it off.

Every row shows **"5 TP | Level 8"**, color-coded: white when your pet
qualifies, orange while only you do, red when neither. Filter buttons
narrow the list to taming or trainer sources; the search box filters by
name.

## Warlocks: demon training

On a warlock the same tab lists your demons' abilities instead. Classic
demon trainers are **vendors** — every trainable rank is a grimoire item —
so the sections become:

- **Available now** — the highest rank per ability you can buy at your
  level (lower ranks a better one would replace are skipped — no wasted
  gold), with the grimoire price, red while you can't afford it. A total
  ("Grimoires to buy") shows what the next trainer visit costs.
- **Needs your level** — everything later, tagged **(grimoire)** or
  **(with the demon)** for the ranks a demon simply comes with.
- **Known by pet** — what the demon already knows.

The family selector browses your other demons; rank tooltips name the
exact grimoire and price. And when you hover a grimoire anywhere — at the
demon trainer, in your bags, in chat links — PetTips says whether your
demon **already knows** that rank (green), **still needs** it (red), or
has a **higher rank** already (gray).

## Which mob teaches this?

Hover any taming rank — in the list or the optional Beast Training side
panel — and the tooltip lists the tameable beasts that know it, with zone
and level range. **Mobs in the zone you are standing in are green and
always sorted to the top.** Trainer ranks show their exact gold cost
instead.

## Beasts tell you what they teach

The tooltip of every tameable beast that knows a trainable ability lists
it directly: **green** if you already know how to teach it, **red** if it
is new — one glance answers "is this tame worth it?".

## Always in sync

What you can already teach is read from the game itself: opening Beast
Training (or a pet trainer) syncs the addon's cache, and skills learned
from a tamed pet are picked up the moment the game announces them. Until
the first sync the list says so honestly instead of guessing. On a
warlock, each demon's known ranks are recorded while it is summoned — so
summon a demon once and the addon remembers its books forever.

## Configuration

Settings -> Options -> AddOns -> PetTips, or simply `/pettips`:

- **Enable training list** — the spellbook tab and list.
- **Show abilities known by pet** — the gray reference section.
- **Show abilities of other pet families** — the planning section.
- **Show missing-ranks panel at Beast Training** — docks a "what's still
  missing" panel to the trainer window (default off).
- **Beast tooltips** — the teach-lines on enemy beasts.
- **Grimoire tooltip hints** — the known/missing lines on grimoire items
  (warlock).
- **Teaching mobs listed per ability** — 3-25 tooltip lines before
  "+N more" (in-zone mobs are never hidden by the cap).

## Data & compatibility

- Complete Classic Era catalogue: **21 hunter abilities, 111 ranks, 297
  teaching beasts** plus **16 demon abilities, 63 ranks, 59 grimoires**,
  with training point costs, level requirements and prices — compiled
  from the game client's own data, Petopia and the original 1.12 trainer
  lists, cross-checked against each other.
- Plays nice with **WhatsTraining**: the tabs share the spellbook edge
  without overlapping, and opening one view closes the other.
- Hunter- and warlock-only by design — completely inert on other classes.
- Ability, family and zone matching is ID-based and works on every client
  language — zone names display localized and the in-zone highlight works
  on all locales. Mob names are localized live from the game server and
  remembered; until a name's first reply arrives it shows in English.

## Limitations & Roadmap

- The addon's own labels and messages are translated for **German,
  French, Spanish (EU and Latin America) and Brazilian Portuguese**;
  other locales see English. Corrections from native speakers are very
  welcome!
- **Clickable mob browser** (a window per ability instead of the tooltip
  list) is planned; the data is already in place.
- **TBC support** is prepared in the data layout but not built yet.
- The Beast Training window only reveals ranks for your current pet's
  family, so the known-ranks cache completes over a few visits with
  different pets — everything else self-corrects as you play.

Found a mob that doesn't teach what we claim, or a missing beast? Please
report it with the mob and ability — the data is generated and easy to
fix.

---

Enjoying PetTips? You can support development on
[PayPal](https://paypal.me/adrianh91) — never expected, always
appreciated.
