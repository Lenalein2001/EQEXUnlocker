# Usage guide

## In game flow

1. Open Native Settings and look for EQEX Unlocker if you have that mod installed.
2. If not, open the Cyber Engine Tweaks overlay.
3. Use Start Safe Scan.
4. Wait for the queued item count to finish building.
5. Use Start Import.
6. If the import pauses or the game crashes, reopen the game and check the last suspect item shown in the overlay or in the saved state file.
7. Use Blacklist Failed IDs, then resume the import.

## Files for diagnosis

- config/state.json stores the last item index and last suspect item id
- config/blacklist.json stores skipped clothing ids
- logs/bad-items.log stores the recorded failures

## Safer tuning

For very large clothing collections, keep the import delay above 0.25 and the batch size low.
