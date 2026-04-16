# Robust Equipment-EX Unlocker

A safer Cyber Engine Tweaks Lua mod for Cyberpunk 2077 that scans clothing records carefully, imports them in small batches, and helps identify problematic clothing items instead of blindly crashing.

## What this version does

- safe batched clothing scan
- safe batched import
- pause and resume support
- persistent queue saving
- saved progress in case the game stops during import
- bad-item logging for easier diagnosis
- blacklist support for clothing IDs that repeatedly fail

## Why it is more robust

The mod saves the current item identifier before each import attempt. If the game hard-crashes on a bad clothing record, the last suspect item is preserved in the saved state and log files so you can blacklist it and resume without starting over.

## Files that matter most

- init.lua starts the CET mod
- src contains the runtime logic
- config/config.json contains the user settings
- config/blacklist.json stores excluded clothing IDs
- config/state.json stores progress and the last suspect item
- logs/bad-items.log records failed or suspicious items

## Basic usage

1. install the folder as a CET mod
2. if you use Native Settings, open the in-game mod settings and look for EQEX Unlocker
3. otherwise open the CET overlay window
4. click Start Safe Scan
5. after the scan completes, click Start Import
6. if failures appear, use Blacklist Failed IDs and resume the import

## Default behavior

The defaults are intentionally conservative:

- manual scan
- manual import
- short scan delay
- slower import delay
- small import batches

That makes it much safer for heavy clothing load orders.

## Current status

This repo now contains a full working starter implementation designed for live in-game testing and iteration.
