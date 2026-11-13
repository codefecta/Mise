# Mise (shared edition) - layout library: pure functions, no Windows calls.
# Used by the builder (map editing) and the runner (placement and launch order). Tested in dev/test-layout.ps1.
#
# A tile's rect is a fraction of its monitor's FULL bounds: @{ x; y; w; h } between 0 and 1.
# A monitor here is @{ id; X; Y; W; H } in desktop pixels (full bounds, not the work area).

# ---------- fractions <-> pixels ----------
# right and bottom edges are rounded on their own, so neighbouring tiles never leave a 1 px gap
function ConvertTo-PxRect($mon, $r) {
  $l = [Math]::Round([double]$r.x * $mon.W); $t = [Math]::Round([double]$r.y * $mon.H)
  $rr = [Math]::Round(([double]$r.x + [double]$r.w) * $mon.W); $b = [Math]::Round(([double]$r.y + [double]$r.h) * $mon.H)
  return @{ X = [int]($mon.X + $l); Y = [int]($mon.Y + $t); W = [int]($rr - $l); H = [int]($b - $t) }
}
function ConvertTo-FracRect($mon, $px) {
  return @{ x = ([double]$px.X - $mon.X) / $mon.W; y = ([double]$px.Y - $mon.Y) / $mon.H; w = [double]$px.W / $mon.W; h = [double]$px.H / $mon.H }
}
function Copy-Rect($r) { return @{ x = [double]$r.x; y = [double]$r.y; w = [double]$r.w; h = [double]$r.h } }
function Get-Right($r) { [double]$r.x + [double]$r.w }
function Get-Bottom($r) { [double]$r.y + [double]$r.h }

# which monitor holds most of a pixel rectangle (for Copy my screen)
function Find-MonitorFor($monitors, $px) {
  $best = $null; $bestA = 0
  foreach ($m in $monitors) {
    $ix = [Math]::Max(0, [Math]::Min($px.X + $px.W, $m.X + $m.W) - [Math]::Max($px.X, $m.X))
    $iy = [Math]::Max(0, [Math]::Min($px.Y + $px.H, $m.Y + $m.H) - [Math]::Max($px.Y, $m.Y))
    if ($ix * $iy -gt $bestA) { $bestA = $ix * $iy; $best = $m }
  }
  return $best
}
# a window that hangs over the edge of its monitor is pulled inside (it keeps its size where it fits)
function Limit-ToMonitor($r) {
  $o = Copy-Rect $r
  $o.w = [Math]::Min(1.0, [Math]::Max(0.0, $o.w)); $o.h = [Math]::Min(1.0, [Math]::Max(0.0, $o.h))
  $o.x = [Math]::Min(1.0 - $o.w, [Math]::Max(0.0, $o.x)); $o.y = [Math]::Min(1.0 - $o.h, [Math]::Max(0.0, $o.y))
  return $o
}

