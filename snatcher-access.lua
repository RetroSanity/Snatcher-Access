-- Snatcher Access, version 0.23
-- Screen reader support for Snatcher (USA, Sega CD) in BizHawk (Genesis Plus GX core).
-- Reads dialogue with speaker names, every command menu, the title/options/backup RAM
-- screens, and announces targets during shooting scenes with speech and positional sounds.
-- Read-only: the script never changes game memory or presses buttons for you.
--
-- Memory map (all in the "CD PRG RAM" domain, found by studying the game):
--   0x1E000          current scene text bank (plain ASCII, FF = end, F2 = new line,
--                    F6 = new page, EC/EE/F0 = button letter, F8-FE = colour codes)
--   0x97D0 (word)    offset of the message being shown, from 0x1E000
--   0x9746 (word)    text printer position (same base)
--   0x9740           text state; becomes 2 each time a new box of text starts printing
--   0x9744           speaker index (0 = none)
--   0x788D           1 while a command menu is on screen
--   0x9852/0x9853    menu capacity / item count, then word offsets of item names from 0x1E000
--   0x9710           menu cursor
--   0x78BA (word)    button layout 0-5 (Options > Controls)
--   0x78E9           shooting scene phase: 1 getting ready, 2 targets coming, 3-5 ending, 0 none
--   0x892D           life during shooting scenes
--   0x8400 + n*0x50  shooting object n (n = grid cell 0-8): +1 active, +0x24 state
--                    (high nibble 1 = enemy/Snatcher, 2 = civilian; low nibble 0-2 appearing,
--                    3-5 leaving, 7 destroyed)
--   0x7897/0x7899    system screen (0/2 backup RAM choice, 9/2 title, 0B options)

local A = {version = '0.23', frame = 0, hooks = {}}
local source = debug.getinfo(1, 'S').source:sub(2)
local folder = source:match('^(.*[/\\])') or './'
local D = 'CD PRG RAM'

local log = io.open(folder .. 'snatcher-speech.log', 'a')

-- snatcher-debug.log is rewritten every time the script starts. It records how speech was
-- set up and anything that went wrong, so a player with no speech can send it in.
local dbglog = io.open(folder .. 'snatcher-debug.log', 'w')
local function note(s)
	console.log(s)
	if dbglog then dbglog:write(os.date('%Y-%m-%d %H:%M:%S '), tostring(s), '\n'); dbglog:flush() end
end
note('Snatcher Access ' .. A.version .. ' starting from ' .. folder)
pcall(function() note('BizHawk ' .. tostring(client.getversion())) end)
note('luanet: ' .. tostring(luanet ~= nil) .. ', BizHawk speech module: ' .. tostring(speech ~= nil and speech.say ~= nil))
local last_said, last_message = '', ''

