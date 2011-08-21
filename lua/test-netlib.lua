local luasimplex = require("luasimplex")
local mps = require("luasimplex.mps")
local rsm = require("luasimplex.rsm")
local monitor = require("luasimplex.monitor")
local lfs = require("lfs")


-- Answers to netlib problems --------------------------------------------------

answers =
{
  ["25FV47"] = 5.5018458883E+03,
  ["80BAU3B"] = 9.8723216072E+05,
  ["ADLITTLE"] = 2.2549496316E+05,
  ["AFIRO"] = -4.6475314286E+02,
  ["AGG"] = -3.5991767287E+07,
  ["AGG2"] = -2.0239252356E+07,
  ["AGG3"] = 1.0312115935E+07,
  ["BANDM"] = -1.5862801845E+02,
  ["BEACONFD"] = 3.3592485807E+04,
  ["BLEND"] = -3.0812149846E+01,
  ["BNL1"] = 1.9776292856E+03,
  ["BNL2"] = 1.8112365404E+03,
  ["BOEING1"] = -3.3521356751E+02,
  ["BOEING2"] = -3.1501872802E+02,
  ["BORE3D"] = 1.3730803942E+03,
  ["BRANDY"] = 1.5185098965E+03,
  ["CAPRI"] = 2.6900129138E+03,
  ["CYCLE"] = -5.2263930249E+00,
  ["CZPROB"] = 2.1851966989E+06,
  ["D2Q06C"] = 1.2278423615E+05,
  ["D6CUBE"] = 3.1549166667E+02,
  ["DEGEN2"] = -1.4351780000E+03,
  ["DEGEN3"] = -9.8729400000E+02,
  ["DFL001"] = 1.12664E+07,
  ["E226"] = -1.8751929066E+01,
  ["ETAMACRO"] = -7.5571521774E+02,
  ["FFFFF800"] = 5.5567961165E+05,
  ["FINNIS"] = 1.7279096547E+05,
  ["FIT1D"] = -9.1463780924E+03,
  ["FIT1P"] = 9.1463780924E+03,
  ["FIT2D"] = -6.8464293294E+04,
  ["FIT2P"] = 6.8464293232E+04,
  ["FORPLAN"] = -6.6421873953E+02,
  ["GANGES"] = -1.0958636356E+05,
  ["GFRD-PNC"] = 6.9022359995E+06,
  ["GREENBEA"] = -7.2462405908E+07,
  ["GREENBEB"] = -4.3021476065E+06,
  ["GROW15"] = -1.0687094129E+08,
  ["GROW22"] = -1.6083433648E+08,
  ["GROW7"] = -4.7787811815E+07,
  ["ISRAEL"] = -8.9664482186E+05,
  ["KB2"] = -1.7499001299E+03,
  ["LOTFI"] = -2.5264706062E+01,
  ["MAROS"] = -5.8063743701E+04,
  ["MAROS-R7"] = 1.4971851665E+06,
  ["MODSZK1"] = 3.2061972906E+02,
  ["NESM"] = 1.4076073035E+07,
  ["PEROLD"] = -9.3807580773E+03,
  ["PILOT"] = -5.5740430007E+02,
  ["PILOT.JA"] = -6.1131344111E+03,
  ["PILOT.WE"] = -2.7201027439E+06,
  ["PILOT4"] = -2.5811392641E+03,
  ["PILOT87"] = 3.0171072827E+02,
  ["PILOTNOV"] = -4.4972761882E+03,
  ["QAP8"] = 2.0350000000E+02,
  ["QAP12"] = 5.2289435056E+02,
  ["QAP15"] = 1.0409940410E+03,
  ["RECIPE"] = -2.6661600000E+02,
  ["SC105"] = -5.2202061212E+01,
  ["SC205"] = -5.2202061212E+01,
  ["SC50A"] = -6.4575077059E+01,
  ["SC50B"] = -7.0000000000E+01,
  ["SCAGR25"] = -1.4753433061E+07,
  ["SCAGR7"] = -2.3313892548E+06,
  ["SCFXM1"] = 1.8416759028E+04,
  ["SCFXM2"] = 3.6660261565E+04,
  ["SCFXM3"] = 5.4901254550E+04,
  ["SCORPION"] = 1.8781248227E+03,
  ["SCRS8"] = 9.0429998619E+02,
  ["SCSD1"] = 8.6666666743E+00,
  ["SCSD6"] = 5.0500000078E+01,
  ["SCSD8"] = 9.0499999993E+02,
  ["SCTAP1"] = 1.4122500000E+03,
  ["SCTAP2"] = 1.7248071429E+03,
  ["SCTAP3"] = 1.4240000000E+03,
  ["SEBA"] = 1.5711600000E+04,
  ["SHARE1B"] = -7.6589318579E+04,
  ["SHARE2B"] = -4.1573224074E+02,
  ["SHELL"] = 1.2088253460E+09,
  ["SHIP04L"] = 1.7933245380E+06,
  ["SHIP04S"] = 1.7987147004E+06,
  ["SHIP08L"] = 1.9090552114E+06,
  ["SHIP08S"] = 1.9200982105E+06,
  ["SHIP12L"] = 1.4701879193E+06,
  ["SHIP12S"] = 1.4892361344E+06,
  ["SIERRA"] = 1.5394362184E+07,
  ["STAIR"] = -2.5126695119E+02,
  ["STANDATA"] = 1.2576995000E+03,
  ["STANDMPS"] = 1.4060175000E+03,
  ["STOCFOR1"] = -4.1131976219E+04,
  ["STOCFOR2"] = -3.9024408538E+04,
  ["STOCFOR3"] = -3.9976661576E+04,
  ["TRUSS"] = 4.5881584719E+05,
  ["TUFF"] = 2.9214776509E-01,
  ["VTP.BASE"] = 1.2983146246E+05,
  ["WOOD1P"] = 1.4429024116E+00,
  ["WOODW"] = 1.3044763331E+00,
}


