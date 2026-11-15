# VoltTime

iPhone app for Ultra Rouge (Tesla Model 3 LR RWD) charging, built from
[tesla-home-charge-planner](https://github.com/shinichixx/tesla-home-charge-planner) and
[Tesla-M3-Charger-Calculator](https://github.com/shinichixx/Tesla-M3-Charger-Calculator).

Dark, Tesla-app style. Two pages, swiped left and right (no tab bar):

- **My Home** – the "Home IM2 Kuantan" page (was the Tesla dashboard in Home Assistant): scenario photo with live
  Model 3 / Solar / Home / Grid power, Exporting / Importing / Self-powered, and three rows:
  - Tap the **Model 3** figure – charging current slider (5–32 A) and Start / Stop charging, sent straight to the car.
  - **Energy** – Tesla-style: Day / Week / Month / Year / Lifetime menu, Home / Solar / Vehicle / Grid bar at the bottom,
    stacked areas for a day (tap and hold to scrub), bars for longer periods, Energy Flow rows. Past days' 15-minute
    curves are kept on the phone (~2–3 KB a day).
  - **Impact** – Tesla-style cards for Day / Week / Month / Year / Lifetime: Self-Powered, Model 3 on solar (+ km on
    sunshine), CO₂ avoided (0.740 kg/kWh, Peninsular 2024) and tomorrow's solar forecast. Daily summaries from HA
    long-term statistics are kept on the phone (~20 KB a year); each refresh only re-reads the last day or two.
  - **Settings** – *Charging mode* (Off / Routine / Excess Solar / Fast, sets `input_select.tesla_charging_mode`;
    the HA "Tesla Charging – Controller" automation still does the work), *Charging start time* (Routine only:
    location tomorrow GPS 73% / TSET 63% / Others, ready time, start time) → *Charge details* (duration, energy,
    safety buffer, start %, cost, charger and battery parameters), and the Home Assistant connection.
  The 9 scenario photos are built in (`Sources/Photos`, JPEG at iPhone width, ~1 MB total).
- **Simulation** – *Home charging* (when to start for any % by any time) and *Public charging* (Supercharger / DC
  time and cost). Nothing is sent to the car or Home Assistant.

`homeassistant/volttime.yaml` is the Home Assistant package that asks "Where are you going tomorrow?" at plug-in,
sets the limit, and writes a one-time Tesla charge schedule through Tessie.

Every push to `main` builds an unsigned `VoltTime_buildN.ipa` and attaches it to a GitHub Release (bump
`CURRENT_PROJECT_VERSION` in `project.yml` for a new build number).