-- Speech ----------------------------------------------------------------------------------
-- 1. Prism (prism.dll), which talks to whichever screen reader is running (NVDA, JAWS,
--    Narrator, and others) or a Windows voice. Lua cannot load a DLL itself, so a tiny C#
--    bridge is compiled in memory by the .NET Framework that BizHawk runs on.
-- 2. BizHawk builds with their own speech module (speech.say).
-- 3. The Windows voice (SAPI) as a last resort.
local prism = nil
local function find_prism()
	local dirs = {folder, folder .. '..\\Snatcher Access\\'}
	pcall(function()
		luanet.load_assembly('mscorlib')
		local AppDomain = luanet.import_type('System.AppDomain')
		dirs[#dirs + 1] = AppDomain.CurrentDomain.BaseDirectory
	end)
	for _, d in ipairs(dirs) do
		local f = io.open(d .. 'prism.dll', 'rb')
		if f then f:close(); return d .. 'prism.dll' end
	end
	return nil
end
local function start_prism()
	if not luanet or SNATCHER_NO_PRISM then return nil end
	local dll = find_prism()
	if not dll then note('Prism: prism.dll not found next to the script or in the BizHawk folder'); return nil end
	note('Prism: using ' .. dll)
	dll = dll:gsub('/', '\\')
	luanet.load_assembly('System')
	local code = [[
using System; using System.Runtime.InteropServices; using System.Text;
public static class SnatcherPrism {
	const string D = @"DLLPATH";
	[DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr prism_init(IntPtr cfg);
	[DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr prism_registry_create_best(IntPtr ctx);
	[DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern int prism_backend_speak(IntPtr b, byte[] text, [MarshalAs(UnmanagedType.I1)] bool interrupt);
	[DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern int prism_backend_stop(IntPtr b);
	[DllImport(D, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr prism_backend_name(IntPtr b);
	static IntPtr ctx, backend;
	public static string Start() {
		ctx = prism_init(IntPtr.Zero);
		if (ctx == IntPtr.Zero) return null;
		backend = prism_registry_create_best(ctx);
		if (backend == IntPtr.Zero) return null;
		IntPtr n = prism_backend_name(backend);
		return n == IntPtr.Zero ? "speech" : Marshal.PtrToStringAnsi(n);
	}
	public static int Speak(string text, bool interrupt) {
		if (backend == IntPtr.Zero) return -1;
		return prism_backend_speak(backend, Encoding.UTF8.GetBytes(text + "\0"), interrupt);
	}
	public static int Stop() { return backend == IntPtr.Zero ? -1 : prism_backend_stop(backend); }
}]]
	code = code:gsub('DLLPATH', function() return dll end)
	local Provider = luanet.import_type('Microsoft.CSharp.CSharpCodeProvider')
	local Params = luanet.import_type('System.CodeDom.Compiler.CompilerParameters')
	local Array = luanet.import_type('System.Array')
	local TypeT = luanet.import_type('System.Type')
	local StringT = TypeT.GetType('System.String')
	local ObjectT = TypeT.GetType('System.Object')
	local params = Params()
	params.GenerateInMemory = true
	params.GenerateExecutable = false
	params.ReferencedAssemblies:Add('System.dll')
	local sources = Array.CreateInstance(StringT, 1)
	sources:SetValue(code, 0)
	local result = Provider():CompileAssemblyFromSource(params, sources)
	if result.Errors.HasErrors then
		local msg = '?'
		pcall(function() msg = tostring(result.Errors:get_Item(0)) end)
		note('Prism: bridge did not compile: ' .. msg)
		return nil
	end
	local t = result.CompiledAssembly:GetType('SnatcherPrism')
	local mSpeak, mStop = t:GetMethod('Speak'), t:GetMethod('Stop')
	local name = t:GetMethod('Start'):Invoke(nil, nil)
	if name == nil then note('Prism: started, but no screen reader or voice was available'); return nil end
	local args = Array.CreateInstance(ObjectT, 2)
	return {
		name = tostring(name),
		say = function(text, interrupt)
			args:SetValue(text, 0); args:SetValue(interrupt and true or false, 1)
			local r = tonumber(tostring(mSpeak:Invoke(nil, args)))
			if r ~= 0 then return false, 'error code ' .. tostring(r) end
			return true
		end,
		stop = function() mStop:Invoke(nil, nil) end,
	}
end
if SNATCHER_PRISM then
	prism = SNATCHER_PRISM   -- already started before an automatic update restarted the script
else
	local ok, p = pcall(start_prism)
	if ok and p then prism = p; SNATCHER_PRISM = p; note('Prism: speaking through ' .. p.name)
	elseif not ok then note('Prism: failed to start: ' .. tostring(p)) end
end

-- The Windows voice. BizHawk can only load System.Speech by its full name.
local sapi, sapiTried = nil, false
local function get_sapi()
	if sapi or sapiTried or not luanet then return sapi end
	sapiTried = true
	local ok, err = pcall(function()
		luanet.load_assembly('System.Speech, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35')
		local Synth = luanet.import_type('System.Speech.Synthesis.SpeechSynthesizer')
		sapi = Synth()
		sapi.Rate = 2
	end)
	if ok and sapi then note('Windows voice ready as a backup') else note('Windows voice unavailable: ' .. tostring(err)); sapi = nil end
	return sapi
end
if not prism and not (speech and speech.say) then get_sapi() end
local failures = 0
local function say(s, interrupt)
	if not s or s == '' then return end
	last_said = s
	console.log(s)
	if log then log:write(os.date('%H:%M:%S '), s, '\n'); log:flush() end
	if prism then
		local ok, spoke, why = pcall(prism.say, s, interrupt ~= false)
		if ok and spoke then return end
		failures = failures + 1
		if failures <= 5 then note('Prism could not speak (' .. tostring(ok and why or spoke) .. '); using a backup voice') end
	end
	if speech and speech.say then
		if interrupt == false then speech.say(s, false) else speech.say(s) end
	elseif get_sapi() then
		pcall(function()
			if interrupt ~= false then sapi:SpeakAsyncCancelAll() end
			sapi:SpeakAsync(s)
		end)
	end
end
local function stop_speech()
	if prism then pcall(prism.stop) end
	if speech and speech.stop then speech.stop()
	elseif sapi then pcall(function() sapi:SpeakAsyncCancelAll() end) end
end

-- Memory helpers ----------------------------------------------------------------------
local function u8(a) return memory.read_u8(a, D) end
local function u16(a) return memory.read_u16_be(a, D) end

if emu.getsystemid() ~= 'GEN' then
	console.log('Snatcher Access: this is not a Genesis or Sega CD game. Nothing was loaded.')
	if speech and speech.say then speech.say('Snatcher access needs the Sega CD version of Snatcher. Nothing was loaded.') end
	return
end
local okDomain = pcall(memory.read_u8, 0, D)
if not okDomain then
	say('Snatcher access could not find the Sega CD program memory. Load Snatcher, USA, Sega CD, with the Genesis Plus GX core.')
	return
end
if not prism and not (speech and speech.say) and not sapi then
	note('NO SPEECH: Prism, BizHawk speech and the Windows voice are all unavailable.')
end

-- Automatic updates ---------------------------------------------------------------------
-- When the script starts it asks GitHub for the newest published release of Snatcher Access.
-- If that release is newer than this script, it downloads the files listed in that release's
-- manifest.txt, checks each file's size, replaces the old files and restarts itself.
-- Only published releases are installed, never work in progress. To turn updates off, put a
-- file called no-update.txt next to this script. Nothing is changed if anything goes wrong.
local REPO = 'RetroSanity/Snatcher-Access'
local function update_log(s)
	note('Update: ' .. s)
	if log then log:write(os.date('%H:%M:%S '), 'Update: ', s, '\n'); log:flush() end
end
local function http_get(url, binary)
	luanet.load_assembly('System')
	local ServicePointManager = luanet.import_type('System.Net.ServicePointManager')
	pcall(function() ServicePointManager.SecurityProtocol = luanet.enum(luanet.import_type('System.Net.SecurityProtocolType'), 3072) end)
	local WebClient = luanet.import_type('System.Net.WebClient')
	local wc = WebClient()
	wc.Headers:Add('User-Agent', 'Snatcher-Access-updater')
	local ok, data = pcall(function() if binary then return wc:DownloadData(url) else return wc:DownloadString(url) end end)
	pcall(function() wc:Dispose() end)
	if not ok then error(tostring(data)) end
	return data
end
local function newer(a, b) return (tonumber(a) or 0) > (tonumber(b) or 0) end
local function check_updates()
	if not luanet then return false end
	local f = io.open(folder .. 'no-update.txt', 'r')
	if f then f:close(); update_log('turned off by no-update.txt'); return false end
	local json = http_get('https://api.github.com/repos/' .. REPO .. '/releases/latest')
	local tag = json:match('"tag_name"%s*:%s*"([^"]+)"')
	if not tag then update_log('no release found'); return false end
	local latest = tag:gsub('^[vV]', '')
	if not newer(latest, A.version) then return false end
	say('Downloading Snatcher Access ' .. latest .. '.')
	local base = 'https://raw.githubusercontent.com/' .. REPO .. '/' .. tag .. '/'
	local manifest = http_get(base .. 'manifest.txt')
	local files = {}
	for size, path in manifest:gmatch('file%s+(%d+)%s+([^\r\n]+)') do
		if not path:find('%.%.') and not path:find('^[/\\]') then files[#files + 1] = {path = path, size = tonumber(size)} end
	end
	if #files == 0 then update_log('empty manifest'); say('The update could not be downloaded.'); return false end
	local File = luanet.import_type('System.IO.File')
	local Directory = luanet.import_type('System.IO.Directory')
	local Path = luanet.import_type('System.IO.Path')
	-- Download everything first; only replace files once every download is complete and correct.
	local staged = {}
	for _, item in ipairs(files) do
		local data = http_get(base .. item.path, true)
		if data.Length ~= item.size then
			update_log(item.path .. ' has the wrong size (' .. tostring(data.Length) .. ' instead of ' .. item.size .. ')')
			say('The update could not be downloaded. Your current version is unchanged.')
			return false
		end
		local dest = folder .. item.path:gsub('/', '\\')
		staged[#staged + 1] = {dest = dest, data = data}
	end
	for _, s in ipairs(staged) do
		Directory.CreateDirectory(Path.GetDirectoryName(s.dest))
		File.WriteAllBytes(s.dest .. '.new', s.data)
	end
	for _, s in ipairs(staged) do File.Copy(s.dest .. '.new', s.dest, true); File.Delete(s.dest .. '.new') end
	update_log('updated from ' .. A.version .. ' to ' .. latest)
	say('Updated to Snatcher Access ' .. latest .. '. Restarting.')
	return true
end
if not SNATCHER_UPDATED then
	local ok, result = pcall(check_updates)
	if not ok then update_log('check failed: ' .. tostring(result))
	elseif result then
		SNATCHER_UPDATED = true
		if log then log:close(); log = nil end
		if sapi then pcall(function() sapi:Dispose() end); sapi = nil end
		return dofile(source)
	end
end

-- Sounds --------------------------------------------------------------------------------
A.beeps = true      -- positional target sounds
A.voice = true      -- spoken target positions
A.aim = true        -- aim assist: draw the blaster and point it at the oldest enemy
-- Sounds live next to the script, or in D:\Games\Pokemon\Snatcher Access\sounds when the
-- script is run from another folder (such as the Lua folder).
local function find_sounds()
	for _, dir in ipairs({folder .. 'sounds\\', folder .. '..\\Snatcher Access\\sounds\\',
			'D:\\Games\\Pokemon\\Snatcher Access\\sounds\\'}) do
		local f = io.open(dir .. 'enemy0.wav', 'rb')
		if f then f:close(); return dir end
	end
	return folder .. 'sounds\\'
end
local SOUNDS = find_sounds()
local audioOK, audio = pcall(function()
	if not luanet then return nil end
	luanet.load_assembly('System')
	local SoundPlayer = luanet.import_type('System.Media.SoundPlayer')
	local t = {}
	for _, kind in ipairs({'enemy', 'civilian'}) do
		t[kind] = {}
		for cell = 0, 8 do
			local p = SoundPlayer(SOUNDS .. kind .. cell .. '.wav')
			p:Load(); t[kind][cell] = p
		end
	end
	local hit = SoundPlayer(SOUNDS .. 'hit.wav'); hit:Load(); t.hit = hit
	local okKill, kill = pcall(function() local k = SoundPlayer(SOUNDS .. 'kill.wav'); k:Load(); return k end)
	if okKill then t.kill = kill end
	return {
		play = function(kind, cell) local p = t[kind] and t[kind][cell]; if p then p:Play() end end,
		hit = function() t.hit:Play() end,
		kill = function() if t.kill then t.kill:Play() end end,
		close = function()
			for _, kind in ipairs({'enemy', 'civilian'}) do for c = 0, 8 do pcall(function() t[kind][c]:Dispose() end) end end
			pcall(function() t.hit:Dispose() end)
			pcall(function() if t.kill then t.kill:Dispose() end end)
		end,
	}
end)
if not audioOK or not audio then
	note('Target sounds unavailable: ' .. tostring(audio))
	audio = nil
end

-- Text ---------------------------------------------------------------------------------
local BANK = 0x1E000
local BTN = {[0xEC] = {'A', 'A', 'B', 'C', 'C', 'B'},   -- draw blaster
             [0xEE] = {'B', 'C', 'A', 'A', 'B', 'C'},   -- cancel
             [0xF0] = {'C', 'B', 'C', 'B', 'A', 'A'}}   -- select / shoot
local NAMES = {'Metal Gear', 'Gillian', 'Mika', 'Togo', 'Driver', 'Chief', 'Harry', 'Napoleon', 'Jamie',
	'Employee', 'Man', 'Stella', 'Christy', 'Woman', 'Fukui the second', 'Miss Hayasaka', 'Mr. Togo',
	'Mr. Nakamura', 'Nakamura', 'Mr. Sasaki', 'Jeremy', 'Chie', 'Kiwi', 'Mr. Kushibuchi', 'Mr. Inamura',
	'Jordan', 'Konami', 'Vangie', 'Katrina', 'Passerby', 'P.A.', 'Doorman', 'Manager', 'Isabella',
	'Sparkster', 'Goemon', 'Mr. Ueda', 'Contra', 'Castlevania pair', 'Customer', 'Dracula',
	'Simon Belmont', 'Freeman', 'Ivan', 'Lisa', 'Parrot', 'Random'}

local function tidy(s)
	return (s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Reads a message from the text bank. Returns plain text.
local function text_at(off, maxlen)
	local a = BANK + off
	if a < BANK or a >= 0x7FFF0 then return '' end
	local n = math.min(maxlen or 1200, 0x80000 - a)
	local bytes = memory.read_bytes_as_array(a, n, D)
	local cfg = u16(0x78BA)
	local out = {}
	for i = 1, #bytes do
		local b = bytes[i]
		if b == 0xFF then break
		elseif b == 0xF2 or b == 0xF6 then out[#out + 1] = ' '
		elseif BTN[b] then out[#out + 1] = (BTN[b][cfg + 1] or '?')
		elseif b >= 0x20 and b < 0x7F then out[#out + 1] = string.char(b) end
	end
	return tidy(table.concat(out))
end

local function speaker()
	local i = u8(0x9744)
	return NAMES[i] or ''
end

-- Menu items are stored in capitals; title case reads better with every speech synthesiser.
local function title_case(s)
	s = s:lower():gsub("(%a)([%w']*)", function(f, r) return f:upper() .. r end)
	s = s:gsub("I%.d%.", "I.D."):gsub(" Of ", " of "):gsub(" The ", " the "):gsub(" To ", " to ")
	s = s:gsub("'S ", "'s "):gsub("'S$", "'s")
	for _, ac in ipairs({'HQ', 'TV', 'CD', 'DNA', 'OK'}) do
		local low = ac:sub(1, 1) .. ac:sub(2):lower()
		s = s:gsub('%f[%a]' .. low .. '%f[%A]', ac)
	end
	return s
end

local function menu_items()
	local count = u8(0x9853)
	if count == 0 or count > 31 then return nil end
	local items = {}
	for i = 0, count - 1 do
		local t = text_at(u16(0x9854 + i * 2), 60)
		if t == '' then return nil end
		items[#items + 1] = title_case(t)
	end
	return items
end

-- State --------------------------------------------------------------------------------
local prev = {}
local msgFrame = -1000
local menuKey = nil

local function read_message()
	local t = text_at(u16(0x97D0))
	local who = speaker()
	if who ~= '' then t = who .. ': ' .. t end
	return t
end

local function dialogue()
	local st = u8(0x9740)
	if st == 2 and prev.st ~= 2 then
		local pos, start = u16(0x9746), u16(0x97D0)
		-- The first box of a message speaks the whole message; later boxes of the same
		-- message are already spoken.
		if pos == start then
			local t = read_message()
			if t ~= '' then
				last_message = t
				say(t)
				msgFrame = A.frame
			end
		end
	end
	prev.st = st
end

local function menus()
	local active = u8(0x788D) == 1
	if not active then
		if prev.menuActive then menuKey = nil end
		prev.menuActive = false
		return
	end
	local items = menu_items()
	if not items then prev.menuActive = true; return end
	local key = table.concat(items, '|')
	local cur = u8(0x9710)
	if cur >= #items then prev.menuActive = true; return end
	local line = items[cur + 1] .. ', ' .. (cur + 1) .. ' of ' .. #items
	if key ~= menuKey or not prev.menuActive then
		-- A menu that opens right after a line of dialogue waits for that line.
		say(line, (A.frame - msgFrame) > 150)
		menuKey = key
	elseif cur ~= prev.cursor then
		say(line)
	end
	prev.cursor = cur
	prev.menuActive = true
	A.menu = items
end

-- System screens (backup RAM choice, title, options) ----------------------------------
local FP = {0x0A, 0x39, 0x00, 0x01, 0x00, 0x00, 0xCD, 0xAC}
local function boot_module()
	local b = memory.read_bytes_as_array(0x28826, 8, D)
	for i = 1, 8 do if b[i] ~= FP[i] then return false end end
	return true
end
local CONTROLS = {
	[0] = 'A draw blaster, B cancel, C select and shoot', 'A draw blaster, B select and shoot, C cancel',
	'A cancel, B draw blaster, C select and shoot', 'A select and shoot, B draw blaster, C cancel',
	'A select and shoot, B cancel, C draw blaster', 'A cancel, B select and shoot, C draw blaster'}
local function option_line(c)
	if c == 0 then return 'Device, ' .. (u8(0x78B9) == 1 and 'joypad and gun' or 'joypad only') .. ', 1 of 5'
	elseif c == 1 then return 'Controls, ' .. (CONTROLS[u8(0x78BB)] or 'unknown') .. ', 2 of 5'
	elseif c == 2 then return 'Sound mode, ' .. (u8(0x78A3) == 1 and 'mono' or 'stereo') .. ', 3 of 5'
	elseif c == 3 then return 'Gun adjust, 4 of 5'
	elseif c == 4 then return 'Quit, 5 of 5. Press C to leave options and start.' end
	return nil
end

local function bcd(b) return math.floor(b / 16) * 10 + b % 16 end
local function file_line(slot)
	local a = 0x28644 + slot * 8
	local saves = u8(a)
	local label = 'File ' .. (slot + 1) .. ', '
	if saves == 0xFF then return label .. 'no data' end
	local h, m = bcd(u8(a + 2)), bcd(u8(a + 3))
	local t = (h > 0) and (h .. (h == 1 and ' hour ' or ' hours ') .. m .. ' minutes') or (m .. (m == 1 and ' minute' or ' minutes'))
	return label .. 'played ' .. t .. ', saved ' .. saves .. (saves == 1 and ' time' or ' times')
end

local function system_screens()
	local s7, s9 = u8(0x7897), u8(0x7899)
	local screen = nil
	if boot_module() then
		if s7 == 0 and s9 == 2 then screen = 'bram'
		elseif s7 == 9 then screen = 'title'
		elseif s7 == 0x0A then screen = 'files'
		elseif s7 == 0x0B then screen = 'options' end
	end
	if screen ~= prev.screen then
		prev.screenValue = nil
		if screen == 'title' then say('Snatcher title screen.')
		elseif screen == 'bram' then say('Which backup memory will you use?')
		elseif screen == 'files' then say('Investigation files. Choose a file with up and down, then press Start.')
		elseif screen == 'options' then say('Options.') end
	end
	prev.screen = screen
	local value = nil
	if screen == 'bram' then
		value = (u8(0xCDAC) == 1) and 'CD backup RAM cart, 2 of 2' or 'Internal backup RAM, 1 of 2'
	elseif screen == 'title' then
		local c = u8(0x7F79)
		if c == 1 then value = 'Continue, 2 of 2. Press Start.'
		elseif c == 3 then value = 'New game, 1 of 2. Press Start.'
		else value = 'New game. Press Start.' end
	elseif screen == 'files' then
		local c = u8(0x78B7)
		if c <= 3 then value = file_line(c) end
	elseif screen == 'options' then
		value = option_line(u8(0x28AD9))
	end
	if value and value ~= prev.screenValue then
		say(value, prev.screenValue ~= nil)
	end
	prev.screenValue = value
	A.screenValue = value
end

-- Videophone keypad ---------------------------------------------------------------------
-- 0x9719 is 10 and 0x97F1 is 6 while the number pad is up. 0x97F0 is the key cursor (7 + row*12 + col*2),
-- 0x97F2 the number of digits typed, and the digits are at 0x9759.
local KEYS = {{'1', '2', '3'}, {'4', '5', '6'}, {'7', '8', '9'}, {'star', '0', 'hash'}}
local function digit_name(b)
	if b == 0x2A then return 'star' elseif b == 0x23 then return 'hash' end
	if b >= 0x30 and b <= 0x39 then return string.char(b) end
	return nil
end
local function typed()
	local n = u8(0x97F2)
	if n == 0 or n > 10 then return '', n end
	local t = {}
	local b = memory.read_bytes_as_array(0x9759, n, D)
	for i = 1, n do
		local d = digit_name(b[i])
		if not d then return nil, n end   -- the game has not written this digit yet
		t[#t + 1] = d
	end
	return table.concat(t, ' '), n
end
local function phone()
	-- 0x97F1 becomes 6 once the pad has finished drawing its empty digit boxes.
	local on = u8(0x9719) == 10 and u8(0x97F1) == 6 and u8(0x97F0) >= 7
	local key = nil
	if on then
		local v = u8(0x97F0) - 7
		local row, col = math.floor(v / 12), math.floor((v % 12) / 2)
		key = KEYS[row + 1] and KEYS[row + 1][col + 1]
	end
	local digits, n = typed()
	if on and digits == nil then return end   -- try again next frame
	if on and not prev.phone then
		say('Dial a number. Arrows choose a key, C types it, B deletes. The call goes through as soon as the number is complete. Key ' .. (key or '?') .. '.', false)
	elseif on then
		if n > (prev.phoneCount or 0) then say(digits)
		elseif n < (prev.phoneCount or 0) then say(n == 0 and 'Deleted. No digits.' or ('Deleted. ' .. digits))
		elseif key ~= prev.phoneKey then say(key or '?') end
	elseif prev.phone and (prev.phoneCount or 0) > 0 then
		say('Dialling ' .. prev.phoneDigits .. '.')
	end
	prev.phone, prev.phoneKey, prev.phoneCount, prev.phoneDigits = on, key, n, digits
	if on then A.screenValue = (digits ~= '' and ('Number so far: ' .. digits .. '. ') or 'No digits yet. ') .. 'Key ' .. (key or '?') .. '.' end
end

-- Captions -------------------------------------------------------------------------------
-- Words drawn as pictures (opening titles, credits, place names). Each is recognised by a
-- fingerprint of the tiles on screen; only exact matches are spoken.
local CAPTIONS = {
	[278137101] = 'This story is dedicated to all those cyberpunks who fight against injustice and corruption every day of their lives.',
	[4160089066] = 'Moscow, June 6, 1996.',
	[2820040163] = '50 years later.',
	[1236396727] = 'Japan.',
	[3934140968] = 'Cast.',
	[1592088032] = 'Gillian Seed: Jeff Lupetin.',
	[1613554130] = 'Metal Gear: Lucy Childs.',
	[3294450833] = 'Random Hajile: Jim Parks.',
	[1441457580] = 'Benson Cunningham: Ray Van Steen.',
	[3352181745] = 'Jamie Seed: Susan Mele.',
	[3195745618] = 'Mika Slayton: Kimberley Harne.',
	[3145688937] = 'Katrina Gibson: Lynn Foosaner.',
	[582603916] = 'Staff.',
	[4267799833] = 'Producer: Tomikazu Kirita.',
	[3012167848] = 'Creator: Hideo Kojima.',
	[2782902699] = 'Character design: Tomiharu Kinoshita.',
	[3798256822] = 'Director: Yoshinori Sasaki.',
	[925461108] = 'Assistant director: Mitsuhiro Togo.',
	[3068850013] = 'Supervisor: Jeremy Blaustein.',
	[149693222] = 'Main programmer: Masahiko Saito.',
	[191975847] = 'Sub programmer: Hidenari Inamura.',
	[2506473868] = 'Scenario compiler: Toshiya Adachi.',
	[1773824719] = 'Graphic designers: Satoshi Kushibuchi and Keita Nose.',
	[1317854262] = 'Music and sound: Konami Kukeiha Club.',
	[3154428970] = 'Translator: Scott T. Hards.',
	[621180609] = 'Special thanks: Michael Blaustein.',
	[12793204] = 'Produced by Konami Co., Ltd.',
	[2137390751] = 'Konami Omni Building, Junker Headquarters.',
}
local function caption_fingerprint()
	local h, n = 0, 0
	for r = 0, 27 do
		local row = memory.read_bytes_as_array(0xE000 + r * 128, 80, 'VRAM')
		for c = 0, 39 do
			local e = row[c * 2 + 1] * 256 + row[c * 2 + 2]
			if e % 2048 ~= 0 then
				n = n + 1
				h = (h * 31 + (r * 64 + c) * 7 + e) & 0xFFFFFFFF
				if n <= 24 then
					local t = (e % 2048) * 32
					h = (h * 31 + memory.read_u8(t + 8, 'VRAM') * 256 + memory.read_u8(t + 20, 'VRAM')) & 0xFFFFFFFF
				end
			end
		end
	end
	return h
end
local vramOK = pcall(memory.read_u8, 0, 'VRAM')
local function captions()
	if not vramOK or A.frame % 8 ~= 0 or u8(0x78E9) ~= 0 then return end
	local ok, fp = pcall(caption_fingerprint)
	if not ok then return end
	if fp ~= prev.caption then
		prev.caption = fp
		local text = CAPTIONS[fp]
		if text and text ~= prev.captionText then
			say(text, false)
			prev.captionText = text
		elseif not text then
			prev.captionText = nil
		end
	end
end

-- Shooting -----------------------------------------------------------------------------
local CELLS = {[0] = 'up left', 'up', 'up right', 'left', 'center', 'right', 'down left', 'down', 'down right'}
local shot = {active = false, cells = {}, born = {}, life = nil}
local dbg = nil

-- Directions that point the blaster at each grid cell (nothing held means the center).
local AIM = {[0] = {Up = true, Left = true}, {Up = true}, {Up = true, Right = true}, {Left = true}, {},
	{Right = true}, {Down = true, Left = true}, {Down = true}, {Down = true, Right = true}}
local function player_aiming()
	local ok, pad = pcall(joypad.getimmediate)
	if not ok or type(pad) ~= 'table' then return false end
	for _, d in ipairs({'Up', 'Down', 'Left', 'Right'}) do
		if pad['P1 ' .. d] or pad[d] then return true end
	end
	return false
end
local function press(buttons)
	local t = {}
	for k, v in pairs(buttons) do t['P1 ' .. k] = v end
	pcall(joypad.set, t)
end

local function aim_assist(phase)
	if not A.aim or phase ~= 2 then return end
	-- Draw the blaster once at the start of each scene (whichever button Options gives "draw").
	if u8(0x80E1) == 0 and (shot.drawTries or 0) < 3 and A.frame >= (shot.drawAt or 0) then
		local letter = BTN[0xEC][u16(0x78BA) + 1] or 'A'
		press({[letter] = true})
		shot.drawTries = (shot.drawTries or 0) + 1
		shot.drawAt = A.frame + 20
		return
	end
	if player_aiming() then return end     -- your own D pad always wins
	local best, born = nil, nil
	for c = 0, 8 do
		local st = shot.cells[c] or 0
		local kind, ph = math.floor(st / 16), st % 16
		if kind == 1 and ph >= 1 and ph <= 4 and (not born or shot.born[c] < born) then best, born = c, shot.born[c] end
	end
	if best then
		local dir = AIM[best]
		press({Up = dir.Up or false, Down = dir.Down or false, Left = dir.Left or false, Right = dir.Right or false})
	end
end

-- The enemy beacon: one enemy at a time (the one that has been there longest, which is also
-- where aim assist points) beeps from its position over and over. It starts slow and speeds
-- up the longer that enemy stays, because enemies attack if they are left too long.
local function beacon_interval(age)
	return math.max(7, math.floor(48 - age * 0.34))   -- frames: about 0.8 s down to about 0.12 s
end
local function oldest_enemy()
	local best, born = nil, nil
	for c = 0, 8 do
		local st = shot.cells[c] or 0
		local kind, ph = math.floor(st / 16), st % 16
		if kind == 1 and ph >= 1 and ph <= 4 and (not born or shot.born[c] < born) then best, born = c, shot.born[c] end
	end
	return best
end
local function beacon()
	local c = oldest_enemy()
	if c ~= shot.beaconCell then
		shot.beaconCell = c
		shot.beaconNext = A.frame          -- a new target beeps straight away
	end
	if not c or not A.beeps or not audio then return end
	if A.frame >= (shot.beaconNext or 0) and A.frame >= (shot.quietUntil or 0) then
		audio.play('enemy', c)
		shot.beaconNext = A.frame + beacon_interval(A.frame - (shot.born[c] or A.frame))
	end
end

local function check_life()
	local life = u8(0x892D)
	if shot.life and life < shot.life and life < 32 then
		if audio then audio.hit() end
		shot.quietUntil = A.frame + 15
		say(life == 0 and 'Hit! Life 0. You are down.' or ('Hit! Life ' .. life .. '.'), false)
	end
	shot.life = life
end

local function shooting()
	local phase = u8(0x78E9)
	local on = phase == 1 or phase == 2
	if on ~= shot.active then
		if not on and shot.active then check_life() end   -- the last hit can land as the scene ends
		shot.active = on
		shot.cells, shot.born = {}, {}
		shot.drawTries, shot.drawAt, shot.drawn = nil, nil, nil
		shot.beaconCell, shot.beaconNext, shot.quietUntil = nil, nil, nil
		if on then
			shot.life = u8(0x892D)
			say('Shooting! Life ' .. shot.life .. '.' .. (A.aim and ' Aim assist on.' or ''), false)
			if not dbg then dbg = io.open(folder .. 'snatcher-shooting.log', 'a') end
			if dbg then dbg:write(os.date('%H:%M:%S'), ' shooting start\n') end
		else
			if dbg then dbg:write(os.date('%H:%M:%S'), ' shooting end\n'); dbg:flush() end
		end
	end
	if not on then return end
	local drawn = u8(0x80E1) == 1
	if drawn then shot.drawTries = 99 end   -- drawn once: from now on holstering is your choice
	if shot.drawn ~= nil and drawn ~= shot.drawn and phase == 2 then
		say(drawn and 'Blaster ready.' or 'Blaster away.', false)
	end
	shot.drawn = drawn
	local spoken = 0
	for c = 0, 8 do
		local base = 0x8400 + c * 0x50
		local alive = u8(base + 1) == 1
		local st = alive and u8(base + 0x24) or 0
		local old = shot.cells[c] or 0
		if st ~= old then
			if dbg then dbg:write(string.format('%d cell %d %02X->%02X\n', A.frame, c, old, st)) end
			local kind = math.floor(st / 16)
			local ph = st % 16
			local oldkind = math.floor(old / 16)
			-- A new target: state goes from empty (or another target) to an appearing phase.
			if ph <= 2 and (old == 0 or oldkind ~= kind or (old % 16) >= 3) and (kind == 1 or kind == 2) then
				shot.born[c] = A.frame
				local what = (kind == 1) and ('Enemy ' .. CELLS[c]) or ('Civilian ' .. CELLS[c] .. ", don't shoot")
				if kind == 2 and A.beeps and audio then
					audio.play('civilian', c)
					shot.quietUntil = A.frame + 12
				elseif kind == 1 and A.beeps and audio and shot.beaconCell and shot.beaconCell ~= c then
					-- the beacon is busy with an older enemy: one beep so you still hear where this one is
					audio.play('enemy', c)
				end
				if A.voice then
					-- Enemies cut in at once; civilians wait their turn so they never cut off an enemy.
					say(what, kind == 1 and spoken == 0)
					spoken = spoken + 1
				end
			-- Shot: an enemy passes through 6 to 7, a civilian jumps straight to 7.
			elseif (ph == 7 and (old % 16) ~= 7 and (old % 16) ~= 6) or (ph == 6 and kind == 1) then
				if kind == 1 then
					if A.beeps and audio then audio.kill(); shot.quietUntil = A.frame + 10 end
				elseif kind == 2 then
					say('You shot a civilian!')
				end
			end
			shot.cells[c] = st
		end
	end
	check_life()
	beacon()
	aim_assist(phase)
end

function A.targets()
	if not shot.active then return 'Not in a shooting scene.' end
	local list = {}
	for c = 0, 8 do
		local st = shot.cells[c] or 0
		local kind, phase = math.floor(st / 16), st % 16
		if (kind == 1 or kind == 2) and phase <= 4 then
			list[#list + 1] = ((kind == 1) and 'enemy ' or 'civilian ') .. CELLS[c]
		end
	end
	local s = 'Life ' .. u8(0x892D) .. '. '
	if #list == 0 then return s .. 'No targets showing.' end
	return s .. table.concat(list, ', ') .. '.'
end

-- Keyboard -----------------------------------------------------------------------------
local oldKeys = {}
local HELP = 'Snatcher access keys. R repeats the last thing said. T reads the current message again. ' ..
	'M reads the whole menu. L says your life and the targets showing in a shooting scene. ' ..
	'V turns target speech on or off. B turns target sounds on or off. G turns aim assist on or off. ' ..
	'Control stops speech. K repeats this help.'

local function keyboard()
	local keys = input.get()
	local function pressed(k) return keys[k] and not oldKeys[k] end
	-- BizHawk names modifiers differently between versions, so match by name.
	local mod, ctrl, newctrl = false, false, false
	for k, v in pairs(keys) do
		if v and type(k) == 'string' then
			local n = k:lower()
			if n:find('ctrl') or n:find('control') then
				ctrl = true
				if not oldKeys[k] then newctrl = true end
			elseif n:find('alt') or n:find('shift') then mod = true end
		end
	end
	if newctrl then stop_speech() end
	if not (mod or ctrl) then
		if pressed('R') then say(last_said)
		elseif pressed('T') then
			if u8(0x9740) ~= 0 then last_message = read_message() end
			say(last_message ~= '' and last_message or 'No message yet.')
		elseif pressed('M') then
			if A.screenValue then say(A.screenValue)
			elseif u8(0x788D) == 1 then
				local items = menu_items()
				if items then say('Menu: ' .. table.concat(items, ', ') .. '. Selected: ' .. items[(u8(0x9710) % #items) + 1] .. '.')
				else say('No menu.') end
			else say('No menu on screen.') end
		elseif pressed('L') then say(A.targets())
		elseif pressed('V') then A.voice = not A.voice; say(A.voice and 'Target speech on.' or 'Target speech off.')
		elseif pressed('B') then
			A.beeps = not A.beeps
			say(audio and (A.beeps and 'Target sounds on.' or 'Target sounds off.') or 'Target sounds are unavailable.')
		elseif pressed('G') then
			A.aim = not A.aim
			say(A.aim and 'Aim assist on.' or 'Aim assist off.')
		elseif pressed('K') then say(HELP) end
	end
	oldKeys = keys
end

-- Main loop ----------------------------------------------------------------------------
function A.tick()
	A.frame = A.frame + 1
	A.screenValue = nil
	system_screens()
	phone()
	captions()
	dialogue()
	menus()
	shooting()
	keyboard()
end

function A.shutdown()
	if audio then pcall(audio.close); audio = nil end
	if sapi then pcall(function() sapi:SpeakAsyncCancelAll(); sapi:Dispose() end); sapi = nil end
	if log then log:close(); log = nil end
	if dbg then dbg:close(); dbg = nil end
end

local function reset_state()
	prev = {}; menuKey = nil; shot = {active = false, cells = {}, born = {}, life = nil}
end
A.hooks[#A.hooks + 1] = event.onloadstate(reset_state, 'Snatcher access state reset')
A.hooks[#A.hooks + 1] = event.onexit(function() A.shutdown() end, 'Snatcher access cleanup')

say('Snatcher access version ' .. A.version .. ' ready. Press K for help.')
if SNATCHER_NO_LOOP then return A end
while true do
	local ok, err = pcall(A.tick)
	if not ok then
		say('Snatcher access stopped because of an error: ' .. tostring(err))
		A.shutdown()
		break
	end
	emu.frameadvance()
end
