# VoltTime

iPhone app for Ultra Rouge (Tesla Model 3 LR RWD) charging, built from
[tesla-home-charge-planner](https://github.com/shinichixx/tesla-home-charge-planner) and
[Tesla-M3-Charger-Calculator](https://github.com/shinichixx/Tesla-M3-Charger-Calculator).

Dark, Tesla-app style. Three pages, swiped left and right (no tab bar):

- **My Home** – the "Home IM2 Kuantan" page (was the Tesla dashboard in Home Assistant): scenario photo with live
  Model 3 / Solar / Home / Grid power with animated pulses along the wires (direction = power flow, green = solar,
  yellow = grid, one speed rule for every line and for My Car,
  12 kW = 112 pt/s, half pace below 0.5 kW; solid green cable on DC fast charging), Exporting / Importing / Self-powered, and three rows:
  - Tap the **Model 3** figure – charging current slider (5–32 A) and Start / Stop charging, sent straight to the car.
  - **Energy** – opens on **All** (solar, home, Model 3 and grid lines together, with six numbers below). Tesla-style: Day / Week / Month / Year / Lifetime menu, Choose Date (Day / Month / Year / Custom up to 31 days), Home / Solar / Vehicle / Grid bar at the bottom,
    stacked areas for a day (tap and hold to scrub), bars for longer periods, Energy Flow rows. The eye shows one total in the view's colour, fading to black at 0. Day graphs use
    5, 10, 15, 30-minute or 1-hour steps (My Home › Settings › Energy Graph; older days 15-minute or hourly). Curves come from the same shared store as Impact.
  - **Utility Bill** (All, Home, Vehicle and Grid views; Home and Vehicle show their share by grid energy used, All adds the savings from solar, and the Solar view shows each saving in Energy Flow) – TNB Domestic ToU / NEM 3.0 bill worked out like the real one, with the AFA
    and threshold of each month and public holidays off-peak. Day / Week are shares of the month's bill (estimates),
    Month shows so far and the full-month estimate, Year / Lifetime add the monthly bills. The eye shows the breakdown.
  - **Impact** – Tesla-style cards for Day / Week / Month / Year / Lifetime: Self-Powered, Model 3 on solar (+ km on
    sunshine), CO₂ avoided (0.740 kg/kWh, Peninsular 2024) and Solar Forecast (follows the period: today's curve, a past day's forecast and
    actual bars, longer periods actual bars with forecast marks; touch and hold to read one). Energy is kept on the phone in one
    file (energy.plist, ~280 KB a year: one curve per day, 5-minute for recent days, 15-minute or hourly for older ones) shared with the
    Energy page; each refresh only fetches today, yesterday and anything missing.
  - Energy and Impact always open on **Day / Today** from My Home. Tapping the house photo opens Energy too:
    car → Vehicle (only when the photo shows the car), solar roofs → Solar, windows → Home, grid wire → Grid.
  - **Settings** – *Utility Rate Plan* (TNB ToU import / export rates from each month's AFA, rate components)
    and *Vehicle Charging*: *Charging mode* (Off / Routine / Excess Solar / Fast, sets `input_select.tesla_charging_mode`;
    the HA "Tesla Charging – Controller" automation still does the work), *Charging start time* (Routine only:
    location tomorrow GPS 73% / TSET 63% / Others, ready time, start time) → *Charge details* (duration, energy,
    safety buffer, start %, cost, charger and battery parameters), and the Home Assistant connection
    (home Wi-Fi address first, Tailscale when it does not answer; Menu › Connection shows which one is in use).
  The 9 scenario photos are built in (`Sources/Photos`, JPEG at iPhone width, ~1 MB total).
- **Ultra Rouge** (the car, straight from Tessie – not through Home Assistant) – two layouts, switched in
  Settings → Car → Layout:
  - *View 1* – script title, car photo pinned behind the page (dims to 18% as you scroll), 100-tick battery ring with a
    draggable charge limit (centre fades to the limit and its range), 6 customisable buttons, Temperature | Tyres
    (top-down car at real Model 3 proportions), Security | Battery health (10 cells, max range, capacity, cycles ≈
    lifetime energy ÷ capacity), location, odometer, version and release date.
  - *View 2* – list style like the rest of VoltTime: charging panel (limit slider, amps, start/stop, charge port),
    5 buttons, rows for Controls, Climate, Tyres, Battery, Security, Location, Charging plan and Odometer.
  Settings → Car: Tessie token (Keychain) and car, Layout, Car photo (your photo with the background lifted on the
  iPhone, edge fade, brightness, size, optional plate blur; included in iCloud backups), Quick controls (every Tessie
  command that makes sense as a button, ask-first per button), Autogate (one RF pulse on
  `switch.porch_rf_controller_switch_1` through Home Assistant).
- **Simulation** – *Home charging* (when to start for any % by any time) and *Public charging* (Supercharger / DC
  time and cost). Nothing is sent to the car or Home Assistant.

`homeassistant/volttime.yaml` is the Home Assistant package: at 7pm it quietly plans the night; it asks "Where are you
going tomorrow?" (Time Sensitive, GPS / TSET work from the lock screen) at the reminder times set in VoltTime
(Charge details → Reminders) only while the car is plugged in at home and unanswered, and when you plug in after 7pm;
sets the limit and writes a one-time Tesla charge schedule through Tessie. When VoltTime is open on an unanswered
charging night it shows the same question as a centre card.

Every push to `main` builds an unsigned `VoltTime_buildN.ipa` and attaches it to a GitHub Release (bump
`CURRENT_PROJECT_VERSION` in `project.yml` for a new build number).
