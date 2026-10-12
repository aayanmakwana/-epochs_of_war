# Build brief: shared by every build phase

## The owner's request
The owner uploaded `v1_game_design.md` (in this folder) and, when asked, said:
- "Build the whole game, all 20 steps"
- GitHub: "Yes, push to main". The repo is https://github.com/aayanmakwana/-epochs_of_war.git
- Godot: "Download a portable Godot 4.x into the project folder"
- Project location: C:\Users\mkw20\Projects\epochs_of_war

The design doc is the spec. Follow its Build Order, Git Workflow and Technical Constraints.

## Environment facts (checked by the orchestrator)
- Windows. Git is at C:\Program Files\Git\cmd\git.exe. Godot was NOT installed.
- Project root: C:\Users\mkw20\Projects\epochs_of_war (contains v1_game_design.md and this brief).
- Godot binary goes in `C:\Users\mkw20\Projects\epochs_of_war\tools\godot\`, and `tools/` goes in .gitignore. Never commit the binary.
- The doc says Godot 4.7. If no 4.7 stable build exists on the official GitHub releases, use the newest 4.x stable build and write the version you used in README.md. Set config/features in project.godot to match the binary you actually use.

## Rules for every phase
- Before you start, read `PROGRESS.md` in the project root if it exists. It lists the steps already done and any known issues.
- Test every step by running the Godot binary headless, for example `godot --headless --path . --quit-after 120`, plus headless test scripts in a `tests/` folder (`godot --headless --path . -s tests/<name>.gd`). A step counts as done only when the project loads with no script/parse errors and its test passes. Fix what you break.
- Commit after each build step with the message `Step X: <description>`, and push to `origin main`.
- If a push fails because of authentication, keep committing locally, carry on with the build, and record the exact error in PROGRESS.md and in your final reply. Do not try to work around credentials, and never write a token into any file.
- Keep README.md current: title, description, how to run (including the path to the Godot binary), and development status.
- At the end of your phase, update PROGRESS.md: which steps are done, what each test checks, known bugs, and anything the next phase needs to know (architecture, autoloads, signal names, file layout). Commit and push it.
- Your final reply: the steps you completed, test results, the commit hashes, whether each push succeeded, and open issues.
