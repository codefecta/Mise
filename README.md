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
Later, one click on an account logs in or switches. The **...** on an account (or right-click): **Update saved login** (if Riot rejects it), remove, **Lobby for this account** (its own lobby instead of Lobby after login) and **Routine for this account** (starts with it; a League routine then does the login). The row shows what the account has set.

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
- **A friend's Discord stream**: type their Discord display name. While the routine runs, when they stream in your voice channel Mise opens the stream, pops it out (stream only, no member strip) and puts it on this tile. In a League routine it waits until League is open. Be in the voice channel with Discord open. Exiting the routine closes the popout. Drag or resize the stream tile in Edit routines to set where the popout goes. Mise only acts while you are in a voice call and never joins a channel for you.
- **Pop-up spot on the map** (routine setting): switch it on and place the small progress box where you want it while this routine runs. Off: the corner from Settings.

### Routine settings
- **Log in to League**: starting the routine asks which account, logs in and opens your lobby first, and arranges everything else while League loads.
- **Quick size**: right-click a tile > Quick size: full screen, halves, thirds or quarters in one click.
- **Undo**: Ctrl+Z (or the Undo button, which shows how many steps there are) takes back the last change on the map; the map says what was undone.
- **Spotify mini player**: its tile only takes sizes the mini player really allows (Mise reads them from the mini player when it is open).
- **Hotkey**: click it, press Ctrl or Alt plus a key (Backspace clears it).
- **Start with a program**: pick a program (for example your game); when it opens, this routine starts by itself. Open the program first to pick it from the list, or type its name.

### Running things
- A routine card on the Mise window: one click starts it. The tray icon menu has the same routines. Mise first minimizes your open windows, then arranges.
- While a routine or account switch is starting, the progress pop-up and the tray menu have **Stop**.
- Starting a routine while another one is on switches: the old one exits first (windows both use stay put), then the new one starts.
- **Progress pop-up**: a slim pill (what is happening, how many apps are ready, a ring) that fades out 3 s after it is done. Point at it to unfold the step list: each step with the second it happened, the one running now pulses. It unfolds by itself when something needs a look or League is updating. A problem row has a **Fix** button: click it for what went wrong and the one action that fixes it (Re-arrange now, Edit routines, Fix League client...). **Stop** and **Hide** sit at its bottom.
- **League updating**: when Riot Client is updating League, Mise says so in the pop-up (with the percentage), waits for it and does not press Play or restart anything; League starts when the update is done.
- **Exit '<name>'** (shown while a routine runs; also in the tray) closes/leaves each window as you chose and brings the taskbar back.
- While a routine is on, the tray icon shows a small play badge and its name.
- Routine rows show small icons of the apps they open.
- **Exit routine when League closes** (League options, on by default): a League routine exits by itself about a minute after the League client is closed.
- **Drag** a routine or account row up or down to reorder it. The tray menu follows the same order.
- **Re-arrange '<name>'** puts the last routine's windows back in place without starting anything.

### The other buttons
- **League options** (when League is installed): auto-accept match, lobby after login (pick from the list), open u.gg for your champion.
- **Gear (top right)**: **Look** (Ember, or one of five glass looks: Midnight Glass, Aurora, Ember Glass, Deep Sea, Nebula; the logo stays copper in all of them), accent colour, progress pop-up corner, where the Mise window sits, check for updates, **Rename screens** (Mise names screens by itself, e.g. "Main - MAG 274Q X24"; a newly plugged-in screen is named automatically), **Fix League client** (if the client opens blank or stuck), **Restart Mise**, **Start over** (first-time setup again; League accounts stay), **Uninstall Mise** (routines, settings and accounts stay), About.
- **Motion**: opening Mise plays a short logo animation, the window rises in and the rows slide in. Rows lift a little under the mouse (a play button slides in on routines), switches spring, and when you click another account the copper frame glides over to it with a "switching..." line. In Edit routines a dragged tile lifts with a shadow, leaves a faint ghost where it came from, shows copper guide lines when its edges line up with another tile and settles with a small bounce ("snapped"). Gear > *Animations* off turns all motion off.
- **Tray**: left-click for the menu, double-click opens Mise. A compact menu in the current look: on top what is running with its **Exit** (or **Stop** while it starts), Open Mise, **Re-arrange** your last routine, the update when one is ready, your routines with their hotkeys, Switch account (the logged-in account has a check), Edit routines, Restart Mise and *Quit Mise* (closes everything). The League options live in the Mise window.

### If something looks wrong
- A window won't move or is too small: apps have a smallest size, tiles stop at it.
- Login rejected: log in by hand once, then right-click the account > **Update saved login**.
- Mise checks your routines when it starts and tells you if an app is uninstalled or a screen is missing.
- Your settings are backed up automatically (last 5 versions); a broken settings file is restored by itself.
- Anything weird: gear > **Restart Mise**.

Your routines and settings live in `%APPDATA%\Mise`; saved logins (no passwords) in `%USERPROFILE%\LeagueAccounts`: keep that folder private. `UNINSTALL.cmd` removes Mise but keeps both.
