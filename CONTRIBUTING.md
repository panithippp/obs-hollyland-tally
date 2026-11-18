# Contributing

Thanks for your interest in improving this OBS Studio script for Hollyland wireless tally lights.

## Report an issue

Please open an issue on GitHub and include:

- **OBS Studio version**
- **Operating system** (Windows or macOS, and the version if you know it)
- **Hollyland base firmware** (the tested base is firmware S4.0.0.10, HW H000 — please include yours)
- **Script log:** in OBS, open **Tools → Scripts → Script Log** and copy the `[Tally]` lines
- If the problem was during install, also attach the installer log:
  - Windows: `%TEMP%\hollyland_tally_install.log`
  - macOS: `~/Library/Logs/hollyland_tally_install.log`
- What you expected, what happened, and how the tally lights and the status window looked

## Pull requests

- Keep changes focused and describe what you tested.
- Do not break existing light mapping or installer behaviour without a clear reason.
- Follow the current code style of the file you edit.

## Testing on real hardware

Please test on a real Hollyland tally base and lights when the change touches tally colours, the vMix TCP API on port 8099, LAN discovery, the status window, or the Windows/macOS installers. If you cannot test on hardware, say so in the pull request and describe what you did test (for example the pure-logic functions in `obs_hollyland_tally.py`, which work without `obspython`).

## License

By contributing, you agree that your changes are licensed under the [MIT License](LICENSE).
