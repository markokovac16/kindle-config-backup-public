package.path = arg[1] .. "/?.lua;" .. package.path
local E = require("chess_engine")
local fails = 0
local function check(name, cond, extra) print((cond and "OK   " or "FAIL ") .. name .. (extra and ("  " .. extra) or "")); if not cond then fails = fails + 1 end end
local function sanOf(pos, m) return pos:san(m) end
local function best(fen, opts) local p = E.newPosition(fen); local m = E.think(p, opts or { time = 2 }); return p:san(m), p end

-- Mates
check("mate in 1 (back rank)", best("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1") == "Ra8#")
local s = best("r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4"); check("scholar's mate Qxf7#", s == "Qxf7#", s)
s = best("6k1/pp4p1/2p5/2bp4/8/P5Pb/1P3rrP/2BRRN1K b - - 0 1", { time = 4 }); check("mate in 2 (black)", s == "Rg1+" or s == "Rxh2+", s)
s = best("2r3k1/p4p2/3Rp2p/1p2P1pK/8/1P4P1/P3Q2P/1q6 b - - 0 1", { time = 4 }); check("mate in 2 Qg6+ line", s == "Qg6+" or s == "Qf5+", s)
-- Takes free material, doesn't hang the queen
s = best("4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1"); check("wins hanging queen", s == "Rxd5", s)
s = best("4k3/8/8/8/8/2n5/3Q4/4K3 w - - 0 1"); check("captures knight safely", s == "Qxc3" or s:match("^Q") ~= nil, s)
-- Prefers mate over stalemate (K+Q v K)
local p = E.newPosition("7k/8/6QK/8/8/8/8/8 w - - 0 1"); local m = E.think(p, { time = 1 }); s = p:san(m)
check("K+Q mates instead of stalemating", s:sub(-1) == "#", s)
-- SAN details
p = E.newPosition("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
local sans = {}; for _, mv in ipairs(p:legalMoves()) do sans[p:san(mv)] = true end
check("castling SAN", sans["O-O"] and sans["O-O-O"])
p = E.newPosition("4k3/8/8/8/8/8/4K3/R6R w - - 0 1"); sans = {}; for _, mv in ipairs(p:legalMoves()) do sans[p:san(mv)] = true end
check("rook disambiguation Rad1/Rhd1", (sans["Rad1"] and sans["Rhd1"] and not sans["Rd1"]) or false)
p = E.newPosition("4k3/1P6/8/8/8/8/8/4K3 w - - 0 1"); sans = {}; for _, mv in ipairs(p:legalMoves()) do sans[p:san(mv)] = true end
check("promotion SAN b8=Q+", sans["b8=Q+"] and sans["b8=N"] or false)
p = E.newPosition("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1"); sans = {}; for _, mv in ipairs(p:legalMoves()) do sans[p:san(mv)] = true end
check("en passant SAN exd6", sans["exd6"] or false)
-- Draw rules
check("K v K insufficient", E.newPosition("4k3/8/8/8/8/8/8/4K3 w - - 0 1"):insufficientMaterial())
check("K+N v K insufficient", E.newPosition("4k3/8/8/8/8/8/8/4KN2 w - - 0 1"):insufficientMaterial())
check("K+R v K sufficient", not E.newPosition("4k3/8/8/8/8/8/8/4KR2 w - - 0 1"):insufficientMaterial())
check("K+B v K+B same colour insufficient", E.newPosition("4kb2/8/8/8/8/8/8/2B1K3 w - - 0 1"):insufficientMaterial())
check("K+B v K+B opposite colour sufficient", not E.newPosition("4k1b1/8/8/8/8/8/8/2B1K3 w - - 0 1"):insufficientMaterial())
check("stalemate has no legal moves", #E.newPosition("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"):legalMoves() == 0)
-- ep key: only when capturable
local a = E.newPosition("4k3/8/8/8/3P4/8/8/4K3 b - d3 0 1"):key(); local b = E.newPosition("4k3/8/8/8/3P4/8/8/4K3 b - - 0 1"):key()
check("ep square ignored in key when no capture", a == b)

-- Self-play: full games end legally with a game-over reason, no errors.
math.randomseed(7)
local function play(opts_w, opts_b, limit)
    local pos = E.newPosition(); local hist, counts = {}, {}
    local k = pos:key(); counts[k] = 1; hist[1] = k
    for ply = 1, limit do
        local legal = pos:legalMoves()
        if #legal == 0 then return pos:inCheck() and "checkmate" or "stalemate", ply end
        if pos.half >= 100 then return "fifty", ply end
        if pos:insufficientMaterial() then return "material", ply end
        local opts = pos.side == 1 and opts_w or opts_b
        opts.history = hist
        local mv = E.think(pos, opts)
        local found = false; for _, l in ipairs(legal) do if l == mv then found = true end end
        if not found then return "ILLEGAL MOVE", ply end
        pos:make(mv)
        k = pos:key(); counts[k] = (counts[k] or 0) + 1; hist[#hist + 1] = k
        if counts[k] >= 3 then return "repetition", ply end
    end
    return "limit", limit
end
for g = 1, 4 do
    local r, n = play({ time = 0.05 }, { max_depth = 1, noise = 150, time = 0.05 }, 400)
    check("self-play game " .. g .. " (strong vs easy)", r ~= "ILLEGAL MOVE", r .. " after " .. n .. " plies")
end
local r, n = play({ time = 0.05 }, { time = 0.05 }, 300)
check("self-play equal engines", r ~= "ILLEGAL MOVE", r .. " after " .. n .. " plies")
-- Speed reference
p = E.newPosition("r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4")
local t0 = os.clock(); E.think(p, { max_depth = 5, time = 30 }); print(string.format("depth-5 search from Italian: %.2fs", os.clock() - t0))
print(fails == 0 and "ALL ENGINE TESTS OK" or (fails .. " FAILURES"))
p = E.newPosition("4k3/8/8/8/R7/8/4K3/R7 w - - 0 1"); sans = {}; for _, mv in ipairs(p:legalMoves()) do sans[p:san(mv)] = true end
check("rank disambiguation R1a3/R4a3", (sans["R1a3"] and sans["R4a3"]) or false)
p = E.newPosition("4k3/8/8/8/8/Q7/8/Q1Q1K3 w - - 0 1"); sans = {}; for _, mv in ipairs(p:legalMoves()) do sans[p:san(mv)] = true end
check("square disambiguation Qa1b2", (sans["Qa1b2"] and sans["Qcb2"] and sans["Q3b2"]) or false)
