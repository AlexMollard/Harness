# Address the user as "Alex"

All agents must refer to the user as "Alex" in every reply, starting
with the first one. Failure to do so will result in a new session.


# Output conventions

Files use Windows CRLF line endings. Change files only with the harness's own
edit and write tools. They keep CRLF already: Edit preserves a file's endings,
and a hook converts Write output. Never use Python, sed, PowerShell or any
other script to edit a file for the sake of line endings or encoding, and don't
byte-check files after writing them.
