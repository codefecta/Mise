# Mise

Everything in its place before you play. Mise switches League accounts in one click and sets up your windows (League, u.gg, Discord, Spotify...) with one button.

**Install:** download the latest zip from [Releases](https://github.com/codefecta/Mise/releases/latest), unzip, double-click `INSTALL.cmd`. Mise lives in the tray (near the clock) and adds a desktop icon.

## Quick guide

### 1. First run
Each screen lights up with a copper frame: give it a name ("Main", "Side"). Then Mise opens its window. Updates are automatic: Mise downloads new versions in the background and installs them when League and Mise aren't in use, never mid-game.

### 2. Add your League accounts
Press **+ Account** (under Tools). It walks you through three steps:
1. **Open Riot Client** (skipped if it's already open).
2. **Log in** and tick **Stay signed in**, then press *I'm logged in*.
3. **Name it**: a nickname (kept as you type it) and the region, then *Save this account*. Mise keeps the login (never the password) and puts Riot Client back on a fresh login screen.

Press *Add another account* for the next one, or **Done**.

Signing out of Riot Client by hand cancels the saved login, so don't.
Later, one click on an account logs in or switches. The **...** on an account (or right-click): **Update saved login** (if Riot rejects it) or remove.

### 3. Make a routine
A routine is a layout of windows plus what starts and what closes.
1. Open your apps and put them roughly where you want them.
2. In Mise press **Edit routines** (or the card on an empty window), then **Copy my screen**.
3. Tick the windows to include. Each has a **When the routine exits** toggle: **Stays open** or **Closes**. Web pages ask for their address.
4. Fine-tune on the map: drag a tile to move it, drag an edge or a corner to resize, drag the line between two tiles to resize both. Tiles stick to edges and each other.
5. Above each screen: **Taskbar** (hide it while the routine runs) and **Layout** (halves, thirds...).
6. The **...** on a routine in the list (or right-click) has **Duplicate** (handy for an ARAM and a Ranked version) and **Delete**.
7. **Test run** starts everything and marks each tile Passed, Late or Failed. **Save** (or **Save and close**) when happy.

Handy: **+ Add app or page** adds any installed app or a web page. Click a tile to see its options; **right-click** it to rename, switch Stays open / Closes or remove. **Undo** takes back the last change, **Delete** removes the selected tile.

### Special tiles
- **u.gg**: marks where the page opens. It opens when you lock a champion.
- **Spotify mini player**: switch on *Mini player* in the tile (the tile shrinks to mini size).
- **League client**: position only.
- **Web page**: *Clean window* hides the address bar and tabs.
- **A friend's Discord stream**: type their Discord display name. While the routine runs and League is open, when they stream in your voice channel Mise opens the stream, pops it out and puts it on this tile (be in the voice channel, Discord open).
- **Pop-up spot on the map** (routine setting): switch it on and place the small progress box where you want it while this routine runs. Off: the corner from Settings.

### Routine settings
- **Log in to League**: starting the routine asks which account, logs in and opens your lobby first, and arranges everything else while League loads.
- **Hotkey**: click it, press Ctrl or Alt plus a key (Backspace clears it).

### Running things
- A routine card on the Mise window: one click starts it. The tray icon menu has the same routines. Mise first minimizes your open windows, then arranges.
- While a routine or account switch is starting, the progress pop-up and the tray menu have **Stop**.
- **Exit '<name>'** (shown while a routine runs; also in the tray) closes/leaves each window as you chose and brings the taskbar back.
- While a routine is on, the tray icon shows a small play badge and its name.
- Routine rows show small icons of the apps they open.
- **Exit routine when League closes** (League options, on by default): a League routine exits by itself about a minute after the League client is closed.
- **Drag** a routine or account row up or down to reorder it. The tray menu follows the same order.
- **Re-arrange '<name>'** puts the last routine's windows back in place without starting anything.

### The other buttons
- **League options** (when League is installed): auto-accept match, lobby after login (pick from the list), open u.gg for your champion.
- **Gear (top right)**: look, progress pop-up corner, where the Mise window sits, check for updates, **Name screens** (after adding or moving a screen), **Fix League client** (if the client opens blank or stuck), **Restart Mise**, **Start over** (first-time setup again; League accounts stay), **Uninstall Mise** (routines, settings and accounts stay), About.
- **Start animation**: opening Mise from its icon plays a short logo animation. Gear > *Animations* off skips it (and all other motion).
- **Tray**: left-click for the menu, double-click opens Mise. It has your routines, accounts, League options, Edit routines, Restart Mise and *Quit Mise* (closes everything).

### If something looks wrong
- A window won't move or is too small: apps have a smallest size, tiles stop at it.
- Login rejected: log in by hand once, then right-click the account > **Update saved login**.
- Mise checks your routines when it starts and tells you if an app is uninstalled or a screen is missing.
- Your settings are backed up automatically (last 5 versions); a broken settings file is restored by itself.
- Anything weird: gear > **Restart Mise**.

Your routines and settings live in `%APPDATA%\Mise`; saved logins (no passwords) in `%USERPROFILE%\LeagueAccounts`: keep that folder private. `UNINSTALL.cmd` removes Mise but keeps both.
