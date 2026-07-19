# PetTips

**What can your pet learn — right now, later, and from which beast?**

PetTips is a hunter addon for WoW Classic Era / Hardcore that merges BOTH
ways of learning pet abilities — **pet trainers** (for money) and **taming
wild beasts** (learn the skill, teach it to every future pet) — into one
WhatsTraining-style list inside your spellbook, and tells you exactly
which mobs to tame for the rest.

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
the first sync the list says so honestly instead of guessing.

## Configuration

Settings -> Options -> AddOns -> PetTips, or simply `/pettips`:

- **Enable training list** — the spellbook tab and list.
- **Show abilities known by pet** — the gray reference section.
- **Show abilities of other pet families** — the planning section.
- **Show missing-ranks panel at Beast Training** — docks a "what's still
  missing" panel to the trainer window (default off).
- **Beast tooltips** — the teach-lines on enemy beasts.
- **Teaching mobs listed per ability** — 3-25 tooltip lines before
  "+N more" (in-zone mobs are never hidden by the cap).

## Data & compatibility

- Complete Classic Era catalogue: **21 abilities, 111 ranks, 297 teaching
  beasts**, with training point costs, pet level requirements and trainer
  prices — compiled from the game client's own data, Petopia and the
  original 1.12 trainer lists, cross-checked against each other.
- Plays nice with **WhatsTraining**: the tabs share the spellbook edge
  without overlapping, and opening one view closes the other.
- Hunter-only by design — completely inert on other classes.
- Ability and family matching is ID-based and works on every client
  language; mob and zone names are currently English (the in-zone
  highlight needs an English client).

## Limitations & Roadmap

- **Zone names are English** for now — planned fix: map-ID based matching,
  which is also the groundwork for showing tame targets on the world map.
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
