# VoltTime

iPhone app for Ultra Rouge (Tesla Model 3 LR RWD) charging, built from
[tesla-home-charge-planner](https://github.com/shinichixx/tesla-home-charge-planner) and
[Tesla-M3-Charger-Calculator](https://github.com/shinichixx/Tesla-M3-Charger-Calculator).

- **My Home** – the "Home IM2 Kuantan" page (was the Tesla dashboard in Home Assistant): scenario photo with live
  Model 3 / Solar / Home / Grid power, Exporting / Importing / Self-powered, Energy (today's power chart and totals),
  Impact (self-powered %), and Settings with the charging modes Off / Routine / Excess Solar / Fast
  (sets `input_select.tesla_charging_mode`; the HA "Tesla Charging – Controller" automation still does the work).
  The 9 photos are downloaded once from `/config/www/tesla_home_scenario1-9.png` and kept on the phone.
- **Home** – night charge planner. Reads battery and charge limit from Home Assistant, quick GPS 73% / TSET 63% / Others limits,
  shows the start time Home Assistant scheduled in the car.
- **Simulate** (section on Home, opens its own page) – what-if calculator: pick a start %, a target % and a leave time to see when charging would have to start.
  Nothing is sent to the car or Home Assistant.
- **Public** – Supercharger / public DC charger time and cost.

`homeassistant/volttime.yaml` is the Home Assistant package that asks "Where are you going tomorrow?" at plug-in,
sets the limit, and writes a one-time Tesla charge schedule through Tessie.

Every push to `main` builds an unsigned `VoltTime_buildN.ipa` and attaches it to a GitHub Release (bump
`CURRENT_PROJECT_VERSION` in `project.yml` for a new build number).