-- Main ------------------------------------------------------------------------

-- read args
local choices, chosen, test_dir, speed, diagnose = 0, {}, "../../netlib-test-data/"
local i = 1
while i <= #arg do
  if arg[i] == "--fast" then
    speed = "fast"
  elseif arg[i] == "--check" then
    speed = "check"
  elseif arg[i] == "--display" then
    speed = "display"
  elseif arg[i] == "--diagnose" then
    diagnose = true
  elseif arg[i] == "--test-dir" then
    i = i + 1
    test_dir = arg[i]
  elseif arg[i] == "--help" then
    io.stderr:write("Usage: ", arg[0], "[--fast|--check|--display] [--diagnose] [--test-dir <location of netlib test data] [<test name>]\n")
  else
    chosen[arg[i]:upper()] = true
    choices = choices + 1
  end
  i = i + 1
end

if choices > 0 then
  if choices > 1 then
    if not speed then speed = "check" end
  else
    if not speed then speed = "display" end
  end
  if diagnose == nil then diagnose = true end
else
  if not speed then speed = "check" end
end


-- read tests
local tests = {}

for fn in lfs.dir(test_dir) do
  local name = fn:match("(.+).txt")
  if name then
    name = name:upper()
    local answer = answers[name]
    if answer and (choices == 0 or chosen[name]) then
      tests[#tests+1] = { fn = fn, name = name, answer = answer, size = lfs.attributes(test_dir..fn, "size") }
    end
  end
end    
table.sort(tests, function(a, b) return a.size < b.size end)
if #tests == 0 then
  io.stderr:write("No test files found.  You might want to use the --test-dir option\n")
end


-- run tests
io.stderr:write(("%-10s\t%10s\t%12s\t%10s\t%12s\t%12s\t%12s\t%12s\t%12s\t%8s\n"):format("Test", "Variables", "Constraints", "Nonzeros", "Expect", "Obtained", "Abs diff", "Rel diff", "Iterations", "Time (s)"))

for _, t in ipairs(tests) do
  io.stderr:write(("%-10s\t"):format(t.name))
  local f = io.open(test_dir..t.fn)
  local status, M = pcall(mps.read, f)
  f:close()

  if not status then
    io.stderr:write("ERROR: ", M, "\n")
    M = nil
  else

    if speed == "display" then
      mps.write(M)
    end
    io.stderr:write(("% 10d\t% 12d\t% 10d\t%12g\t"):format(M.nvars, M.nrows, M.nonzeroes, t.answer))
    local S = {}
    if speed == "check" then
      S.monitor = monitor.check
    elseif speed == "display" then
      S.monitor = monitor.display
    end

    local status, o, time = true

    local I = luasimplex.new_instance(M.nrows, M.nvars, use_c_structs)
    rsm.initialise(M, I, S)

    if speed == "display" then
      o, _, iterations = rsm.solve(M, I, S)
    elseif speed == "check" then
      status, o, _, iterations = pcall(rsm.solve, M, I, S)
    else
      time = os.clock()
      status, o, _, iterations = pcall(rsm.solve, M, I, S)
      time = os.clock() - time
    end
    if status then
      io.stderr:write(("% 12g\t% 12g\t% 12g\t% 12d\t")
        :format(o, math.abs(t.answer - o), math.abs((t.answer - o)/t.answer), iterations))
      if time then
        io.stderr:write(("%8.4f"):format(time))
      end
      io.stderr:write("\n")
    else
      if type(o) == "table" and diagnose then
        monitor.diagnose(o.M, o.I, o.S, o.error)
      end
      io.stderr:write("ERROR: ", tostring(o), "\n")
    end
  end
end


-- EOF -------------------------------------------------------------------------

