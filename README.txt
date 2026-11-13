Mise (shared edition) 0.7.0 - everything in its place before you play
(mise = short for 'mise en place', a chef's habit: everything in its place before service starts.)

INSTALL
1. Double-click INSTALL.cmd. Mise starts in the tray (near the clock) and adds a desktop icon.
2. First run: each screen lights up with a copper frame - give it a name. A short intro follows.
3. Updating from 0.5: your screens, settings and League accounts stay. Old routines are not carried over
   (routines are built differently now); a copy of the old settings file is kept as config-v3.json.

MAKE A ROUTINE (the card in an empty Mise window, or Edit routines)
1. Open your apps and put them roughly where you want them.
2. Press Copy my screen. Tick the windows that belong to the routine and choose Closes or Stays open for when
   you exit. Browser windows ask for their address.
3. Mise puts them on a map of your screens and tidies them: small gaps closed, small overlaps removed.
4. Fine-tune on the map:
   - drag a tile to move it; it sticks to the screen edges and to other tiles
   - drag a tile's edge or corner to resize it; it stops at the smallest size the app allows
   - drag the line two tiles share to resize both
   - Layout (above each screen): full, halves, thirds, 40/30/30
   - Taskbar (above each screen): hide it on that screen while the routine runs
   - Undo takes back the last change, Delete removes the selected tile
5. Test run starts the routine (League with the current login) and marks every tile Passed, Late or Failed.
   Save (or Save and close) checks every app is still installed.
- The ... on a routine in the list: Duplicate or Delete.
+ Add app or page adds a tile from the list of installed apps, or a web page.

SPECIAL TILES
- Web page: Clean window = no address bar, tabs or bookmarks. Uses your default browser
  (Chrome, Brave, Opera or Vivaldi). Firefox opens normal windows. Mise doesn't use Edge: with Edge as
  your default it uses another installed browser.
- u.gg: the u.gg tile only marks where the page goes. It opens when you pick a champion.
- Spotify: Mini player puts the small player in that spot (open it once in Spotify first).
- League client: position only, its size is set in League.
- A friend's Discord stream: + Add app or page > A friend's Discord stream, type their Discord name. While the routine runs
  (a League routine: once League is open), Mise opens their stream when they go live in your voice channel, pops it out
  and places it here. Exiting the routine closes it.
- Pop-up spot on the map (routine setting): where the small progress pop-up shows while the routine runs.
- Right-click a tile > Quick size: full screen, halves, thirds or quarters.
- Start with a program (routine setting): the routine starts by itself when that program (e.g. your game) opens.

ROUTINE SETTINGS
- Log in to League: starting the routine asks which account, then logs in, starts the client and your lobby
  first, and arranges everything else while League loads.
- Hotkey: click it and press your keys (Ctrl or Alt plus a letter, digit or F-key). Backspace clears it.

THE MISE WINDOW (desktop icon, or tray > Open Mise)
- Routines: one click starts one. Mise steps away and a small pill shows the progress; point at it for the step list
  (it opens by itself for a problem or a League update, with a Fix button on problems). It fades out 3 s after it is done.
  When League is updating, Mise waits and says so instead of pressing Play.
- League accounts: one click logs in to that account, or switches if another one is open. Nothing else.
  The ... on an account (or right-click): update its saved login, remove it, or give it its own lobby and a routine
  that starts with it.
  Starting a routine while another is on switches: the old one exits first.
- Tools: Re-arrange '<routine>' (put the windows back), Edit routines (the builder), + Account.
- League options (when League is installed): auto-accept, lobby after login (pick from the list), u.gg page for your champion.
- Exit '<routine>' shows while a routine runs.
- The gear: Look (Ember or five glass looks: Midnight Glass, Aurora, Ember Glass, Deep Sea, Nebula; the logo stays copper), accent colour, pop-up corner, window spot, check for updates, Rename screens (screens are named automatically), Fix League client, Restart Mise,
  Start over (first-time setup again, League accounts stay), Uninstall Mise, About.
  Routine rows show small icons of their apps. League options > Exit routine when League closes: a League routine
  exits by itself about a minute after the League client is closed.
  Drag a routine or account row up or down to reorder it. The tray icon shows a play badge while a routine is on.
- Motion (Settings > Animations turns it all off): the window rises in and the rows slide in, rows react to the mouse,
  the account frame glides to the account you switch to, and tiles in Edit routines lift, show guide lines and snap.

TRAY (left- or right-click the icon)
A compact menu in the current look: what is running with Exit (or Stop while it starts), Open Mise, Re-arrange (last routine), the update when ready,
your routines, Switch account (a check on the logged-in one), Edit routines, Restart Mise, Quit Mise.
Auto-accept and the u.gg page are in the Mise window (League options).

LEAGUE
- Saved logins live in %USERPROFILE%\LeagueAccounts and never contain passwords. Keep that folder private.
- Do not sign out of Riot Client between accounts: signing out cancels the saved login.
- If a lobby does not open, Mise tests every lobby type once, remembers which ones work today and enters the best one.
- If a saved login is rejected, Mise stops: log in by hand, then the account's ... > Update saved login.

UPDATES
Mise checks GitHub (codefecta/Mise) every few hours and installs the update quietly when nothing is running. Settings > Check for updates checks right now.

Your routines and settings live in %APPDATA%\Mise\config.json and are kept when you update or uninstall.
Settings > Uninstall Mise (or UNINSTALL.cmd) removes Mise (not your routines or saved logins).
