package.path="./?.lua;"..package.path
M = dofile("./mocks.lua")
local BOX = { [4301]="NAME", [4302]="DESC", [4303]="DETAILS", [4304]="FLAVOR" }
local function show(title, cfg, traits, hoverFor)
  G = dofile("./harness.lua")
  M.install(G, nil, cfg)
  M.pendingGameLoad = nil
  dofile("../src/main.lua")
  if M.pendingGameLoad then M.pendingGameLoad() end
  if traits then G.CurrentRun = G.newRun(traits) end
  local sc = G.newInventoryScreen()
  G.SelectFirstBoon_InventoryTabOpen(sc)
  if hoverFor then
    local target
    for _, b in ipairs(sc.SelectFirstBoonButtons) do
      if hoverFor(b) then target = target or b end
    end
    G.textBoxWrites = {}
    if target then G.SelectFirstBoon_InventoryTabOver(target) end
  end
  print("\n### " .. title)
  for _, w in ipairs(G.textBoxWrites) do
    if BOX[w.Id] then
      print(string.format("  %-8s %s", BOX[w.Id], (w.RawText or ""):gsub("{#BoldFormat}","**"):gsub("{#Prev}","**")))
    end
  end
end
local KEEP = { { ForceBoonName = "ApolloUpgrade", Uses = 1 } }
local function cfg(t) local c = { ShowInventoryTab = true } for k,v in pairs(t) do c[k]=v end return c end

print("=========== RESTING PANEL ===========")
show("Nothing picked", cfg{ God = "" })
show("Zeus picked", cfg{ God = "ZeusUpgrade" })
show("Zeus picked, Apollo keepsake, KeepsakeWins OFF", cfg{ God="ZeusUpgrade", KeepsakeWins=false }, KEEP)
show("Zeus picked, Apollo keepsake, KeepsakeWins ON", cfg{ God="ZeusUpgrade", KeepsakeWins=true }, KEEP)
show("Zeus picked, keepsake, AlwaysFirst ON", cfg{ God="ZeusUpgrade", KeepsakeWins=false, AlwaysFirst=true }, KEEP)
show("Apollo keepsake AND Apollo picked -- the same god", cfg{ God="ApolloUpgrade", KeepsakeWins=false }, KEEP)
show("Everything OFF", cfg{ God="ZeusUpgrade", DisableEverything=true })

print("\n=========== HOVERING ===========")
show("Hover a god you have not picked", cfg{ God="" }, nil, function(b) return b.SelectFirstBoonGod=="HeraUpgrade" end)
show("Hover the god you HAVE picked", cfg{ God="ZeusUpgrade" }, nil, function(b) return b.SelectFirstBoonGod=="ZeusUpgrade" end)
show("Hover Standard", cfg{ God="ZeusUpgrade" }, nil, function(b) return b.SelectFirstBoonGod=="" end)
show("Hover Hermes Delay (on)", cfg{ God="", BlockHermesBeforeBoon=true }, nil,
     function(b) return b.SelectFirstBoonGate and b.SelectFirstBoonGate.key=="BlockHermesBeforeBoon" end)
show("Hover Hermes Delay (off)", cfg{ God="", BlockHermesBeforeBoon=false }, nil,
     function(b) return b.SelectFirstBoonGate and b.SelectFirstBoonGate.key=="BlockHermesBeforeBoon" end)
show("Hover Always First (off)", cfg{ God="", AlwaysFirst=false }, nil,
     function(b) return b.SelectFirstBoonGate and b.SelectFirstBoonGate.key=="AlwaysFirst" end)
show("Hover Turn Everything Off (off)", cfg{ God="" }, nil,
     function(b) return b.SelectFirstBoonGate and b.SelectFirstBoonGate.key=="DisableEverything" end)
show("Hover a god while a keepsake is equipped", cfg{ God="ZeusUpgrade", KeepsakeWins=true }, KEEP,
     function(b) return b.SelectFirstBoonGod=="HeraUpgrade" end)
show("Hover Selene Delay (on)", cfg{ God="", BlockSeleneBeforeBoon=true }, nil,
     function(b) return b.SelectFirstBoonGate and b.SelectFirstBoonGate.key=="BlockSeleneBeforeBoon" end)
show("Both delays OFF -- the held-back line should vanish",
     cfg{ God="ZeusUpgrade", BlockHermesBeforeBoon=false, BlockSeleneBeforeBoon=false })
show("Hermes picked, Hermes Delay ON -- the pick overrides its own gate",
     cfg{ God="@Hermes", BlockHermesBeforeBoon=true })
show("Hover the gate your pick overrides",
     cfg{ God="@Hermes", BlockHermesBeforeBoon=true }, nil,
     function(b) return b.SelectFirstBoonGate and b.SelectFirstBoonGate.key=="BlockHermesBeforeBoon" end)
show("Selene picked, both delays ON", cfg{ God="@Selene", BlockHermesBeforeBoon=true,
     BlockSeleneBeforeBoon=true })
show("Always First ON", cfg{ God="ZeusUpgrade", AlwaysFirst=true })
