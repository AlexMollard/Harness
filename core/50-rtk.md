# RTK - Rust Token Killer

A Claude Code hook rewrites shell commands through `rtk` (`git status` becomes
`rtk git status`) to cut output tokens. Use `rtk proxy <cmd>` when you need the
raw, unfiltered output; `rtk gain` shows the savings. If `rtk gain` fails, the
wrong `rtk` (Rust Type Kit) is on PATH.