# ---------- magnetic edges ----------
# guide lines on one axis: the monitor edges plus the edges of the other tiles on the same monitor
function Get-Guides($tiles, [string]$axis, [string]$exceptId) {
  $g = New-Object System.Collections.Generic.List[double]
  $g.Add(0.0); $g.Add(1.0)
  foreach ($t in $tiles) {
    if ($t.id -eq $exceptId) { continue }
    if ($axis -eq 'x') { $g.Add([double]$t.rect.x); $g.Add((Get-Right $t.rect)) } else { $g.Add([double]$t.rect.y); $g.Add((Get-Bottom $t.rect)) }
  }
  return $g.ToArray()
}
# nearest guide within the tolerance, else $null
function Find-Snap([double]$v, $guides, [double]$tol) {
  $best = $null; $bd = $tol
  foreach ($g in $guides) { $d = [Math]::Abs($v - $g); if ($d -le $bd) { $bd = $d; $best = $g } }
  return $best
}
# move: whichever edge is closer to a guide pulls the whole tile there (size never changes)
function Get-SnappedMove($r, $gx, $gy, [double]$tolX, [double]$tolY) {
  $o = Copy-Rect $r
  $sl = Find-Snap $o.x $gx $tolX; $sr = Find-Snap (Get-Right $o) $gx $tolX
  $dl = if ($null -ne $sl) { [Math]::Abs($o.x - $sl) } else { 9 }; $dr = if ($null -ne $sr) { [Math]::Abs((Get-Right $o) - $sr) } else { 9 }
  if ($dl -le $dr -and $null -ne $sl) { $o.x = $sl } elseif ($null -ne $sr) { $o.x = $sr - $o.w }
  $st = Find-Snap $o.y $gy $tolY; $sb = Find-Snap (Get-Bottom $o) $gy $tolY
  $dt = if ($null -ne $st) { [Math]::Abs($o.y - $st) } else { 9 }; $db = if ($null -ne $sb) { [Math]::Abs((Get-Bottom $o) - $sb) } else { 9 }
  if ($dt -le $db -and $null -ne $st) { $o.y = $st } elseif ($null -ne $sb) { $o.y = $sb - $o.h }
  return (Limit-ToMonitor $o)
}
# resize one edge ('l','r','t','b') to a fraction, snapping it and keeping the minimum size (fractions)
function Get-ResizedRect($r, [string]$edge, [double]$v, $guides, [double]$tol, [double]$minW, [double]$minH, [double]$maxW = 1.0, [double]$maxH = 1.0) {
  $o = Copy-Rect $r
  $s = Find-Snap $v $guides $tol; if ($null -ne $s) { $v = $s }
  $v = [Math]::Min(1.0, [Math]::Max(0.0, $v))
  switch ($edge) {
    'l' { $right = Get-Right $o; $v = [Math]::Max([Math]::Min($v, $right - $minW), $right - $maxW); $o.x = $v; $o.w = $right - $v }
    'r' { $v = [Math]::Min([Math]::Max($v, $o.x + $minW), $o.x + $maxW); $o.w = $v - $o.x }
    't' { $bottom = Get-Bottom $o; $v = [Math]::Max([Math]::Min($v, $bottom - $minH), $bottom - $maxH); $o.y = $v; $o.h = $bottom - $v }
    'b' { $v = [Math]::Min([Math]::Max($v, $o.y + $minH), $o.y + $maxH); $o.h = $v - $o.y }
  }
  return $o
}

# ---------- minimum sizes ----------
# min sizes come in pixels (from the app); as fractions of this monitor
function Get-MinFrac($tile, $mon) {
  $mw = if ($tile.minW) { [double]$tile.minW / $mon.W } else { 0.04 }
  $mh = if ($tile.minH) { [double]$tile.minH / $mon.H } else { 0.03 }
  # the largest size the app accepts (the Spotify mini player has one); none = the whole screen
  $xw = 1.0; $xh = 1.0
  try { if ($tile.maxW -and [double]$tile.maxW -gt 0) { $xw = [Math]::Max([Math]::Min(1.0, $mw), [Math]::Min(1.0, [double]$tile.maxW / $mon.W)) } } catch {}
  try { if ($tile.maxH -and [double]$tile.maxH -gt 0) { $xh = [Math]::Max([Math]::Min(1.0, $mh), [Math]::Min(1.0, [double]$tile.maxH / $mon.H)) } } catch {}
  return @{ w = [Math]::Min(1.0, $mw); h = [Math]::Min(1.0, $mh); xw = $xw; xh = $xh }
}
# grow a rect to the minimum size, keeping its top-left where it fits
function Set-MinSize($r, $min) {
  $o = Copy-Rect $r
  if ($o.w -lt $min.w) { $o.w = $min.w }
  if ($o.h -lt $min.h) { $o.h = $min.h }
  if ($null -ne $min.xw -and $o.w -gt $min.xw) { $o.w = $min.xw }
  if ($null -ne $min.xh -and $o.h -gt $min.xh) { $o.h = $min.xh }
  return (Limit-ToMonitor $o)
}

