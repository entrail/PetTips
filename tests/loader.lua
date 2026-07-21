-- Loads addon source files headlessly, exactly like the game does: each
-- file's chunk is called with ("PetTips", ns) and given an environment
-- where WoW globals resolve to the mock set first, falling back to _G.
-- Globals the addon writes (PetTipsDB, SLASH_...) land in the env table,
-- so every boot is fully isolated. Requires Lua 5.1 / LuaJIT (setfenv).

local Loader = {}
Loader.addonName = "PetTips"

local function makeEnv(mocks)
    local env
    env = setmetatable({}, {
        __index = function(_, k)
            local v = mocks[k]
            if v ~= nil then return v end
            return _G[k]
        end,
    })
    env._G = env -- _G["SpellButton1"] etc. must resolve to the mock set
    mocks.__env = env -- CreateFrame registers named frames here
    return env
end

function Loader.newEnv(mocks)
    return makeEnv(mocks)
end

function Loader.load(base, path, ns, env)
    local chunk, err = loadfile(base .. path)
    if not chunk then error("loadfile(" .. path .. "): " .. tostring(err)) end
    setfenv(chunk, env)
    return chunk(Loader.addonName, ns)
end

function Loader.loadAll(base, paths, ns, env)
    for _, p in ipairs(paths) do
        Loader.load(base, p, ns, env)
    end
end

return Loader
