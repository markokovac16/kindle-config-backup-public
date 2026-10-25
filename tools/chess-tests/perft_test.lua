package.path = arg[1] .. "/?.lua;" .. package.path
local E = require("chess_engine")
local tests = {
    { "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", { 20, 400, 8902, 197281 } },
    { "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", { 48, 2039, 97862, 4085603 } },
    { "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", { 14, 191, 2812, 43238, 674624 } },
    { "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", { 6, 264, 9467, 422333 } },
    { "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", { 44, 1486, 62379, 2103487 } },
    { "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", { 46, 2079, 89890, 3894594 } },
}
local ok = true
for i, t in ipairs(tests) do
    local pos = E.newPosition(t[1])
    for d, want in ipairs(t[2]) do
        local t0 = os.clock()
        local got = pos:perft(d)
        local pass = got == want
        ok = ok and pass
        print(string.format("pos%d depth %d: %d (want %d) %s  %.2fs", i, d, got, want, pass and "OK" or "FAIL", os.clock() - t0))
    end
end
print(ok and "ALL PERFT OK" or "PERFT FAILURES")