# ---------- tidy after Copy my screen ----------
# closes small gaps (to the monitor edge and between tiles), removes small overlaps; counts what it did
function Invoke-Tidy($tiles, [double]$tol = 0.03) {
  $gaps = 0; $overl = 0
  $list = @($tiles | ForEach-Object { $_.rect = Limit-ToMonitor $_.rect; $_ })
  # 1. edges near the monitor edge go to it
  foreach ($t in $list) {
    $r = $t.rect
    if ($r.x -gt 0 -and $r.x -le $tol) { $r.w += $r.x; $r.x = 0.0; $gaps++ }
    if ($r.y -gt 0 -and $r.y -le $tol) { $r.h += $r.y; $r.y = 0.0; $gaps++ }
    $d = 1.0 - (Get-Right $r); if ($d -gt 0 -and $d -le $tol) { $r.w += $d; $gaps++ }
    $d = 1.0 - (Get-Bottom $r); if ($d -gt 0 -and $d -le $tol) { $r.h += $d; $gaps++ }
  }
  # 2. a tile's edge that nearly meets a neighbour's opposite edge (with overlap on the other axis) meets it
  for ($i = 0; $i -lt $list.Count; $i++) {
    for ($j = 0; $j -lt $list.Count; $j++) {
      if ($i -eq $j) { continue }
      $a = $list[$i].rect; $b = $list[$j].rect
      $ovY = [Math]::Min((Get-Bottom $a), (Get-Bottom $b)) - [Math]::Max($a.y, $b.y)
      $ovX = [Math]::Min((Get-Right $a), (Get-Right $b)) - [Math]::Max($a.x, $b.x)
      if ($ovY -gt 0.05) {   # side by side: a on the left of b
        $gap = $b.x - (Get-Right $a)
        if ($gap -gt 0.000001 -and $gap -le $tol) { $a.w += $gap; $gaps++ }
        elseif ($gap -lt -0.000001 -and -$gap -le [Math]::Max($tol, 0.15 * [Math]::Min($a.w, $b.w)) -and $a.x -lt $b.x) { $a.w += $gap; $overl++ }
      }
      if ($ovX -gt 0.05) {   # stacked: a above b
        $gap = $b.y - (Get-Bottom $a)
        if ($gap -gt 0.000001 -and $gap -le $tol) { $a.h += $gap; $gaps++ }
        elseif ($gap -lt -0.000001 -and -$gap -le [Math]::Max($tol, 0.15 * [Math]::Min($a.h, $b.h)) -and $a.y -lt $b.y) { $a.h += $gap; $overl++ }
      }
    }
  }
  return @{ Tiles = $list; Gaps = $gaps; Overlaps = $overl }
}

