-- Chess rules and a small alpha-beta engine, in pure Lua (no KOReader dependencies,
-- so it can be perft-tested on any LuaJIT).
--
-- Board: 10x12 mailbox. Square = 21 + file + 10 * rank (file/rank 0..7, a1 = 21, h8 = 98).
-- Pieces: 1 pawn, 2 knight, 3 bishop, 4 rook, 5 queen, 6 king; white > 0, black < 0.
-- Moves are integers: from + to * 128 + promo * 16384 + flag * 131072.

local bit = require("bit")
local band = bit.band

local Engine = {}

local P, N, B, R, Q, K = 1, 2, 3, 4, 5, 6
local OFF = 7
local FLAG_DOUBLE, FLAG_EP, FLAG_CASTLE = 1, 2, 3
local WK, WQ, BK, BQ = 1, 2, 4, 8
Engine.P, Engine.N, Engine.B, Engine.R, Engine.Q, Engine.K = P, N, B, R, Q, K

local KNIGHT = { -21, -19, -12, -8, 8, 12, 19, 21 }
local BISHOP = { -11, -9, 9, 11 }
local ROOK = { -10, -1, 1, 10 }
local ROYAL = { -11, -10, -9, -1, 1, 9, 10, 11 }

local function sq(file, rank) return 21 + file + 10 * rank end
local function fileOf(s) return (s - 21) % 10 end
local function rankOf(s) return math.floor((s - 21) / 10) end
Engine.sq, Engine.fileOf, Engine.rankOf = sq, fileOf, rankOf

local function encode(from, to, promo, flag)
    return from + to * 128 + (promo or 0) * 16384 + (flag or 0) * 131072
end
local function mFrom(m) return m % 128 end
local function mTo(m) return math.floor(m / 128) % 128 end
local function mPromo(m) return math.floor(m / 16384) % 8 end
local function mFlag(m) return math.floor(m / 131072) end
Engine.encode, Engine.from, Engine.to, Engine.promo, Engine.flag = encode, mFrom, mTo, mPromo, mFlag

-- Castling rights kept after a piece moves from or to these squares.
local CASTLE_MASK = {}
for s = 0, 119 do CASTLE_MASK[s] = 15 end
CASTLE_MASK[sq(4, 0)] = 15 - WK - WQ
CASTLE_MASK[sq(0, 0)] = 15 - WQ
CASTLE_MASK[sq(7, 0)] = 15 - WK
CASTLE_MASK[sq(4, 7)] = 15 - BK - BQ
CASTLE_MASK[sq(0, 7)] = 15 - BQ
CASTLE_MASK[sq(7, 7)] = 15 - BK

local Position = {}
Position.__index = Position

