Mise (shared edition) 0.6.2 - everything in its place before you play
(mise = short for 'mise en place', a chef's habit: everything in its place before service starts.)

INSTALL
1. Double-click INSTALL.cmd. Mise starts in the tray (near the clock) and adds a desktop icon.
2. First run: each screen lights up with a copper frame - give it a name. A short intro follows.
3. Updating from 0.5: your screens, settings and League accounts stay. Old routines are not carried over
   (routines are built differently now); a copy of the old settings file is kept as config-v3.json.

MAKE A ROUTINE (the card in an empty Mise window, or Routines)
1. Open your apps and put them roughly where you want them.
2. Press Copy my screen. Tick the windows that belong to the routine and choose Close or Leave for when
   you exit (Close all / Leave all at the top). Browser windows ask for their address.
3. Mise puts them on a map of your screens and tidies them: small gaps closed, small overlaps removed.
4. Fine-tune on the map:
   - drag a tile to move it; it sticks to the screen edges and to other tiles
   - drag a tile's edge to resize it; it stops at the smallest size the app allows
   - drag the line two tiles share to resize both
   - Layout (above each screen): full, halves, thirds, 40/30/30
   - Taskbar (above each screen): hide it on that screen while the routine runs
   - Ctrl+Z undoes, Delete removes the selected tile
5. Preview on screen moves your open windows to the layout once. Test run starts the routine (League with
   the current login) and marks every tile Passed, Late or Failed. Save checks every app is still installed.
+ Add app adds a tile from the list of installed apps, or a web page.

SPECIAL TILES
- Web page: Clean window = no address bar, tabs or bookmarks. Uses your default browser
  (Chrome, Brave, Opera or Vivaldi). Firefox opens normal windows. Mise doesn't use Edge: with Edge as
  your default it uses another installed browser.
- u.gg: the u.gg tile only marks where the page goes. It opens when you pick a champion.
- Spotify: Mini player puts the small player in that spot (open it once in Spotify first).
- League client: position only, its size is set in League.
- Mise pop-up: where the small progress pop-up shows while the routine runs.

ROUTINE SETTINGS
- Log in to League: starting the routine asks which account, then logs in, starts the client and your lobby
  first, and arranges everything else while League loads.
- Hotkey: click it and press your keys (Ctrl or Alt plus a letter, digit or F-key).

THE MISE WINDOW (desktop icon, or tray > Open Mise)
- Routines: one click starts one. Mise steps away and a small pop-up shows the progress.
- League accounts: one click logs in to that account, or switches if another one is open. Nothing else.
  Right-click an account to update its saved login or remove it.
- Tools: Arrange (put the windows back), Routines (the builder), + Account.
- Options: auto-accept, lobby after login (click to go to the next one), u.gg page for your champion.
- The gear: look, pop-up corner, window spot, updates, Fix League client, Reset Mise, About.

TRAY (left- or right-click the icon)
Open Mise, Reset Mise, Forget everything (start over: shows the first-time setup again), your routines, Switch to (accounts), exit a routine, the League helpers, Edit routines, Quit.

LEAGUE
- Saved logins live in %USERPROFILE%\LeagueAccounts and never contain passwords. Keep that folder private.
- Do not sign out of Riot Client between accounts: signing out cancels the saved login.
- If a lobby does not open, Mise tests every lobby type once, remembers which ones work today and enters the best one.
- If a saved login is rejected, Mise stops: log in by hand, then right-click the account > Update saved login.

UPDATES
Mise checks GitHub (codefecta/Mise) once a day and offers the update in the tray. Settings > Updates checks right now.

Your routines and settings live in %APPDATA%\Mise\config.json and are kept when you update or uninstall.
UNINSTALL.cmd removes Mise (not your routines or saved logins).