# ---------- layout presets per monitor ----------
function Get-Presets([bool]$vertical) {
  $p = [ordered]@{}
  $p['Full'] = @(@{ x = 0; y = 0; w = 1; h = 1 })
  if ($vertical) {
    $p['Halves'] = @(@{ x = 0; y = 0; w = 1; h = 0.5 }, @{ x = 0; y = 0.5; w = 1; h = 0.5 })
    $p['Thirds'] = @(@{ x = 0; y = 0; w = 1; h = 1 / 3 }, @{ x = 0; y = 1 / 3; w = 1; h = 1 / 3 }, @{ x = 0; y = 2 / 3; w = 1; h = 1 / 3 })
    $p['40 / 30 / 30'] = @(@{ x = 0; y = 0; w = 1; h = 0.4 }, @{ x = 0; y = 0.4; w = 1; h = 0.3 }, @{ x = 0; y = 0.7; w = 1; h = 0.3 })
  } else {
    $p['Halves'] = @(@{ x = 0; y = 0; w = 0.5; h = 1 }, @{ x = 0.5; y = 0; w = 0.5; h = 1 })
    $p['Thirds'] = @(@{ x = 0; y = 0; w = 1 / 3; h = 1 }, @{ x = 1 / 3; y = 0; w = 1 / 3; h = 1 }, @{ x = 2 / 3; y = 0; w = 1 / 3; h = 1 })
    $p['Main + side'] = @(@{ x = 0; y = 0; w = 2 / 3; h = 1 }, @{ x = 2 / 3; y = 0; w = 1 / 3; h = 1 })
  }
  return $p
}
# tiles take the preset's slots in reading order (top to bottom, left to right); tiles beyond the slots keep their spot
function Set-Preset($tiles, $slots) {
  $sorted = @($tiles | Sort-Object { [Math]::Round([double]$_.rect.y, 2) }, { [double]$_.rect.x })
  for ($i = 0; $i -lt [Math]::Min($sorted.Count, @($slots).Count); $i++) { $sorted[$i].rect = Copy-Rect $slots[$i] }
  return $tiles
}

# ---------- the edge two tiles share (the grip: drag to resize both) ----------
# returns the shared edges on a monitor: axis x = a vertical line (left tiles | right tiles), axis y = a horizontal line
function Get-SharedEdges($tiles, [double]$tol = 0.002) {
  $edges = @()
  $list = @($tiles)
  foreach ($axis in 'x', 'y') {
    $lines = @{}
    foreach ($a in $list) {
      $pos = if ($axis -eq 'x') { Get-Right $a.rect } else { Get-Bottom $a.rect }
      if ($pos -ge 1 - $tol) { continue }
      foreach ($b in $list) {
        if ($a.id -eq $b.id) { continue }
        $start = if ($axis -eq 'x') { [double]$b.rect.x } else { [double]$b.rect.y }
        if ([Math]::Abs($start - $pos) -gt $tol) { continue }
        $ov = if ($axis -eq 'x') { [Math]::Min((Get-Bottom $a.rect), (Get-Bottom $b.rect)) - [Math]::Max($a.rect.y, $b.rect.y) } else { [Math]::Min((Get-Right $a.rect), (Get-Right $b.rect)) - [Math]::Max($a.rect.x, $b.rect.x) }
        if ($ov -le $tol) { continue }
        $key = [Math]::Round($pos, 3).ToString([Globalization.CultureInfo]::InvariantCulture)
        if (-not $lines.ContainsKey($key)) { $lines[$key] = @{ axis = $axis; pos = $pos; before = @(); after = @() } }
        if ($lines[$key].before -notcontains $a.id) { $lines[$key].before += $a.id }
        if ($lines[$key].after -notcontains $b.id) { $lines[$key].after += $b.id }
      }
    }
    $edges += @($lines.Values)
  }
  return $edges
}
# move a shared edge; tiles before it grow/shrink at their far edge, tiles after it at their near edge. Min sizes hold.
function Move-SharedEdge($tiles, $edge, [double]$v, $mon) {
  $byId = @{}; foreach ($t in $tiles) { $byId[$t.id] = $t }
  $lo = 0.0; $hi = 1.0
  foreach ($id in $edge.before) { $t = $byId[$id]; $m = Get-MinFrac $t $mon; $lo = [Math]::Max($lo, $(if ($edge.axis -eq 'x') { $t.rect.x + $m.w } else { $t.rect.y + $m.h })); $hi = [Math]::Min($hi, $(if ($edge.axis -eq 'x') { $t.rect.x + $m.xw } else { $t.rect.y + $m.xh })) }
  foreach ($id in $edge.after) { $t = $byId[$id]; $m = Get-MinFrac $t $mon; $hi = [Math]::Min($hi, $(if ($edge.axis -eq 'x') { (Get-Right $t.rect) - $m.w } else { (Get-Bottom $t.rect) - $m.h })) }
  foreach ($id in $edge.after) { $t = $byId[$id]; $m = Get-MinFrac $t $mon; $lo = [Math]::Max($lo, $(if ($edge.axis -eq 'x') { (Get-Right $t.rect) - $m.xw } else { (Get-Bottom $t.rect) - $m.xh })) }
  if ($lo -gt $hi) { return $edge.pos }
  $v = [Math]::Min($hi, [Math]::Max($lo, $v))
  foreach ($id in $edge.before) { $r = $byId[$id].rect; if ($edge.axis -eq 'x') { $r.w = $v - $r.x } else { $r.h = $v - $r.y } }
  foreach ($id in $edge.after) { $r = $byId[$id].rect; if ($edge.axis -eq 'x') { $e = Get-Right $r; $r.x = $v; $r.w = $e - $v } else { $e = Get-Bottom $r; $r.y = $v; $r.h = $e - $v } }
  $edge.pos = $v
  return $v
}