function Engine.newPosition(fen)
    local pos = setmetatable({ b = {}, kings = {}, stack = {}, ply = 0 }, Position)
    pos:setFen(fen or "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    return pos
end

local LETTER = { p = P, n = N, b = B, r = R, q = Q, k = K }

function Position:setFen(fen)
    local b = self.b
    for s = 0, 119 do b[s] = OFF end
    for r = 0, 7 do for f = 0, 7 do b[sq(f, r)] = 0 end end
    local placement, side, castle, ep, half, full = fen:match("^(%S+)%s+(%S+)%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
    local rank, file = 7, 0
    for c in placement:gmatch(".") do
        if c == "/" then
            rank, file = rank - 1, 0
        elseif c:match("%d") then
            file = file + tonumber(c)
        else
            local kind = LETTER[c:lower()]
            local color = c:match("%u") and 1 or -1
            b[sq(file, rank)] = kind * color
            if kind == K then self.kings[color] = sq(file, rank) end
            file = file + 1
        end
    end
    self.side = side == "b" and -1 or 1
    self.castle = 0
    if castle:find("K") then self.castle = self.castle + WK end
    if castle:find("Q") then self.castle = self.castle + WQ end
    if castle:find("k") then self.castle = self.castle + BK end
    if castle:find("q") then self.castle = self.castle + BQ end
    self.ep = 0
    if ep and ep:match("^[a-h][1-8]$") then
        self.ep = sq(ep:byte(1) - 97, ep:byte(2) - 49)
    end
    self.half = tonumber(half) or 0
    self.fullmove = tonumber(full) or 1
    self.ply = 0
end

-- Is square s attacked by side `by`?
function Position:attacked(s, by)
    local b = self.b
    if by == 1 then
        if b[s - 9] == P or b[s - 11] == P then return true end
    else
        if b[s + 9] == -P or b[s + 11] == -P then return true end
    end
    local kn, kg = N * by, K * by
    for i = 1, 8 do
        if b[s + KNIGHT[i]] == kn then return true end
        if b[s + ROYAL[i]] == kg then return true end
    end
    local bi, ro, qu = B * by, R * by, Q * by
    for i = 1, 4 do
        local d = BISHOP[i]
        local t = s + d
        while b[t] == 0 do t = t + d end
        if b[t] == bi or b[t] == qu then return true end
        d = ROOK[i]
        t = s + d
        while b[t] == 0 do t = t + d end
        if b[t] == ro or b[t] == qu then return true end
    end
    return false
end

function Position:inCheck(side)
    side = side or self.side
    return self:attacked(self.kings[side], -side)
end

local function addPawnMove(list, n, from, to, promote, flag)
    if promote then
        for _, pr in ipairs({ Q, N, R, B }) do
            n = n + 1; list[n] = encode(from, to, pr, flag)
        end
    else
        n = n + 1; list[n] = encode(from, to, 0, flag)
    end
    return n
end

-- Pseudo-legal moves (may leave own king in check). Returns count.
function Position:generate(list, captures_only)
    local b, side = self.b, self.side
    local n = 0
    local fwd = 10 * side
    local start_rank = side == 1 and 1 or 6
    local last_rank = side == 1 and 7 or 0
    for s = 21, 98 do
        local p = b[s]
        if p ~= 0 and p ~= OFF and p * side > 0 then
            local kind = p * side
            if kind == P then
                local promote = rankOf(s + fwd) == last_rank
                local t = s + fwd
                if b[t] == 0 and (not captures_only or promote) then
                    n = addPawnMove(list, n, s, t, promote, 0)
                    if not captures_only and rankOf(s) == start_rank and b[t + fwd] == 0 then
                        n = n + 1; list[n] = encode(s, t + fwd, 0, FLAG_DOUBLE)
                    end
                end
                for _, d in ipairs({ fwd - 1, fwd + 1 }) do
                    t = s + d
                    local c = b[t]
                    if c ~= OFF and c * side < 0 then
                        n = addPawnMove(list, n, s, t, promote, 0)
                    elseif t == self.ep and self.ep ~= 0 then
                        n = n + 1; list[n] = encode(s, t, 0, FLAG_EP)
                    end
                end
            elseif kind == N or kind == K then
                local dirs = kind == N and KNIGHT or ROYAL
                for i = 1, 8 do
                    local t = s + dirs[i]
                    local c = b[t]
                    if c ~= OFF and (c * side < 0 or (c == 0 and not captures_only)) then
                        n = n + 1; list[n] = encode(s, t)
                    end
                end
            else
                local dirs = kind == B and BISHOP or kind == R and ROOK or ROYAL
                for i = 1, #dirs do
                    local d = dirs[i]
                    local t = s + d
                    while b[t] == 0 do
                        if not captures_only then n = n + 1; list[n] = encode(s, t) end
                        t = t + d
                    end
                    local c = b[t]
                    if c ~= OFF and c * side < 0 then
                        n = n + 1; list[n] = encode(s, t)
                    end
                end
            end
        end
    end
    if not captures_only then
        -- Castling: king and rook unmoved (rights), squares between empty,
        -- king not in check and not passing through or landing on an attacked square.
        local e = side == 1 and sq(4, 0) or sq(4, 7)
        local ks, qs = side == 1 and WK or BK, side == 1 and WQ or BQ
        if band(self.castle, ks + qs) ~= 0 and b[e] == K * side and not self:attacked(e, -side) then
            if band(self.castle, ks) ~= 0 and b[e + 1] == 0 and b[e + 2] == 0 and b[e + 3] == R * side
                and not self:attacked(e + 1, -side) and not self:attacked(e + 2, -side) then
                n = n + 1; list[n] = encode(e, e + 2, 0, FLAG_CASTLE)
            end
            if band(self.castle, qs) ~= 0 and b[e - 1] == 0 and b[e - 2] == 0 and b[e - 3] == 0 and b[e - 4] == R * side
                and not self:attacked(e - 1, -side) and not self:attacked(e - 2, -side) then
                n = n + 1; list[n] = encode(e, e - 2, 0, FLAG_CASTLE)
            end
        end
    end
    return n
end

function Position:make(m)
    local b, side = self.b, self.side
    local from, to, promo, flag = mFrom(m), mTo(m), mPromo(m), mFlag(m)
    local p = b[from]
    local cap = b[to]
    local ply = self.ply + 1
    self.ply = ply
    self.stack[ply] = { cap, self.castle, self.ep, self.half }
    if flag == FLAG_EP then
        b[to - 10 * side] = 0
        cap = -P * side
    end
    b[to] = promo > 0 and promo * side or p
    b[from] = 0
    if flag == FLAG_CASTLE then
        if to > from then
            b[to + 1], b[to - 1] = 0, R * side
        else
            b[to - 2], b[to + 1] = 0, R * side
        end
    end
    if p == K * side then self.kings[side] = to end
    self.ep = flag == FLAG_DOUBLE and (from + to) / 2 or 0
    self.castle = band(self.castle, CASTLE_MASK[from], CASTLE_MASK[to])
    if p == P * side or cap ~= 0 then self.half = 0 else self.half = self.half + 1 end
    if side == -1 then self.fullmove = self.fullmove + 1 end
    self.side = -side
end

function Position:unmake(m)
    local b = self.b
    local side = -self.side
    self.side = side
    local from, to, promo, flag = mFrom(m), mTo(m), mPromo(m), mFlag(m)
    local u = self.stack[self.ply]
    self.stack[self.ply] = nil
    self.ply = self.ply - 1
    local p = promo > 0 and P * side or b[to]
    b[from] = p
    if flag == FLAG_EP then
        b[to] = 0
        b[to - 10 * side] = -P * side
    else
        b[to] = u[1]
    end
    if flag == FLAG_CASTLE then
        if to > from then
            b[to - 1], b[to + 1] = 0, R * side
        else
            b[to + 1], b[to - 2] = 0, R * side
        end
    end
    if p == K * side then self.kings[side] = from end
    self.castle, self.ep, self.half = u[2], u[3], u[4]
    if side == -1 then self.fullmove = self.fullmove - 1 end
end

-- Leaves own king safe?
function Position:tryMove(m)
    local side = self.side
    self:make(m)
    local ok = not self:attacked(self.kings[side], -side)
    if not ok then self:unmake(m) end
    return ok
end

function Position:legalMoves()
    local list, out = {}, {}
    local n = self:generate(list)
    for i = 1, n do
        if self:tryMove(list[i]) then
            self:unmake(list[i])
            out[#out + 1] = list[i]
        end
    end
    return out
end

function Position:perft(depth)
    if depth == 0 then return 1 end
    local list = {}
    local n = self:generate(list)
    local total = 0
    for i = 1, n do
        if self:tryMove(list[i]) then
            total = total + self:perft(depth - 1)
            self:unmake(list[i])
        end
    end
    return total
end

-- Position identity for repetition: placement, side, castling, en passant.
-- The en passant square only counts when a capture there is actually possible.
function Position:key()
    local b, parts = self.b, {}
    for s = 21, 98 do
        local p = b[s]
        if p ~= OFF then parts[#parts + 1] = string.char(p + 72) end
    end
    local ep = 0
    if self.ep ~= 0 then
        local fwd = 10 * self.side
        if b[self.ep - fwd - 1] == P * self.side or b[self.ep - fwd + 1] == P * self.side then ep = self.ep end
    end
    return table.concat(parts) .. self.side .. ":" .. self.castle .. ":" .. ep
end

-- Neither side can possibly mate: K v K, K+minor v K, K+B v K+B with same-coloured bishops.
function Position:insufficientMaterial()
    local minors, bishop_colors = {}, {}
    for s = 21, 98 do
        local p = self.b[s]
        if p ~= 0 and p ~= OFF then
            local kind = math.abs(p)
            if kind == P or kind == R or kind == Q then return false end
            if kind == N or kind == B then
                minors[#minors + 1] = kind
                if kind == B then bishop_colors[#bishop_colors + 1] = (fileOf(s) + rankOf(s)) % 2 end
            end
        end
    end
    if #minors <= 1 then return true end
    if #minors == #bishop_colors then
        for i = 2, #bishop_colors do
            if bishop_colors[i] ~= bishop_colors[1] then return false end
        end
        return true
    end
    return false
end

-- Standard algebraic notation, e.g. "Nf3", "exd5", "O-O", "e8=Q+". Call before making the move.
function Position:san(m, legal)
    local b = self.b
    local from, to, promo, flag = mFrom(m), mTo(m), mPromo(m), mFlag(m)
    local kind = math.abs(b[from])
    local function name(s) return string.char(97 + fileOf(s)) .. (rankOf(s) + 1) end
    local s
    if flag == FLAG_CASTLE then
        s = to > from and "O-O" or "O-O-O"
    else
        local capture = b[to] ~= 0 or flag == FLAG_EP
        if kind == P then
            s = (capture and string.char(97 + fileOf(from)) .. "x" or "") .. name(to)
            if promo > 0 then s = s .. "=" .. ("PNBRQK"):sub(promo, promo) end
        else
            s = ("PNBRQK"):sub(kind, kind)
            local same_file, same_rank, ambiguous = false, false, false
            for _, o in ipairs(legal or self:legalMoves()) do
                local of = mFrom(o)
                if o ~= m and mTo(o) == to and of ~= from and math.abs(b[of]) == kind then
                    ambiguous = true
                    if fileOf(of) == fileOf(from) then same_file = true end
                    if rankOf(of) == rankOf(from) then same_rank = true end
                end
            end
            if ambiguous then
                if not same_file then s = s .. string.char(97 + fileOf(from))
                elseif not same_rank then s = s .. (rankOf(from) + 1)
                else s = s .. name(from) end
            end
            s = s .. (capture and "x" or "") .. name(to)
        end
    end
    self:make(m)
    if self:inCheck() then
        s = s .. (#self:legalMoves() == 0 and "#" or "+")
    end
    self:unmake(m)
    return s
end

------------------------------------------------------------------------------
-- Evaluation: material plus piece-square tables (Michniewski's simplified tables).

local VALUE = { 100, 320, 330, 500, 900, 0 }
Engine.VALUE = VALUE

-- Rows from rank 8 down to rank 1, from white's point of view.
local PST_ROWS = {
    [P] = {
        0, 0, 0, 0, 0, 0, 0, 0,
        50, 50, 50, 50, 50, 50, 50, 50,
        10, 10, 20, 30, 30, 20, 10, 10,
        5, 5, 10, 25, 25, 10, 5, 5,
        0, 0, 0, 20, 20, 0, 0, 0,
        5, -5, -10, 0, 0, -10, -5, 5,
        5, 10, 10, -20, -20, 10, 10, 5,
        0, 0, 0, 0, 0, 0, 0, 0 },
    [N] = {
        -50, -40, -30, -30, -30, -30, -40, -50,
        -40, -20, 0, 0, 0, 0, -20, -40,
        -30, 0, 10, 15, 15, 10, 0, -30,
        -30, 5, 15, 20, 20, 15, 5, -30,
        -30, 0, 15, 20, 20, 15, 0, -30,
        -30, 5, 10, 15, 15, 10, 5, -30,
        -40, -20, 0, 5, 5, 0, -20, -40,
        -50, -40, -30, -30, -30, -30, -40, -50 },
    [B] = {
        -20, -10, -10, -10, -10, -10, -10, -20,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -10, 0, 5, 10, 10, 5, 0, -10,
        -10, 5, 5, 10, 10, 5, 5, -10,
        -10, 0, 10, 10, 10, 10, 0, -10,
        -10, 10, 10, 10, 10, 10, 10, -10,
        -10, 5, 0, 0, 0, 0, 5, -10,
        -20, -10, -10, -10, -10, -10, -10, -20 },
    [R] = {
        0, 0, 0, 0, 0, 0, 0, 0,
        5, 10, 10, 10, 10, 10, 10, 5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        0, 0, 0, 5, 5, 0, 0, 0 },
    [Q] = {
        -20, -10, -10, -5, -5, -10, -10, -20,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -10, 0, 5, 5, 5, 5, 0, -10,
        -5, 0, 5, 5, 5, 5, 0, -5,
        0, 0, 5, 5, 5, 5, 0, -5,
        -10, 5, 5, 5, 5, 5, 0, -10,
        -10, 0, 5, 0, 0, 0, 0, -10,
        -20, -10, -10, -5, -5, -10, -10, -20 },
    [K] = { -- middlegame
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -20, -30, -30, -40, -40, -30, -30, -20,
        -10, -20, -20, -20, -20, -20, -20, -10,
        20, 20, 0, 0, 0, 0, 20, 20,
        20, 30, 10, 0, 0, 10, 30, 20 },
}
local KING_END_ROWS = {
    -50, -40, -30, -20, -20, -30, -40, -50,
    -30, -20, -10, 0, 0, -10, -20, -30,
    -30, -10, 20, 30, 30, 20, -10, -30,
    -30, -10, 30, 40, 40, 30, -10, -30,
    -30, -10, 30, 40, 40, 30, -10, -30,
    -30, -10, 20, 30, 30, 20, -10, -30,
    -30, -30, 0, 0, 0, 0, -30, -30,
    -50, -30, -30, -30, -30, -30, -30, -50 }

-- PST[kind][color][square], scores from that piece's own point of view.
local PST, KING_END = {}, { [1] = {}, [-1] = {} }
for kind = 1, 6 do
    PST[kind] = { [1] = {}, [-1] = {} }
    for r = 0, 7 do
        for f = 0, 7 do
            PST[kind][1][sq(f, r)] = PST_ROWS[kind][(7 - r) * 8 + f + 1]
            PST[kind][-1][sq(f, r)] = PST_ROWS[kind][r * 8 + f + 1]
            if kind == K then
                KING_END[1][sq(f, r)] = KING_END_ROWS[(7 - r) * 8 + f + 1]
                KING_END[-1][sq(f, r)] = KING_END_ROWS[r * 8 + f + 1]
            end
        end
    end
end

-- Score from the side to move's point of view.
function Position:evaluate()
    local b = self.b
    local score, queens, minors = 0, 0, 0
    for s = 21, 98 do
        local p = b[s]
        if p ~= 0 and p ~= OFF then
            local color = p > 0 and 1 or -1
            local kind = p * color
            if kind == Q then queens = queens + 1 elseif kind ~= P and kind ~= K then minors = minors + 1 end
            if kind ~= K then score = score + color * (VALUE[kind] + PST[kind][color][s]) end
        end
    end
    -- Endgame once queens are off or almost nothing else is left: kings centralise.
    local endgame = queens == 0 or (queens <= 2 and minors <= 2)
    local kt = endgame and KING_END or PST[K]
    score = score + kt[1][self.kings[1]] - kt[-1][self.kings[-1]]
    return score * self.side
end

------------------------------------------------------------------------------
-- Search: iterative deepening negamax with alpha-beta, quiescence, MVV-LVA ordering.

local MATE = 100000
Engine.MATE = MATE

local Search = {}
Search.__index = Search

local function now() return os.clock() end

function Search:timeUp()
    self.nodes = self.nodes + 1
    if self.nodes % 512 == 0 and now() > self.deadline then self.stopped = true end
    return self.stopped
end

function Search:orderScore(pos, m, ply)
    local b = pos.b
    local cap = b[mTo(m)]
    local score = 0
    if cap ~= 0 then
        score = 10000 + VALUE[math.abs(cap)] * 10 - VALUE[math.abs(b[mFrom(m)])] / 10
    elseif mFlag(m) == FLAG_EP then
        score = 10000 + 1000 - 10
    end
    if mPromo(m) == Q then score = score + 9000 end
    if self.killers[ply] and (self.killers[ply][1] == m or self.killers[ply][2] == m) then
        score = score + 5000
    end
    return score
end

function Search:sorted(pos, list, n, ply, first)
    local scores = {}
    for i = 1, n do
        scores[i] = list[i] == first and 1e9 or self:orderScore(pos, list[i], ply)
    end
    -- Insertion sort, best first (lists are short).
    for i = 2, n do
        local m, s = list[i], scores[i]
        local j = i - 1
        while j >= 1 and scores[j] < s do
            list[j + 1], scores[j + 1] = list[j], scores[j]
            j = j - 1
        end
        list[j + 1], scores[j + 1] = m, s
    end
end

function Search:quiesce(pos, alpha, beta, ply)
    if self:timeUp() then return 0 end
    local stand = pos:evaluate()
    if stand >= beta then return stand end
    if stand > alpha then alpha = stand end
    local list = {}
    local n = pos:generate(list, true)
    self:sorted(pos, list, n, ply)
    for i = 1, n do
        local m = list[i]
        if pos:tryMove(m) then
            local score = -self:quiesce(pos, -beta, -alpha, ply + 1)
            pos:unmake(m)
            if self.stopped then return 0 end
            if score >= beta then return score end
            if score > alpha then alpha = score end
        end
    end
    return alpha
end

function Search:negamax(pos, depth, alpha, beta, ply)
    if self:timeUp() then return 0 end
    if ply > 0 then
        if pos.half >= 100 then return 0 end
        -- Repetition of a position in the game or the current line counts as a draw.
        if self.seen[pos:key()] then return 0 end
    end
    local in_check = pos:inCheck()
    if in_check then depth = depth + 1 end
    if depth <= 0 then return self:quiesce(pos, alpha, beta, ply) end
    local list = {}
    local n = pos:generate(list)
    self:sorted(pos, list, n, ply, ply == 0 and self.best or nil)
    local legal, best = 0, -MATE - 1
    local key = ply > 0 and pos:key()
    if key then self.seen[key] = true end
    for i = 1, n do
        local m = list[i]
        if pos:tryMove(m) then
            legal = legal + 1
            local score = -self:negamax(pos, depth - 1, -beta, -alpha, ply + 1)
            pos:unmake(m)
            if self.stopped then break end
            if score > best then
                best = score
                if ply == 0 then self.iter_best = m end
            end
            if score > alpha then alpha = score end
            if alpha >= beta then
                if pos.b[mTo(m)] == 0 then
                    local k = self.killers[ply] or {}
                    if k[1] ~= m then k[2] = k[1]; k[1] = m end
                    self.killers[ply] = k
                end
                break
            end
        end
    end
    if key then self.seen[key] = nil end
    if self.stopped then return 0 end
    if legal == 0 then return in_check and -(MATE - ply) or 0 end
    return best
end

-- Best move for the side to move. opts: max_depth, time (seconds), noise (random centipawns
-- added at the root to weaken play), history (keys of earlier positions, for repetition).
function Engine.think(pos, opts)
    local s = setmetatable({ nodes = 0, killers = {}, seen = {}, stopped = false }, Search)
    for _, k in ipairs(opts.history or {}) do s.seen[k] = true end
    s.deadline = now() + (opts.time or 1)
    local legal = pos:legalMoves()
    if #legal == 0 then return nil end
    if #legal == 1 then return legal[1] end
    if (opts.noise or 0) > 0 then
        -- Weak play: shallow search, then pick among moves near the best one.
        local scored = {}
        for _, m in ipairs(legal) do
            pos:make(m)
            local score = -s:negamax(pos, (opts.max_depth or 1) - 1, -MATE - 1, MATE + 1, 1)
            pos:unmake(m)
            scored[#scored + 1] = { m, score + math.random(0, opts.noise) }
        end
        table.sort(scored, function(a, c) return a[2] > c[2] end)
        return scored[1][1]
    end
    local best = legal[1]
    for depth = 1, opts.max_depth or 64 do
        s.iter_best = nil
        s.best = best
        local score = s:negamax(pos, depth, -MATE - 1, MATE + 1, 0)
        if s.stopped then
            -- A partial iteration that already searched the previous best first is still usable.
            if s.iter_best then best = s.iter_best end
            break
        end
        best = s.iter_best or best
        if math.abs(score) > MATE - 100 then break end -- forced mate found
        if now() > s.deadline then break end
    end
    return best
end

return Engine
