# Wallpapers

Drop your own images into `dark/` and `light/`. The `theme` script and
`hypr-wallpaper` pick a random image from the pool matching the active theme;
`hypr-wallpaper-rotate` cycles them on a timer.

## Time of day

There are four pools, and they form one brightness ladder:

```
dark/  ->  dusk/  ->  dawn/  ->  light/
```

Your theme picks which end you live at. When the sun is near the horizon,
`hypr-wallpaper` moves you one rung towards the middle:

| Sun | `theme light` | `theme dark` |
|---|---|---|
| day | `light/` | `dark/` |
| near the horizon | `dawn/` | `dusk/` |
| night | `light/` | `dark/` |

Which rung is the **theme's** choice, not the clock's: the light theme brightens
into `dawn/` and the dark theme darkens into `dusk/`, at either end of the day.
So a dark desktop at sunrise shows dusk photographs — the ones that sit next to
its night set — rather than the bright ones a sunrise would otherwise imply.
The two middle pools are brightness tiers, not times.

**The theme never changes on its own** — that stays a decision you make. All
that shifts is which images are eligible, and `sun-phase` only decides *whether*
you are on a middle rung at all.

`dark/` and `light/` need no `night/` or `day/` counterpart: they already are
those sets. `dawn/` and `dusk/` are optional, and an empty or missing one falls
straight back to the theme's own pool, so an existing setup keeps working
untouched.

Time comes from the sun's elevation, not the clock — evening is an angle, not an
hour, and fixed times are wrong twice a year and wrong all year at high
latitudes. Location is read from your timezone's entry in tzdata, so there is
nothing to configure and no geolocation service involved; `SANELAND_LAT` /
`SANELAND_LON` override it. Dawn and dusk are the band from −6° to +6°, roughly
an hour at each end at mid latitudes. Since rotation re-evaluates on every tick,
the changeover happens within one interval.

```bash
sun-phase --verbose          # dusk  elevation=+2.31°  lat=40.40 lon=-3.68 …
SANELAND_PHASE=dusk hypr-wallpaper   # force one, for a look
```

No images ship with this repo (they'd be someone else's copyright). The folders
are intentionally empty except for `.gitkeep`.

Any format awww accepts works (JPG, PNG, WebP, animated GIF, …). There's
nothing else to configure — add or remove files and the next rotation picks
them up.

## Starting from empty

An empty pool means a black desktop, so there's a fetcher for the cold start:

```bash
wallpaper-fetch                  # add 10 images to every pool
wallpaper-fetch -n 25            # ask for more
wallpaper-fetch --theme dark     # only the dark theme's pools (dark/, dusk/)
wallpaper-fetch --phase twilight # only dawn/ and dusk/
wallpaper-fetch --phase main     # only dark/ and light/, skip the twilight pools
wallpaper-fetch --dry-run        # report what it would keep, write nothing
```

It pulls freely-licensed nature photography from Wikimedia Commons' curated
Featured/Quality picture categories, renders each at 4K, and writes credits to
`ATTRIBUTION.md` (git-ignored, like the images). Needs ImageMagick.

Two things it does that a plain download loop doesn't:

- **It sorts by measurement, not by category.** Every candidate's luminance is
  measured and *that* decides whether it lands in `dark/` or `light/` — so the
  pool matches the theme it's filling. The thresholds come from measuring a real
  hand-picked pool, which showed the two sets separate cleanly at mean luminance
  ~0.30, and that dark wallpapers tolerate deep shadow but never blown
  highlights (light ones are the mirror image). Override any of them from the
  environment: `DARK_MEAN_MAX=0.35 wallpaper-fetch`.
- **It spreads the results.** Per-run caps stop one colour family or one source
  category from taking over — without the category cap a run comes back as ten
  auroras, which a colour check can't catch because auroras aren't one colour.
- **It won't hand you the same picture twice.** Every image is fingerprinted
  twice (average-hash and difference-hash) and compared against the pool before
  its full size is downloaded. Commons batch uploads are caught separately, by
  collapsing digits out of the filename: `Auroras_1/2/6/7_-_panoramio` is one
  photographer's night, not five wallpapers.

Re-running is safe: files already in the pool are skipped, and each run samples
a different shuffle, so it tops up rather than repeating itself.

**Deleting is how you curate.** Every filename ever fetched is recorded in
`.wallpaper-seen`, so an image you `rm` stays gone instead of returning on the
next run. Some things no automatic filter can recognise — a drilling rig
photographed under the aurora has nothing in its title or its histogram to give
it away — so throwing one out has to be permanent to be useful. Delete
`.wallpaper-seen` to start over.

### Why dark/ is picked differently from light/

Luminance measures *dim*, not *night* — and for a dark desktop theme that
distinction is the whole point. A fern forest under closed canopy, a cave
interior, a waterfall in a shaded gorge all measure comfortably dark while being
unmistakably daytime photographs. A pool built on luminance alone came out half
caves and green woodland.

No pixel statistic reliably tells those apart from a night shot, but the source
category does: whether a photograph was taken at night is a fact about the
photograph, and Commons has already sorted it. So `dark/` draws only from
`NIGHT_CATEGORIES`, and measurement then decides which of those are dark
*enough*. Daylight categories can only ever fill `light/`.

That list leads with night *landscapes* — forests, trees, mountains, lakes,
rivers, beaches, snow — and treats the sky phenomena (aurorae, star trails,
noctilucent clouds, moonlight) as the minority they should be. An astronomy-only
version produced a pool that looked like an observatory gallery: every frame
mostly sky above a sliver of silhouette. A dark wallpaper wants ground in it.

Twilight is the one phase where the pixels get the casting vote, because there
the two pools *are* a brightness split: a low sun genuinely comes in both
weights, and the measurement decides whether a frame belongs to the dark theme's
blue-hour end (`dusk/`) or the light theme's golden one (`dawn/`). Sunrise
versus sunset is the distinction no statistic can make — the same photograph
either way — and nothing here needs it, so both feed one stream.

One category is deliberately absent: "Night photography". It is overwhelmingly
urban and institutional — a run through it returned a city skyline, a floodlit
dog, a roundabout and an armoured vehicle. *Taken at* night is not the same
claim as *of* the night.

### The dark pool runs dry first

Daylight nature photography vastly outnumbers night photography, so `dark/`
exhausts long before `light/` does. A run that asks for twenty of each will
comfortably fill light and warn that dark fell short; that warning means the
candidate list was genuinely used up, not that something failed.

Two levers, in order of preference: re-run later (the shuffle samples
differently and Commons keeps growing), or raise the ceiling —
`DARK_MEAN_MAX=0.34 wallpaper-fetch --theme dark`, which admits dusk and
twilight frames that the default's 0.30 rejects.

### On licensing

The default keeps anything Commons hosts, which is free content by
construction — mostly CC BY-SA. That is not a redistribution risk here, because
nothing is redistributed: the images land in your home directory and are
git-ignored, exactly like ones you'd drop in yourself. `--public-domain`
narrows to the CC0/public-domain subset, which carries no attribution
obligation, if you plan to pass your pool on to someone else.

Be aware of what that flag costs: public domain is a small minority of Commons'
curated photography. The same search that offered 308 candidates on the default
setting offered 18 under `--public-domain`, so ask for fewer images per run and
expect to re-run.

### Where it stops

The subject filter is a heuristic over file titles, and it leaks in both
directions. It reliably rejects buildings, vehicles and people when the title
names them in a language it knows, but a Genoese watchtower titled *"tour
génoise"* gets through, and a file named `170905-N-UY653-014` cannot be judged
at all. Expect to delete the occasional keeper — the pool is just a directory.