# ---------- undo ----------
function New-UndoStack { return @{ Items = New-Object System.Collections.Generic.List[string]; Max = 100 } }
function Push-Undo($stack, $state) {
  $stack.Items.Add((ConvertTo-Json $state -Depth 8 -Compress))
  if ($stack.Items.Count -gt $stack.Max) { $stack.Items.RemoveAt(0) }
}
function Pop-Undo($stack) {
  if ($stack.Items.Count -eq 0) { return $null }
  $s = $stack.Items[$stack.Items.Count - 1]; $stack.Items.RemoveAt($stack.Items.Count - 1)
  return ($s | ConvertFrom-Json)
}

# ---------- launch order and waiting ----------
# League is started by the routine's League switch before any tile. Then: apps that still need starting,
# slowest first (they get the most time), then apps that are already open (only moved), then web pages.
# The u.gg tile and the Mise tile are never launched.
function Get-LaunchOrder($tiles, $running, $timings) {
  $apps = @($tiles | Where-Object { $_.kind -eq 'app' -or $_.kind -eq 'spotify' })
  $cold = @($apps | Where-Object { $running -notcontains $_.id } | Sort-Object { -1 * (Get-LearnedSeconds $timings (Get-TimingKey $_)) })
  $warm = @($apps | Where-Object { $running -contains $_.id })
  $web  = @($tiles | Where-Object { $_.kind -eq 'web' })
  return @($cold) + @($warm) + @($web)
}
function Get-TimingKey($tile) { if ($tile.exe) { return (("$($tile.exe)" -split '[\\/]')[-1]).ToLower() } elseif ($tile.appid) { return "$($tile.appid)".ToLower() } else { return "$($tile.name)".ToLower() } }
function Get-LearnedSeconds($timings, [string]$key) {
  if ($timings -and $timings.ContainsKey($key) -and @($timings[$key]).Count) { return [double](@($timings[$key]) | Measure-Object -Maximum).Maximum }
  return 0
}
# how long to wait for a window before calling it "doesn't open": twice the slowest of the last runs, 20 s at least, 120 s at most
function Get-WaitSeconds($timings, [string]$key) {
  $s = Get-LearnedSeconds $timings $key
  if ($s -le 0) { return 30 }
  return [int][Math]::Min(120, [Math]::Max(20, [Math]::Ceiling(2 * $s)))
}
function Add-Timing($timings, [string]$key, [double]$seconds) {
  if (-not $timings.ContainsKey($key)) { $timings[$key] = @() }
  $timings[$key] = @(@($timings[$key]) + [Math]::Round($seconds, 1) | Select-Object -Last 3)
  return $timings
}

