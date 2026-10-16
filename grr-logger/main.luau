--grr logger 
--credits to : v1x , .Anonym in discord
--fully handcoded envinronment logger !

local fs = require('@lune/fs')
local process = require('@lune/process')
local task = require('@lune/task')
local roblox = require('@lune/roblox')
local luau = require('@lune/luau')

local input = assert(process.args[1], 'Usage: lune run main.lua <input.lua> [output.lua]')
local lines, jobs, errors = {}, {}, {}
local refs, names, cache = {}, {}, {}
local env, globals = {}, {}
local mocks = {}
local nextVar = 0
local fenvLogged, useMocks = false, false
local scriptSources = {}
local callbacks, callbackCache, contexts = {}, {}, {}
local STOP, YIELD = {}, {}

names[env] = 'fenv'

local function instrument(source)
	local parts = {}
	local first, i = 1, 1
	while i <= #source do
		local char = source:sub(i, i)
		local comment = source:sub(i, i + 1) == '--'
		local start = comment and i + 2 or i
		local equals = source:sub(start):match('^%[(=*)%[')
		if equals then
			local _, last = source:find(']' .. equals .. ']', start + 2 + #equals, true)
			i = (last or #source) + 1
		elseif comment then
			i = source:find('\n', i + 2, true) or (#source + 1)
		elseif char == '"' or char == "'" or char == '`' then
			i += 1
			while i <= #source do
				if source:sub(i, i) == '\\' then
					i += 2
				elseif source:sub(i, i) == char then
					i += 1
					break
				else
					i += 1
				end
			end
		elseif char:match('[%a_]') then
			local _, last = source:find('^[%w_]+', i)
			local word = source:sub(i, last)
			i = last + 1
			if word == 'do' or word == 'repeat' then
				parts[#parts + 1] = source:sub(first, last) .. ' __envlogger_step();'
				first = i
			end
		else
			i += 1
		end
	end
	parts[#parts + 1] = source:sub(first)
	return table.concat(parts)
end

local function loadChunk(source, name)
	local options = { environment = env, injectGlobals = false, debugName = name }
	local ok, fn = pcall(luau.load, instrument(source), options)
	if not ok then fn = luau.load(source, options) end
	scriptSources[debug.info(fn, 's')] = ok or nil
	callbackCache[fn] = false
	return fn
end

local function emit(text)
	local context = contexts[coroutine.running()]
	local target = context and context.rows or lines
	if context and context.mode and #target >= 80 then error(STOP, 0) end
	local row = { text }
	target[#target + 1] = row
	return row
end

local function getCallback(fn, hint)
	if callbackCache[fn] == false then return nil end
	if not scriptSources[debug.info(fn, 's')] then return nil end
	if not callbackCache[fn] then
		local arity, vararg = debug.info(fn, 'a')
		local record = { id = #callbacks + 1, fn = fn, arity = arity, vararg = vararg, rows = {} }
		callbacks[#callbacks + 1], callbackCache[fn] = record, record
	end
	local record = callbackCache[fn]
	if hint and hint.Callback == fn then record.hint = hint end
	return record
end

local function fmt(value, seen, hint)
	if names[value] then return names[value] end
	local kind = type(value)
	if kind == 'string' then return string.format('%q', value) end
	if kind == 'function' then
		local record = getCallback(value, hint)
		return record and ('\1' .. record.id .. '\2') or 'function(...) end'
	end
	if kind == 'thread' then return 'coroutine.create(function(...) end)' end
	if kind ~= 'table' then return tostring(value) end
	seen = seen or {}
	if seen[value] then return '{}' end
	seen[value] = true
	local items = {}
	for k, v in value do
		items[#items + 1] = '[' .. fmt(k, seen) .. ']=' .. fmt(v, seen, value)
	end
	seen[value] = nil
	return '{' .. table.concat(items, ', ') .. '}'
end

local function field(path, key)
	if type(key) == 'string' and key:match('^[%a_][%w_]*$') then return path .. '.' .. key end
	return path .. '[' .. fmt(key) .. ']'
end

local function read(path) emit('local _ = ' .. path) end
local function fenv()
	if not fenvLogged then
		table.insert(lines, 1, { 'local fenv = getfenv()' })
		fenvLogged = true
	end
	return env
end

local bind, wrap, stub
local function call(path, fn, values)
	local index = nextVar
	nextVar += 1
	local name = 'var' .. index
	local items = {}
	for i = 1, values.n do
		items[i] = fmt(values[i])
		values[i] = refs[values[i]] or values[i]
	end
	local expr = path .. '(' .. table.concat(items, ', ') .. ')'
	local row = emit('local ' .. name .. ' = ' .. expr)
	local result = table.pack(pcall(fn, table.unpack(values, 1, values.n)))
	if not result[1] then
		if result[2] == STOP or result[2] == YIELD then error(result[2], 0) end
		if useMocks then
			result = table.pack(true, stub(name))
		else
			row[1] = nil
			if nextVar == index + 1 then
				nextVar -= 1
			end
			error(result[2], 0)
		end
	end
	local locals = { name }
	for i = 3, result.n do
		locals[#locals + 1] = name .. '_' .. (i - 1)
	end
	row[1] = 'local ' .. table.concat(locals, ', ') .. ' = ' .. expr
	for i = 2, result.n do
		result[i] = bind(result[i], locals[i - 1])
	end
	return table.unpack(result, 2, result.n)
end

stub = function(path, parent, key)
	local proxy, fields = {}, {}
	names[proxy], mocks[proxy] = path, true
	local mt = {
		__index = function(_, k)
			read(field(names[proxy], k))
			if fields[k] == nil then fields[k] = stub(field(names[proxy], k), proxy, k) end
			return fields[k]
		end,
		__newindex = function(_, k, v)
			fields[k] = v
			emit(field(names[proxy], k) .. ' = ' .. fmt(v))
		end,
		__call = function(_, ...)
			local values = table.pack(...)
			local method = parent and values[1] == parent
			local expr = method and names[parent] .. ':' .. key or names[proxy]
			if method then values = table.pack(table.unpack(values, 2, values.n)) end
			return call(expr, function()
				if key and key:match('^FindFirstChild') then return nil end
				if key == 'GetChildren' or key == 'GetDescendants' or key == 'GetPlayers' then
					return {}
				end
				return stub(expr)
			end, values)
		end,
		__tostring = function() return names[proxy] end,
		__len = function() return 0 end,
		__unm = function() return stub('(-' .. names[proxy] .. ')') end,
	}
	for method, op in
		{
			__add = '+',
			__sub = '-',
			__mul = '*',
			__div = '/',
			__mod = '%',
			__pow = '^',
			__concat = '..',
		}
	do
		mt[method] = function(a, b) return stub('(' .. fmt(a) .. ' ' .. op .. ' ' .. fmt(b) .. ')') end
	end
	return setmetatable(proxy, mt)
end

bind = function(value, path)
	if mocks[value] then
		names[value] = path
		return value
	end
	if typeof(value) == 'Instance' then return wrap(value, path) end
	if type(value) == 'table' then
		local result = {}
		names[result] = path
		for k, v in value do
			result[k] = bind(v, field(path, k))
		end
		return result
	end
	if type(value) == 'function' or type(value) == 'thread' or type(value) == 'userdata' then
		names[value] = names[value] or path
	end
	return value
end

wrap = function(value, path)
	if cache[value] then return cache[value] end
	local proxy, methods = {}, {}
	refs[proxy], names[proxy], cache[value] = value, path, proxy
	return setmetatable(proxy, {
		__index = function(_, key)
			local member = field(path, key)
			local ok, result = pcall(function() return value[key] end)
			if not ok then
				if
					({ HttpGet = true, HttpPost = true, GetAsync = true, PostAsync = true })[key]
				then
					result = function()
						useMocks = true
						return stub(member)
					end
				elseif useMocks then
					return stub(member, proxy, key)
				else
					error(result, 0)
				end
			end
			if result == nil and useMocks then return stub(member) end
			if type(result) ~= 'function' then
				read(member)
				return bind(result, member)
			end
			if not methods[key] then
				methods[key] = function(...)
					local values = table.pack(...)
					local method = values[1] == proxy
					local expr = method and path .. ':' .. key or member
					if method then
						local tail = table.pack(table.unpack(values, 2, values.n))
						return call(expr, function(...) return result(value, ...) end, tail)
					end
					return call(expr, result, values)
				end
				names[methods[key]] = member
			end
			return methods[key]
		end,
		__newindex = function(_, key, new)
			value[key] = refs[new] or new
			local member = field(path, key)
			emit(member .. ' = ' .. fmt(new))
		end,
		__tostring = function() return tostring(value) end,
		__len = function() return #value end,
	})
end

local function runCallback(record, values, rows, mode)
	rows = rows or record.rows
	local co = coroutine.running()
	local previous = contexts[co]
	contexts[co] = {
		rows = rows,
		mode = mode,
		steps = 0,
		deadline = os.clock() + 0.2,
	}
	local ok, err = pcall(record.fn, table.unpack(values, 1, values.n))
	contexts[co] = previous
	if not mode then record.observed = true end
	if not ok and err ~= YIELD then
		if err == STOP then
			rows[#rows + 1] = { '--exp limit' }
		elseif mode then
			rows[#rows + 1] = { '--incomplete trace' .. tostring(err):gsub('[\r\n].*', '') }
		else
			errors[#errors + 1] = tostring(err)
		end
	end
end

local function probe(record, values, rows)
	local co = task.spawn(runCallback, record, values, rows, 'probe')
	local deadline = os.clock() + 0.25
	while coroutine.status(co) ~= 'dead' and os.clock() < deadline do
		task.wait(0.001)
	end
	if coroutine.status(co) ~= 'dead' then
		task.cancel(co)
		contexts[co] = nil
		rows[#rows + 1] = { '--exp paused' }
	end
end

local function launch(method, seconds, fn, ...)
	assert(type(fn) == 'function' or type(fn) == 'thread', 'expected function or thread')
	local values = table.pack(...)
	local context = contexts[coroutine.running()]
	local record = type(fn) == 'function' and getCallback(fn)
	if context and context.mode then
		if record and not record.observed then
			record.observed = true
			runCallback(record, values, nil, 'once')
		end
		return coroutine.create(function() end)
	end
	local callback = fn
	if type(fn) == 'function' then
		callback = function()
			if record then
				runCallback(record, values)
				return
			end
			local ok, err = pcall(fn, table.unpack(values, 1, values.n))
			if not ok then errors[#errors + 1] = tostring(err) end
		end
	end
	local co
	if method == 'delay' then
		co = task.delay(seconds, callback, table.unpack(values, 1, values.n))
	else
		co = task[method](callback, table.unpack(values, 1, values.n))
	end
	jobs[#jobs + 1] = co
	return co
end
--credits to : v1x , .Anonym in discord
local base = getfenv()
local builtinNames = string.split(
	'assert error type tostring tonumber pairs ipairs next select unpack pcall xpcall getmetatable setmetatable newproxy rawequal rawget rawset rawlen',
	' '
)
for _, key in builtinNames do
	globals[key] = base[key]
end
for _, key in { 'string', 'math', 'table', 'bit32', 'utf8', 'buffer', 'coroutine', 'os' } do
	globals[key] = table.clone(base[key])
end
globals.unpack = table.unpack
globals.typeof = function(value) return typeof(refs[value] or value) end
local game = roblox.Instance.new('DataModel')
local world = game:GetService('Workspace')
local players = game:GetService('Players')
local player = roblox.Instance.new('Player')
player.DisplayName, player.Parent = player.Name, players
players.LocalPlayer = player
for _, class in { 'Camera', 'Terrain' } do
	roblox.Instance.new(class).Parent = world
end
globals.game, globals.workspace = wrap(game, 'game'), wrap(world, 'workspace')
globals.script = wrap(roblox.Instance.new('LocalScript'), 'script')
local robloxTypes = {
	'Instance',
	'Enum',
	'Vector2',
	'Vector3',
	'CFrame',
	'Color3',
	'UDim',
	'UDim2',
	'Rect',
	'Ray',
	'BrickColor',
	'TweenInfo',
}
for _, key in robloxTypes do
	if roblox[key] then globals[key] = wrap(roblox[key], key) end
end
globals.task = wrap({
	spawn = function(fn, ...) return launch('spawn', 0, fn, ...) end,
	defer = function(fn, ...) return launch('defer', 0, fn, ...) end,
	delay = function(seconds, fn, ...) return launch('delay', seconds, fn, ...) end,
	wait = function(seconds)
		local context = contexts[coroutine.running()]
		if context and context.mode then
			if context.mode == 'once' then error(YIELD, 0) end
			return seconds or 0
		end
		return task.wait(seconds)
	end,
	cancel = task.cancel,
}, 'task')
globals.spawn, globals.delay, globals.wait =
	globals.task.spawn, globals.task.delay, globals.task.wait
globals.print = function(...)
	return call('print', function() end, table.pack(...))
end
globals.warn = function(...)
	return call('warn', function() end, table.pack(...))
end
globals.require = function(...)
	return call('require', function()
		useMocks = true
		return stub('require')
	end, table.pack(...))
end
globals.debug = wrap(debug, 'debug')
globals.coroutine = wrap(coroutine, 'coroutine')
globals.getfenv, globals.getgenv = fenv, fenv
globals.setfenv = setfenv
globals._G, globals._ENV = env, env
globals.__envlogger_step = function()
	local context = contexts[coroutine.running()]
	if context and context.mode then
		context.steps += 1
		if
			context.steps > 30000 or (context.steps % 1000 == 0 and os.clock() > context.deadline)
		then
			error(STOP, 0)
		end
	end
end
globals.loadstring = function(source, name)
	if mocks[source] then
		local fn
		fn = function(...)
			return call(names[fn], function() return stub(names[fn]) end, table.pack(...))
		end
		return call('loadstring', function() return fn end, table.pack(source))
	end
	return call('loadstring', function(src, label)
		local ok, loaded = pcall(loadChunk, src, label or 'loadstring')
		if not ok then return nil, loaded end
		local fn
		fn = function(...) return call(names[fn], loaded, table.pack(...)) end
		return fn
	end, name and table.pack(source, name) or table.pack(source))
end

local builtins = table.clone(globals)
setmetatable(env, {
	__index = function(_, key)
		if not builtins[key] then
			fenv()
			read('fenv[' .. fmt(key) .. ']')
		end
		local context = contexts[coroutine.running()]
		if globals[key] == nil and context and context.mode then
			return stub('fenv[' .. fmt(key) .. ']')
		end
		return globals[key]
	end,
	__newindex = function(_, key, value)
		fenv()
		local text = 'fenv[' .. fmt(key) .. '] = ' .. fmt(value)
		emit(text)
		globals[key] = value
	end,
})
local ok, fn = pcall(loadChunk, fs.readFile(input), input)
if ok then
	launch('spawn', 0, fn)
else
	errors[#errors + 1] = tostring(fn)
end

local deadline = os.clock() + 10
while os.clock() < deadline do
	local running = false
	for _, co in jobs do
		if coroutine.status(co) ~= 'dead' then
			running = true
			break
		end
	end
	if not running then break end
	task.wait(0.001)
end
for _, co in jobs do
	if coroutine.status(co) ~= 'dead' then
		task.cancel(co)
		errors[#errors + 1] = 'task timeout'
	end
end
useMocks = true
local explorationDeadline = os.clock() + 4
local position = 1
while position <= #callbacks and position <= 128 and os.clock() < explorationDeadline do
	local record = callbacks[position]
	if not record.observed then
		record.explored = true
		local values = { n = record.arity }
		for i = 1, record.arity do
			values[i] = stub('arg' .. i)
		end
		local hint = record.hint
		if hint and record.arity > 0 and type(hint.Default) == 'boolean' then
			record.cases = { {}, {} }
			values[1] = true
			probe(record, values, record.cases[1])
			values[1] = false
			probe(record, values, record.cases[2])
		else
			if hint and record.arity > 0 then
				values[1] = hint.Default or (hint.Values and hint.Values[1]) or values[1]
			end
			probe(record, values, record.rows)
		end
	end
	position += 1
end

local render
local function renderRows(rows)
	local result = {}
	for _, row in rows do
		if row[1] then result[#result + 1] = render(row[1]) end
	end
	return table.concat(result, '\n')
end

render = function(text)
	return (
		text:gsub('\1(%d+)\2', function(id)
			local record = callbacks[tonumber(id)]
			if record.rendering then return 'function(...) end' end
			record.rendering = true
			local params = {}
			for i = 1, record.arity do
				params[#params + 1] = 'arg' .. i
			end
			if record.vararg then params[#params + 1] = '...' end
			local body = renderRows(record.rows)
			if record.cases then
				local yes, no = renderRows(record.cases[1]), renderRows(record.cases[2])
				if yes ~= '' or no ~= '' then
					body = 'if arg1 then\n\t'
						.. yes:gsub('\n', '\n\t')
						.. '\nelse\n\t'
						.. no:gsub('\n', '\n\t')
						.. '\nend'
				end
			end
			if body == '' and record.explored then body = '--no env calls got' end
			if not record.explored and not record.observed then
				body = '--failed to explore callback'
			end
			record.rendering = nil
			local signature = 'function(' .. table.concat(params, ', ') .. ')'
			if body == '' then return signature .. ' end' end
			return signature .. '\n\t' .. body:gsub('\n', '\n\t') .. '\nend'
		end)
	)
end

local output = renderRows(lines) .. '\n'
fs.writeFile(process.args[2] or 'out.lua', output)
local _, lineCount = output:gsub('\n', '')
print(lineCount .. ' lines')
for _, err in errors do
	warn(err)
end
if #errors > 0 then process.exit(1) end

--credits to : v1x , .Anonym in discord
