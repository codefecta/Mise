# Mise

Everything in its place before you play. Mise switches League accounts in one click and sets up your windows (League, u.gg, Discord, Spotify...) with one button.

**Install:** download the latest zip from [Releases](https://github.com/codefecta/Mise/releases/latest), unzip, double-click `INSTALL.cmd`. Mise lives in the tray (near the clock) and adds a desktop icon.

## Quick guide

### 1. First run
Each screen lights up with a copper frame: give it a name ("Main", "Side"). Then Mise opens its window. Updates are automatic: Mise checks once a day and tells you from the tray.

### 2. Add your League accounts
1. Press **+ Account** (under Tools). A window explains the steps and has an **Open Riot Client** button.
2. In Riot Client log in and tick **Stay signed in**. Don't sign out afterwards.
3. Back in Mise type a nickname, pick the region, press **Save this account**. Mise closes Riot Client and keeps the login (never the password), then opens it on the login screen for the next account.
4. Repeat for each account, then press **Done**.

Signing out of Riot Client by hand cancels the saved login, so don't.
Later, one click on an account logs in or switches. Right-click an account: **Update saved login** (if Riot rejects it) or remove.

### 3. Make a routine
A routine is a layout of windows plus what starts and what closes.
1. Open your apps and put them roughly where you want them.
2. In Mise press **Routines** (or the card on an empty window), then **Copy my screen**.
3. Tick the windows to include. For each, choose what happens when you exit the routine: **Closes** or **Stays open**. Web pages ask for their address.
4. Fine-tune on the map: drag a tile to move it, drag its edge to resize, drag the line between two tiles to resize both. Tiles stick to edges and each other.
5. Above each screen: **Taskbar** (hide it while the routine runs) and **Layout** (halves, thirds...).
6. **Preview** moves windows that are already open (starts nothing). **Test run** starts everything and marks each tile Passed, Late or Failed. **Save** when happy.

Handy: **+ Add app** adds any installed app or a web page. **Ctrl+Z** undoes, **Delete** removes the selected tile. Click a tile to see its options.

### Special tiles
- **u.gg**: marks where the page opens. It opens when you lock a champion.
- **Spotify mini player**: switch on *Mini player* in the tile (the tile shrinks to mini size).
- **League client**: position only.
- **Web page**: *Clean window* hides the address bar and tabs.
- **Mise pop-up**: where the small progress box appears while a routine runs.

### Routine settings
- **Log in to League**: starting the routine asks which account, logs in and opens your lobby first, and arranges everything else while League loads.
- **Hotkey**: click it, press Ctrl or Alt plus a key.

### Running things
- A routine card on the Mise window: one click starts it. The tray icon menu has the same routines. Mise first minimizes your open windows, then arranges.
- **Exit routine** (or tray > exit) closes/leaves each window as you chose and brings the taskbar back.
- **Arrange** puts windows back in place without starting anything.

### The other buttons
- **Options**: auto-accept match, lobby after login, open u.gg for your champion.
- **Fix client**: use if the League client opens blank or stuck.
- **Gear (top right)**: look, pop-up corner, where the Mise window sits, updates, Reset Mise, About.
- **Tray**: left-click for the menu, double-click opens Mise. *Quit Mise* closes everything. *Forget everything* starts over like a first run.

### If something looks wrong
- A window won't move or is too small: apps have a smallest size, tiles stop at it.
- Login rejected: log in by hand once, then right-click the account > **Update saved login**.
- Anything weird: gear > **Reset Mise**.

Your routines and settings live in `%APPDATA%\Mise`; saved logins (no passwords) in `%USERPROFILE%\LeagueAccounts`: keep that folder private. `UNINSTALL.cmd` removes Mise but keeps both.