# ---------- web pages ----------
$script:WebPresets = [ordered]@{ 'u.gg' = 'https://u.gg'; 'op.gg' = 'https://op.gg'; 'YouTube' = 'https://www.youtube.com'; 'Twitch' = 'https://www.twitch.tv' }
# a first guess at a browser window's address from its title ("U.GG Tier List - Google Chrome" -> https://u.gg)
function Get-UrlGuess([string]$title) {
  $t = ($title -replace '\s+-\s+(Google Chrome|Brave|Opera|Vivaldi|Mozilla Firefox|Microsoft Edge|Microsoft.*Edge)$', '').Trim()
  if ($t -match '(?i)\bu\.gg\b') { return 'https://u.gg' }
  if ($t -match '(?i)\bop\.gg\b') { return 'https://op.gg' }
  if ($t -match '(?i)youtube') { return 'https://www.youtube.com' }
  if ($t -match '(?i)twitch') { return 'https://www.twitch.tv' }
  if ($t -match '(?i)\b([a-z0-9-]+\.)+(com|net|org|gg|tv|io|co|app|dev|gg)\b') { return "https://$($Matches[0].ToLower())" }
  return ''
}
# what the default browser can do (from its registry ProgId)
function Get-BrowserKind([string]$progId) {
  switch -Regex ($progId) {
    '^ChromeHTML' { return @{ Kind = 'chrome'; Name = 'Chrome'; Clean = $true } }
    '^BraveHTML' { return @{ Kind = 'brave'; Name = 'Brave'; Clean = $true } }
    '^VivaldiHTM' { return @{ Kind = 'vivaldi'; Name = 'Vivaldi'; Clean = $true } }
    '^Opera' { return @{ Kind = 'opera'; Name = 'Opera'; Clean = $true } }
    '^MSEdgeHTM' { return @{ Kind = 'edge'; Name = 'Edge'; Clean = $false } }   # Mise never uses Edge
    '^FirefoxURL' { return @{ Kind = 'firefox'; Name = 'Firefox'; Clean = $false } }
    default { return @{ Kind = 'other'; Name = 'your browser'; Clean = $false } }
  }
}

# ---------- check on save ----------
# $envr: @{ Exists = { param($tile) bool }; Monitors = @(ids); Browser = Get-BrowserKind result; Conflicts = @(text) }
function Test-RoutineHealth($routine, $envr) {
  $out = @()
  $tiles = @($routine.tiles)
  if ($tiles.Count -eq 0 -and -not $routine.league) { $out += @{ Level = 'error'; Text = 'The routine is empty: copy your screen or add an app.' } }
  if (-not "$($routine.name)".Trim()) { $out += @{ Level = 'error'; Text = 'Give the routine a name.' } }
  foreach ($t in $tiles) {
    if (@($envr.Monitors) -notcontains $t.monitor) { $out += @{ Level = 'warn'; Text = "$($t.name): its screen is not connected now, it will not be placed." } }
    if ($t.kind -eq 'app' -or $t.kind -eq 'spotify') {
      if (& $envr.Exists $t) { $out += @{ Level = 'ok'; Text = "$($t.name) found" } } else { $out += @{ Level = 'error'; Text = "$($t.name) is not installed on this PC." } }
    }
    if ($t.kind -eq 'stream' -and -not "$($t.streamer)".Trim()) { $out += @{ Level = 'error'; Text = "$($t.name): type your friend's Discord name." } }
    if ($t.kind -eq 'web') {
      if (-not "$($t.url)".Trim()) { $out += @{ Level = 'error'; Text = "$($t.name): no address." } }
      elseif ($envr.Browser.Kind -eq 'none') { $out += @{ Level = 'error'; Text = "$($t.name): no supported browser (Chrome, Brave, Vivaldi or Opera; Mise doesn't use Edge)." } }
      elseif ($t.clean -and -not $envr.Browser.Clean) { $out += @{ Level = 'warn'; Text = "$($t.name): $($envr.Browser.Name) can't open clean windows, it opens as a normal window." } }
    }
  }
  foreach ($c in @($envr.Conflicts)) { $out += @{ Level = 'warn'; Text = "Hotkey: $c" } }
  return $out
}
