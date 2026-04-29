# Usage guide

## In game flow

1. Open Native Settings and look for EQEX Unlocker if you have that mod installed.
2. If not, open the Cyber Engine Tweaks overlay.
3. Use Start Scan.
4. Wait for the queued item count to finish building.
5. Use Start Import.
6. If needed, use Re-add All to queue all eligible clothing again, including already unlocked/imported items.
7. If the import pauses or the game crashes, reopen the game and check the last suspect item shown in the overlay or in the saved state file.
8. Use Blacklist Failed IDs, then resume the import.

## Smart import

- Enable Smart import in Native Settings or in the CET Settings tab.
- Set Smart import minimum FPS to your target floor.
- During import, the mod adjusts work rate automatically:
- lower throughput when FPS drops below target
- gradually increase throughput when there is headroom

## HUD and status telemetry

- Scan elapsed time and scan ETA.
- Import elapsed time and import ETA.
- Smart import readout with current FPS, target FPS, and current speed percentage.

## Files for diagnosis

- config/state.json stores the last item index and last suspect item id
- config/blacklist.json stores skipped clothing ids
- logs/bad-items.log stores the recorded failures

## Safer tuning

For very large clothing collections, keep import delay conservative and batch size low, then use Smart import minimum FPS to tune stability.
