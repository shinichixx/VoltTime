# VoltTime

iPhone app for Ultra Rouge (Tesla Model 3 LR RWD) charging, built from
[tesla-home-charge-planner](https://github.com/shinichixx/tesla-home-charge-planner) and
[Tesla-M3-Charger-Calculator](https://github.com/shinichixx/Tesla-M3-Charger-Calculator).

- **Home** – night charge planner. Reads battery and charge limit from Home Assistant, quick GPS 73% / TSET 63% / Others limits,
  shows the start time Home Assistant scheduled in the car.
- **Simulate** (section on Home, opens its own page) – what-if calculator: pick a start %, a target % and a leave time to see when charging would have to start.
  Nothing is sent to the car or Home Assistant.
- **Public** – Supercharger / public DC charger time and cost.

`homeassistant/volttime.yaml` is the Home Assistant package that asks "Where are you going tomorrow?" at plug-in,
sets the limit, and writes a one-time Tesla charge schedule through Tessie.

Every push to `main` builds an unsigned `VoltTime_buildN.ipa` and attaches it to a GitHub Release (bump
`CURRENT_PROJECT_VERSION` in `project.yml` for a new build number).
