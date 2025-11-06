script_name('[JF] Mining Tools')
script_author('JustFedot -- Restored by dakyg')
script_version('2.3.6')
script_version_number(2)
script_description('Скрипт для упрощения майнинга на сервере.')

require("moonloader")
local sampfuncs = require("sampfuncs")
local sampev = require("samp.events")
local encoding = require("encoding")
encoding.default = 'CP1251'
u8 = encoding.UTF8
local imgui = require("mimgui")
local ffi = require('ffi')
local raknet = require('samp.raknet')
local wm = require('windows.message')
require('samp.synchronization')
local requests = require('requests')

if sampev.INTERFACE.INCOMING_RPCS[61][2].dialogId == "uint16" then
    sampev.INTERFACE.INCOMING_RPCS[61] = {
        "onShowDialog",
        {
            dialogId = "uint16"
        },
        {
            style = "uint8"
        },
        {
            title = "string8"
        },
        {
            button1 = "string8"
        },
        {
            button2 = "string8"
        },
        {
            text = "encodedString4096"
        },
        {
            placeholder = "string8"
        }
    }
end
local dialogIdTable = {}

local dialogIdTableArizona = {
    videoCardSt = 25244,             -- ID диалога полки
    videoCardDialogId = 25245,       -- ID диалога управления видеокартой (Стойка/Полка)
    coolantDialogId = 25271,         -- ID диалога выбора охлаждающей жидкости
    houseDialogId = 7238,            -- ID диалога выбора дома
    houseFlashMinerDialogId = 25182, -- ID диалога выбора видеокарты в доме
    videoCardAcceptDialogId = 25246, -- ID диалога подтверждения вывода прибыли

    phoneBankMenuId = 6565,          -- ID главного меню банка в телефоне
    payAllTaxesDialogId = 15252,     -- ID диалога подтверждения оплаты всех налогов
    houseListBankId = 7238,          -- ID диалога выбора дома для пополнения (тот же что и houseDialogId)
    topUpBalanceDialogId = 27016,    -- ID диалога ввода суммы пополнения

}
local dialogIdTableRodina = {
    videoCardSt = 25244,           -- ID диалога полки
    videoCardDialogId = 270,       -- ID диалога управления видеокартой (Стойка/Полка)
    coolantDialogId = 25271,       -- ID диалога выбора охлаждающей жидкости
    houseDialogId = 7238,          -- ID диалога выбора дома
    houseFlashMinerDialogId = 269, -- ID диалога выбора видеокарты в доме
    videoCardAcceptDialogId = 271, -- ID диалога подтверждения вывода прибыли
    -- Не нужны, но просто чтобы были
    phoneBankMenuId = 6565,        -- ID главного меню банка в телефоне
    payAllTaxesDialogId = 15252,   -- ID диалога подтверждения оплаты всех налогов
    houseListBankId = 7238,        -- ID диалога выбора дома для пополнения (тот же что и houseDialogId)
    topUpBalanceDialogId = 27016,  -- ID диалога ввода суммы пополнения
}

do
    Jcfg = {
        _version = 0.1,
        _author = "JustFedot",
        _telegram = "@justfedot",
        _help = [[Jcfg - модуль для сохранения и загрузки конфигурационных файлов...]]
    }

    function Jcfg.__init()
        local self = {}
        local json = require('dkjson')

        local function makeDirectory(path)
            assert(type(path) == "string" and path:find('moonloader'),
                "Path must be a string and include 'moonloader' folder")
            path = path:gsub("[\\/][^\\/]+%.json$", "")
            if not doesDirectoryExist(path) then
                if not createDirectory(path) then
                    return error("Failed to create directory: " .. path)
                end
            end
        end

        local function setupImguiConfig(table)
            assert(type(table) == "table",
                ("bad argument #1 to 'setupImgui' (table expected, got %s)"):format(type(table)))
            local function setupImguiConfigRecursive(tbl)
                local imcfg = {}
                for k, v in pairs(tbl) do
                    if type(v) == "table" then
                        imcfg[k] = setupImguiConfigRecursive(v)
                    elseif type(v) == "number" then
                        if v % 1 == 0 then
                            imcfg[k] = imgui.new.int(v)
                        else
                            imcfg[k] = imgui.new.float(v)
                        end
                    elseif type(v) == "string" then
                        imcfg[k] = imgui.new.char[256](u8(v))
                    elseif type(v) == "boolean" then
                        imcfg[k] = imgui.new.bool(v)
                    else
                        error(("Unsupported type for imguiConfig: %s"):format(type(v)))
                    end
                end
                return imcfg
            end
            return setupImguiConfigRecursive(table)
        end

        function self.save(table, path)
            assert(type(table) == "table", ("bad argument #1 to 'save' (table expected, got %s)"):format(type(table)))
            assert(path == nil or type(path) == "string", "Path must be nil or a valid file path.")
            if not path then
                assert(thisScript().name, "Script name is not defined")
                path = getWorkingDirectory() .. '\\config\\' .. thisScript().name .. '\\config.json'
            end
            makeDirectory(path)
            local file = io.open(path, "w")
            if file then
                file:write(json.encode(table, { indent = true }))
                file:close()
            else
                error("Could not open file for writing: " .. path)
            end
        end

        function self.load(path)
            if not path then
                path = getWorkingDirectory() .. '\\config\\' .. thisScript().name .. '\\config.json'
            end
            if doesFileExist(path) then
                local file = io.open(path, "r")
                if file then
                    local content = file:read("*all")
                    file:close()
                    return json.decode(content)
                else
                    return error("Could not load configuration")
                end
            end
            return {}
        end

        function self.update(table, path)
            assert(type(table) == "table", ("bad argument #1 to 'update' (table expected, got %s)"):format(type(table)))
            local loadedCfg = self.load(path)
            if loadedCfg then
                for k, v in pairs(table) do
                    if loadedCfg[k] ~= nil then
                        table[k] = loadedCfg[k]
                    end
                end
            end
            return true
        end

        function self.setupImgui(table)
            assert(imgui ~= nil, "The imgui library is not loaded.")
            return setupImguiConfig(table)
        end

        return self
    end

    setmetatable(Jcfg, {
        __call = function(self)
            return self.__init()
        end
    })
end

local jcfg = Jcfg()

local cfg = {
    isReloaded = false,
    silentMode = false,
    active = true,
    useSuperCoolant = false,
    useCoolantPercent = 50,
    economyMode = false,
    pause_duration = 120,
    count_action = 12,
    useDialogMode = false,
    targetHouseBalance = 10000000,
    taxPayment = 10000,
    housesWithoutBasement = {},
    lastKnownHouseCount = -1
}

jcfg.update(cfg)
local imcfg = jcfg.setupImgui(cfg)

function save()
    jcfg.save(cfg)
end

function resetDefaultCfg()
    cfg = {
        isReloaded = true,
        silentMode = false,
        active = true,
        useSuperCoolant = false,
        useCoolantPercent = 50,
        economyMode = false,
        pause_duration = 120,
        count_action = 12,
        useDialogMode = false,
        targetHouseBalance = 10000000,
        taxPayment = 10000,
        housesWithoutBasement = {},
        lastKnownHouseCount = -1
    }
    save()
    thisScript():reload()
end

local data = {
    main = imgui.new.bool(false),
    showHouseControlWindow = imgui.new.bool(false),
    selectedHouseIndex = 1,
    lastWindowState = {
        main = false,
        houseControl = false,
    },
    dialogData = {
        flashminer = {},
        videocards = {}
    },
    taskTypeNow = '',
    houseStatuses = {},
    working = false,
    autoCoolant = false,
    isFlashminer = false,
    forImgui = {
        allGood = false,
        videocardCount = 0,
        earnings = { btc = 0, asc = 0 },
        attentionTime = 0,
    },
    withdraw = { btc = 0, asc = 0 },
    dFlashminerId = 0,
    flashminerSwitchId = { direction = 0, id = 0 },
    houseHasNoBasement = false,
    isRodina = false,
    initialScanCompleted = false,
    activeTaskState = false,
    lastSelectedHouse = -1,
    capturedTaxAmount = 0,
    fix = false

}

local utils = (function()
    local self = {}
    local function cyrillic(text)
        local convtbl = {
            [230] = 155,
            [231] = 159,
            [247] = 164,
            [234] = 107,
            [250] = 144,
            [251] = 168,
            [254] = 171,
            [253] = 170,
            [255] = 172,
            [224] = 97,
            [240] = 112,
            [241] = 99,
            [226] = 162,
            [228] = 154,
            [225] = 151,
            [227] = 153,
            [248] = 165,
            [243] = 121,
            [184] = 101,
            [235] = 158,
            [238] = 111,
            [245] = 120,
            [233] = 157,
            [242] = 166,
            [239] = 163,
            [244] = 63,
            [237] = 174,
            [229] = 101,
            [246] = 36,
            [236] = 175,
            [232] = 156,
            [249] = 161,
            [252] = 169,
            [215] = 141,
            [202] = 75,
            [204] = 77,
            [220] = 146,
            [221] = 147,
            [222] = 148,
            [192] = 65,
            [193] = 128,
            [209] = 67,
            [194] = 139,
            [195] = 130,
            [197] = 69,
            [206] = 79,
            [213] = 88,
            [168] = 69,
            [223] = 149,
            [207] = 140,
            [203] = 135,
            [201] = 133,
            [199] = 136,
            [196] = 131,
            [208] = 80,
            [200] = 133,
            [198] = 132,
            [210] = 143,
            [211] = 89,
            [216] = 142,
            [212] = 129,
            [214] = 137,
            [205] = 72,
            [217] = 138,
            [218] = 167,
            [219] = 145
        }
        local result = {}
        for i = 1, #text do
            local c = text:byte(i)
            result[i] = string.char(convtbl[c] or c)
        end
        return table.concat(result)
    end
    function self.addChat(a)
        if cfg.silentMode then return end
        if a then
            local a_type = type(a)
            if a_type == 'number' then a = tostring(a) elseif a_type ~= 'string' then return end
        else
            return
        end
        sampAddChatMessage('{ffa500}' .. thisScript().name .. '{ffffff}: ' .. a, -1)

        --imgui.addNotification(u8(a):gsub('{%x%x%x%x%x%x}', ''))
    end

    function self.printStringNow(text, time)
        if not text then return end
        time = time or 100
        text = type(text) == "number" and tostring(text) or text
        if type(text) ~= 'string' then return end
        printStringNow(cyrillic(text), time)
    end

    function self.calculateRemainingHours(percent)
        local consumptionPerHour = 0.48
        return percent / consumptionPerHour
    end

    function self.formatTime(seconds)
        local hours = math.floor(seconds / 3600)
        local minutes = math.floor((seconds % 3600) / 60)
        local secs = math.floor(seconds % 60)
        return string.format('%02d:%02d:%02d', hours, minutes, secs)
    end

    function self.random(min, max)
        math.randomseed(os.time())
        for _ = 1, 5 do math.random() end
        return math.random(min, max)
    end

    function self.simplifyNumber(num)
        local suffixes = { [1e9] = "kkk", [1e6] = "kk", [1e3] = "k" }
        for base, suffix in ipairs({ 1e9, 1e6, 1e3 }) do
            if num >= suffix then
                local decimals = (suffix == 1e3) and 1 or 3
                local value = round(num / suffix, decimals)
                return value .. (suffixes)[suffix]
            end
        end
        return tostring(num)
    end

    function self.formatNumber(num)
        if type(num) ~= 'number' then
            if type(num) == 'string' and tonumber(num) then
                num = tonumber(num)
            else
                return 'Error: invalid input'
            end
        end
        local formatted = string.format('%.0f', math.floor(num))
        local reversed = formatted:reverse()
        local with_dots = reversed:gsub('(%d%d%d)', '%1.'):reverse()
        if with_dots:sub(1, 1) == '.' then
            with_dots = with_dots:sub(2)
        end
        return with_dots
    end

    function samp_create_sync_data(sync_type, copy_from_player)
        copy_from_player = copy_from_player or true
        local sync_traits = {
            player = { 'PlayerSyncData', raknet.PACKET.PLAYER_SYNC, sampStorePlayerOnfootData },
            vehicle = { 'VehicleSyncData', raknet.PACKET.VEHICLE_SYNC, sampStorePlayerIncarData },
            passenger = { 'PassengerSyncData', raknet.PACKET.PASSENGER_SYNC, sampStorePlayerPassengerData },
            aim = { 'AimSyncData', raknet.PACKET.AIM_SYNC, sampStorePlayerAimData },
            trailer = { 'TrailerSyncData', raknet.PACKET.TRAILER_SYNC, sampStorePlayerTrailerData },
            unoccupied = { 'UnoccupiedSyncData', raknet.PACKET.UNOCCUPIED_SYNC, nil },
            bullet = { 'BulletSyncData', raknet.PACKET.BULLET_SYNC, nil },
            spectator = { 'SpectatorSyncData', raknet.PACKET.SPECTATOR_SYNC, nil }
        }
        local sync_info = sync_traits[sync_type]
        if not sync_info then return end
        local data_type = 'struct ' .. sync_info[1]
        local data = ffi.new(data_type, {})
        local raw_data_ptr = tonumber(ffi.cast('uintptr_t', ffi.new(data_type .. '*', data)))
        if copy_from_player then
            local copy_func = sync_info[3]
            if copy_func then
                local _, player_id
                if copy_from_player == true then
                    _, player_id = sampGetPlayerIdByCharHandle(PLAYER_PED)
                else
                    player_id = tonumber(copy_from_player)
                end
                copy_func(player_id, raw_data_ptr)
            end
        end
        local func_send = function()
            local bs = raknetNewBitStream()
            raknetBitStreamWriteInt8(bs, sync_info[2])
            raknetBitStreamWriteBuffer(bs, raw_data_ptr, ffi.sizeof(data))
            raknetSendBitStreamEx(bs, sampfuncs.HIGH_PRIORITY, sampfuncs.UNRELIABLE_SEQUENCED, 1)
            raknetDeleteBitStream(bs)
        end
        local mt = {
            __index = function(t, index) return data[index] end,
            __newindex = function(t, index, value) data[index] = value end
        }
        return setmetatable({ send = func_send }, mt)
    end

    function self.pressButton(keysData)
        local sync = samp_create_sync_data('player')
        sync.keysData = keysData
        sync:send()
    end

    function self.sendVehiclePos(x, y, z)
        local sync = samp_create_sync_data('vehicle')
        sync.position = { x, y, z }
        sync:send()
    end

    function self.sendPlayerPos(x, y, z)
        local sync = samp_create_sync_data('player')
        sync.position = { x, y, z }
        sync:send()
    end

    function self.pressHorn()
        local keysData = samp_create_sync_data('vehicle').keysData
        keysData.keysData = bit.bor(keysData.keysData, 1)
        self.pressButton(keysData)
    end

    return self
end)()

function isArizonaServer()
    local serverName = sampGetCurrentServerName()
    local isMatch = serverName:match("^Arizona [^|]+ | ([^|]+) |") or serverName:match("^Arizona [^|]+ | ([^|]+)$")
    return isMatch ~= nil
end

function smart_wait(total_duration_ms, start_time_clock)
    if start_time_clock then
        local remaining_time_ms = total_duration_ms - (os.clock() - start_time_clock) * 1000

        if remaining_time_ms > 0 then
            wait(remaining_time_ms)
        else
            wait(0)
        end
    else
        wait(total_duration_ms)
    end
end

function fixI()
    lua_thread.create(function()
        wait(0)
        data.fix = true
        sampSendChat("/mm")
        wait(2000)
        data.fix = false
    end)
end

function runTaskAndReopenDialog(taskFunction, ...)
    taskFunction(...)
    lua_thread.create(function()
        while data.working do wait(50) end
        wait(200)
        if sampIsDialogActive() then sampCloseCurrentDialogWithButton(0) end
        sampSendChat("/flashminer")
    end)
end

function main()
    repeat wait(0) until isSampAvailable() and isSampfuncsLoaded()
    while not isSampLoaded() do wait(0) end
    while not sampGetCurrentServerName():find('Arizona') and not sampGetCurrentServerName():find('Rodina') do wait(0) end
    data.isRodina = not isArizonaServer()
    if data.isRodina then
        dialogIdTable = dialogIdTableRodina
    else
        dialogIdTable = dialogIdTableArizona
    end

    utils.addChat('Загружен. Команда: {ffc0cb}/mnt{ffffff}.')

    sampRegisterChatCommand('mnt', function()
        cfg.active = not cfg.active
        utils.addChat(cfg.active and "Скрипт {99ff99}включен." or "Скрипт {F78181}отключен.")
        save()
    end)

    if cfg.isReloaded then
        cfg.isReloaded = false
        save()
    end

    local waitingForDialogClose = sampIsDialogActive() and
        sampGetCurrentDialogId() == dialogIdTable.houseFlashMinerDialogId

    if sampIsDialogActive() then
        local id = sampGetCurrentDialogId()
        if id == dialogIdTable.houseFlashMinerDialogId then
            waitingForDialogClose = true
        end
    end
    addEventHandler('onWindowMessage', function(msg, wparam, lparam)
        if sampIsChatInputActive() then return end
        if msg ~= wm.WM_KEYDOWN then return end

        if data.showHouseControlWindow[0] and wparam == 27 then -- ESC
            if not data.lastWindowState.houseControl then
                consumeWindowMessage(true, false)
                return
            end
            consumeWindowMessage(true, false)
            sampCloseCurrentDialogWithButton(0)
            data.showHouseControlWindow[0] = false
            fixI()
            return
        end
        if #data.dialogData.flashminer > 0 and data.showHouseControlWindow[0] then
            if wparam == 40 then -- Стрелка ВНИЗ
                consumeWindowMessage(true, false)
                data.selectedHouseIndex = data.selectedHouseIndex + 1
                if data.selectedHouseIndex > #data.dialogData.flashminer then
                    data.selectedHouseIndex = 1
                end
                data.scrollToSelection = true
                return
            end

            if wparam == 38 then -- Стрелка ВВЕРХ
                consumeWindowMessage(true, false)
                data.selectedHouseIndex = data.selectedHouseIndex - 1
                if data.selectedHouseIndex < 1 then
                    data.selectedHouseIndex = #data.dialogData.flashminer -- Переход в конец списка
                end
                data.scrollToSelection = true
                return
            end

            if wparam == 13 then -- ENTER
                if not data.lastWindowState.houseControl then
                    consumeWindowMessage(true, false)
                    return
                end
                local selectedHouse = data.dialogData.flashminer[data.selectedHouseIndex]
                if selectedHouse then
                    sampSendDialogResponse(data.dFlashminerId, 1, selectedHouse.index - 1, "")
                    data.showHouseControlWindow[0] = false
                    data.lastSelectedHouse = selectedHouse.house_number
                end
            end
            return
        end

        if data.main[0] then -- ESC
            if not data.lastWindowState.main then
                consumeWindowMessage(true, false)
                return
            end

            if wparam == 27 then
                consumeWindowMessage(true, false)
                data.main[0] = false
            elseif wparam == 37 then
                consumeWindowMessage(true, false)
                navigateFlashminer(-1)
            elseif wparam == 39 then
                consumeWindowMessage(true, false)
                navigateFlashminer(1)
            end
        end
    end)

    while true do
        wait(0)
        data.lastWindowState.main = data.main[0]
        data.lastWindowState.houseControl = data.showHouseControlWindow[0]
        if cfg.active then
            local id = sampGetCurrentDialogId()
            local isVideocardListActive = (id == dialogIdTable.houseFlashMinerDialogId or id == dialogIdTable.videoCardSt) and
                sampIsDialogActive() and not data.showHouseControlWindow[0]
            if waitingForDialogClose and not isVideocardListActive then
                waitingForDialogClose = false
            end
            data.main[0] = (isVideocardListActive and not waitingForDialogClose) or
                (data.main[0] and data.working and not data.showHouseControlWindow[0])
            data.showHouseControlWindow[0] = not cfg.useDialogMode and data.showHouseControlWindow[0]
        end
    end
end

function sendcef(str)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 18)
    raknetBitStreamWriteInt16(bs, #str)
    raknetBitStreamWriteString(bs, str)
    raknetBitStreamWriteInt32(bs, 0)
    raknetSendBitStream(bs)
    raknetDeleteBitStream(bs)
end

local dialogsToHideDuringTask = {
    titles = {
        "{BFBBBA}Выбор дома",
        "Вывод прибыли видеокарты",
        "Выберите тип жидкости",
        "^Полка №%d+",
        "^Стойка №%d+"
    },

    texts = {
        "Забрать прибыль",
        "Достать видеокарту",
        "Баланс Bitcoin"
    }
}

function sampev.onShowDialog(dialogId, style, title, button1, button2, text, placeholder)
    if not cfg.active then return end
    if data.fix and title:find("Игровое меню") then
        sampSendDialogResponse(dialogId, 0, 0, "")
        return false
    end

    if (data.activeTaskState and data.working) and ((dialogId == dialogIdTable.houseListBankId and title:find("Выбо")) or dialogId == dialogIdTable.topUpBalanceDialogId or dialogId == dialogIdTable.payAllTaxesDialogId) then
        return false
    end

    if data.working then
        for _, pattern in ipairs(dialogsToHideDuringTask.titles) do
            if title:find(pattern) then
                return false
            end
        end
        for _, pattern in ipairs(dialogsToHideDuringTask.texts) do
            if text:find(pattern) then
                return false
            end
        end
    end

    if title:find("Выбор дома") then
        if text:match("циклов %(%$%d+") then
            data.isFlashminer = true
            data.dFlashminerId = dialogId
            _formatHouseList(text)
            if data.flashminerSwitchId.direction ~= 0 then
                local base_index
                if data.forImgui.dTitle and data.forImgui.dTitle ~= "Неизвестно" then
                    for i, house in ipairs(data.dialogData.flashminer) do
                        if house.name:find(data.forImgui.dTitle) then
                            base_index = i
                            break
                        end
                    end
                end
                if not base_index then
                    base_index = data.flashminerSwitchId.direction == 1 and 0 or #data.dialogData.flashminer + 1
                end
                local next_index = base_index + data.flashminerSwitchId.direction
                if next_index > #data.dialogData.flashminer then next_index = 1 end
                if next_index < 1 then next_index = #data.dialogData.flashminer end

                if data.dialogData.flashminer[next_index] then
                    local next_house = data.dialogData.flashminer[next_index]
                    data.forImgui.dTitle = tostring(next_house.house_number)
                    sampSendDialogResponse(dialogId, 1, next_house.index - 1, "")
                else
                    data.flashminerSwitchId.direction = 0
                end

                return false
            end
        else
            return
        end
        if cfg.useDialogMode then
            local newText = text .. "\n "
            newText = newText .. "\n{33CC33}» Включить все видеокарты"
            newText = newText .. "\n"
            newText = newText .. "\n{FFFF00}» Собрать криптовалюту со всех домов"
            newText = newText .. "\n"
            newText = newText .. "\n{FF3333}» Выключить все видеокарты"
            return { dialogId, style, title, button1, button2, newText, placeholder }
        else
            data.showHouseControlWindow[0] = true
            local foundIndex = 1
            if data.lastSelectedHouse ~= -1 then
                for i, house in ipairs(data.dialogData.flashminer) do
                    if house.house_number == data.lastSelectedHouse then
                        foundIndex = i
                        break
                    end
                end
            end
            data.selectedHouseIndex = foundIndex
            data.scrollToSelection = true
            if not data.working and (cfg.lastKnownHouseCount ~= #data.dialogData.flashminer or cfg.lastKnownHouseCount == -1) then
                local task = buildTaskTable('scanBasements')
                runTaskAndReopenDialog(function() task:run() end)
            end
            if not data.initialScanCompleted and not data.working then
                local task = buildTaskTable('updateStatuses')
                runTaskAndReopenDialog(function() task:run() end)
            end
            return false
        end
    end

    if title:find("^{......}Выберите видеокарту") or title:find("^Полка №%d+") or text:find("Баланс Bitcoin") or text:find('Обзор всех видеокарт') then
        data.flashminerSwitchId.direction = 0
        data.flashminerSwitchId.currentIndex = nil
        data.isFlashminer = title:find("%(дом №%d+%)") ~= nil
        data.dFlashminerId = dialogId
        local houseNum = title:match("дом №(%d+)")
        data.forImgui = {
            dTitle = title:match("дом №(%d+)") or title:match("Полка №(%d+)") or title:match("Стойка №(%d+)") or
                "Неизвестно",
            allGood = true,
            videocardCount = 0,
            earnings = { btc = 0, asc = 0 },
            attentionTime = 101,
        }
        data.dialogData.videocards = {}
        local listbox_index = -1
        for line in text:gmatch("[^\n\r]+") do
            listbox_index = listbox_index + 1
            if line:find("{......}Работает") or line:find("{......}На паузе") then
                local card = {
                    index = listbox_index,
                    working = line:find("{......}Работает") and true or false,
                    btc = tonumber(select(1, line:match("(%d+)%.%d+ BTC"))) or 0,
                    asc = tonumber(select(1, line:match("(%d+)%.%d+ ASC"))) or 0,
                    coolant = tonumber(line:match("(%d+%.%d+)%%?%s*$")) or 0,
                    fluidType = line:find("BTC") and 1 or (line:find("ASC") and 2 or 0),
                    level = tonumber(line:match("(%d+) уровень")) or 0,
                    id = dialogId
                }
                table.insert(data.dialogData.videocards, card)
                if not card.working or card.coolant < cfg.useCoolantPercent then data.forImgui.allGood = false end
                if card.coolant < data.forImgui.attentionTime then data.forImgui.attentionTime = card.coolant end
                data.forImgui.earnings.btc = data.forImgui.earnings.btc + card.btc
                data.forImgui.earnings.asc = data.forImgui.earnings.asc + card.asc
                data.forImgui.videocardCount = data.forImgui.videocardCount + 1
            end
        end

        if houseNum and not cfg.useDialogMode then
            local currentHouseData = nil
            for _, h in ipairs(data.dialogData.flashminer) do
                if h.house_number == tonumber(houseNum) then
                    currentHouseData = h
                    break
                end
            end
            updateHouseStatus(tonumber(houseNum), currentHouseData)
        end
        if (not data.initialScanCompleted and not cfg.useDialogMode) or data.taskTypeNow == 'updateStatuses' then return false end
    end
end

function sampev.onDialogClose(dialogId, button, listitem, input)
    if dialogId == data.dFlashminerId then
        data.showHouseControlWindow[0] = false
    end
end

function sampev.onServerMessage(color, text)
    if not cfg.active then return end
    if text:find("^Вы вывели {ffffff}%d+ [BTCASC]+{ffff00}") then
        if text:find("BTC") then
            data.withdraw.btc = data.withdraw.btc + tonumber(text:match("Вы вывели {ffffff}(%d+)"))
        elseif text:find("ASC") then
            data.withdraw.asc = data.withdraw.asc + tonumber(text:match("Вы вывели {ffffff}(%d+)"))
        end
        return false
    elseif text:find("^Вам был добавлен предмет") and (text:find(":item1811:") or text:find(":item5996:") or text:find("BTC") or text:find("ASC")) then
        return false
    elseif text:find("^Добавлено в инвентарь") and text:find("BTC") then
        data.withdraw.btc = data.withdraw.btc + (tonumber(text:match('%((%d+) шт%)')) or 1)
        return false
    elseif text:find("Выводить прибыль можно только целыми частями и минимум 1 целый коин.") then
        return false
    elseif text:find("Выберите дом с майнинг фермой") then
        return false
    elseif text:find("В этом доме нет подвала с вентиляцией или он еще не достроен.") then
        if data.working then
            data.houseHasNoBasement = true
            return false
        end
        if data.flashminerSwitchId.direction ~= 0 then
            sampSendChat("/flashminer")
            return false
        end
    elseif text:find("охлаждающей жидкости в видеокарту, состояние системы охлаждения восстановлено") then
        return false
    elseif text:find("дом в котором хотите пополнить счёт") and data.working then
        return false
    elseif text:find("Вы успешно пополнили счёт дома за") and data.working then
        return false
    elseif text:find("Вы оплатили все налоги на сумму") and data.working then
        local amount_str = text:match("%$([%d%.,%s]+)")
        if amount_str then
            local clean_str = amount_str:gsub("[^%d]", "")
            if clean_str and clean_str ~= "" then
                local amount = tonumber(clean_str) or 0
                data.capturedTaxAmount = amount
            end
        end
        return false
    end
end

function sampev.onSendDialogResponse(dialogId, button, listitem, input)
    local cleanInput = input:gsub("{%x%x%x%x%x%x}", "")
    if cleanInput:find("» Собрать криптовалюту со всех домов") and button == 1 then
        local task = buildTaskTable('collectFromAllHouses')
        runTaskAndReopenDialog(function() task:run() end)
        return false
    end
    if cleanInput:find("» Включить все видеокарты") and button == 1 then
        local task = buildTaskTable('massSwitchCards')
        runTaskAndReopenDialog(function() task:run(true) end)
        return false
    end
    if cleanInput:find("» Выключить все видеокарты") and button == 1 then
        local task = buildTaskTable('massSwitchCards')
        runTaskAndReopenDialog(function() task:run(false) end)
        return false
    end
    if dialogId == data.dFlashminerId then
        data.showHouseControlWindow[0] = false
    end
    return true
end

function _formatHouseList(text)
    data.dialogData.flashminer = {}

    for line in text:gmatch("[^\r\n]+") do
        if line:find("Номер дома") or line:find("Город") or line:find("Налог") then
            goto continue
        end

        local list_id, house_num = line:match("%[(%d+)%]%s+Дом №(%d+)")
        if not (list_id and house_num) then goto continue end

        local after_num = (line:match("Дом №%d+%s+(.+)") or ""):gsub("{%w+}", "")
        local parts = {}
        for w in after_num:gmatch("%S+") do table.insert(parts, w) end

        local city, tax, cycles, balance, max_balance = "", nil, 0, 0, 0
        local cycles_index
        for i, part in ipairs(parts) do
            if part == "циклов" then
                cycles_index = i
                break
            end
        end

        if cycles_index then
            cycles = tonumber(parts[cycles_index - 1]) or 0
            tax = tonumber(parts[cycles_index - 2])
            local city_end = tax and (cycles_index - 3) or (cycles_index - 2)
            if city_end >= 1 then
                city = table.concat({ table.unpack(parts, 1, city_end) }, " ")
            else
                city = ""
            end

            local bal_paren = after_num:match("%(([^%)]+)%)")
            if bal_paren then
                local bstr, mstr = bal_paren:match("([%$%d%.%s]+)%s*/%s*([%$%d%.%s]+)")
                if not bstr then
                    bstr, mstr = bal_paren:match("([^/]+)%s*/%s*([^/]+)")
                end
                if bstr then
                    local clean_b = bstr:gsub("[%$%.%s]", "")
                    balance = tonumber(clean_b) or 0
                end
                if mstr then
                    local clean_m = mstr:gsub("[%$%.%s]", "")
                    max_balance = tonumber(clean_m) or 0
                end
            end
        end

        local house_data = {
            index = tonumber(list_id),
            name = "Дом №" .. house_num,
            house_number = tonumber(house_num),
            city = city,
            tax = tax,
            cycles = cycles,
            balance = balance,
            max_balance = max_balance,
            raw_line = line
        }

        table.insert(data.dialogData.flashminer, house_data)
        if not data.houseStatuses then data.houseStatuses = {} end
        if not data.houseStatuses[house_data.house_number] then
            data.houseStatuses[house_data.house_number] = {
                status = balance < 5000000 and "warning" or "good",
                lastCheck = 0,
                needsAttention = false,
                lastBalance = balance
            }
        end

        ::continue::
    end
end

function updateHouseStatus(houseNumber, houseData)
    if not data.houseStatuses[houseNumber] then
        data.houseStatuses[houseNumber] = {
            status = "unknown",
            lastCheck = 0,
            issues = {},
            earnings = { btc = 0, asc = 0 },
            minCoolant = 101,
            cardLevels = {}
        }
    end

    local status = data.houseStatuses[houseNumber]
    status.lastCheck = os.time()
    status.issues = {}
    status.earnings = { btc = 0, asc = 0 }
    status.minCoolant = 101
    status.cardLevels = {}

    local cardsOff = 0
    local cardsLowCoolant = 0
    local totalCards = #data.dialogData.videocards

    if totalCards > 0 then
        for _, card in ipairs(data.dialogData.videocards) do
            if not card.working then
                cardsOff = cardsOff + 1
            end
            if card.coolant < cfg.useCoolantPercent then
                cardsLowCoolant = cardsLowCoolant + 1
            end
            if card.coolant < status.minCoolant then
                status.minCoolant = card.coolant
            end
            if card.level and card.level > 0 then
                if not status.cardLevels[card.level] then
                    status.cardLevels[card.level] = { total = 0, working = 0 }
                end
                status.cardLevels[card.level].total = status.cardLevels[card.level].total + 1
                if card.working then
                    status.cardLevels[card.level].working = status.cardLevels[card.level].working + 1
                end
            end

            status.earnings.btc = status.earnings.btc + card.btc
            status.earnings.asc = status.earnings.asc + card.asc
        end
        if cardsOff > 0 then
            table.insert(status.issues, string.format("Выключено видеокарт: %d/%d", cardsOff, totalCards))
        end
        if cardsLowCoolant > 0 then
            table.insert(status.issues, string.format("Мало жидкости: %d/%d", cardsLowCoolant, totalCards))
        end
    else
        status.minCoolant = 0
    end

    if houseData and houseData.balance < 5000000 then
        table.insert(status.issues, string.format("Низкий баланс: $%s", utils.formatNumber(houseData.balance)))
    end

    if houseData and houseData.tax then
        if houseData.tax >= 90000 then
            table.insert(status.issues, string.format("Высокий налог: $%s", utils.formatNumber(houseData.tax)))
        elseif houseData.tax >= 50000 then
            table.insert(status.issues, string.format("Повышенный налог: $%s", utils.formatNumber(houseData.tax)))
        end
    end
    if cardsOff > 0 or cardsLowCoolant > 0 or (houseData and houseData.tax and houseData.tax >= 90000) then
        status.status = "bad"
    elseif houseData and (houseData.balance < 5000000 or (houseData.tax and houseData.tax >= 50000)) then
        status.status = "warning"
    else
        status.status = "good"
    end
end

function navigateFlashminer(direction)
    if data.working then return end
    data.flashminerSwitchId.direction = direction
    data.flashminerSwitchId.id = data.dFlashminerId
    data.isSwitchingHouse = true
    sampSendDialogResponse(data.dFlashminerId, 0, -1, "")
end

function buildTaskTable(taskType, ...)
    local function createProtectedTask(taskFunction, ...)
        if data.working then
            utils.addChat("{F78181}Уже выполняется другая операция.")
            return
        end
        local args = { ... }
        lua_thread.create(function()
            data.working = true
            data.taskTypeNow = taskType
            local action_count = 0
            any_dialog_clock = os.clock()
            local function sendResponse(...)
                sampSendDialogResponse(...)
                action_count = action_count + 1
                if not data.isRodina and action_count > 0 and action_count % cfg.count_action == 0 and
                    os.clock() - (data.dialogTimer or 0) < cfg.pause_duration then
                    wait(cfg.pause_duration)
                end
                data.dialogTimer = os.clock()
            end

            local success, err = pcall(function() taskFunction(sendResponse, unpack(args)) end)

            if not success then
                utils.addChat("{F78181}Критическая ошибка: " .. tostring(err))
                if sampIsDialogActive() then
                    sampCloseCurrentDialogWithButton(0)
                end
            end
            --smart_wait(600, any_dialog_clock)
            wait(300)
            data.working = false
            data.taskTypeNow = ''
        end)
    end

    local task = {
        data = {
            mainId = data.dFlashminerId,
            listBoxes = {}
        }
    }

    if taskType == 'coolant' then
        task.coolant = function(self)
            local cardsToProcess = {}
            for _, card in ipairs(self.data.listBoxes) do
                if card.coolant < cfg.useCoolantPercent then table.insert(cardsToProcess, card) end
            end

            if #cardsToProcess == 0 then return utils.addChat("Во всех видеокартах достаточно охлаждающей жидкости.") end
            createProtectedTask(function(sendResponse)
                for _, card in ipairs(cardsToProcess) do
                    local refill_count = cfg.useSuperCoolant and 1 or ((card.coolant < 50.0) and 2 or 1)
                    if not cfg.useSuperCoolant and cfg.economyMode and (card.coolant + 50) > 70 then refill_count = 1 end
                    for i = 1, refill_count do
                        sendResponse(self.data.mainId, 1, card.index - 1, "")
                        sendResponse(dialogIdTable.videoCardDialogId, 1, data.isRodina and 2 or 3, "")

                        local fluid_listitem = (card.fluidType == 1 and (cfg.useSuperCoolant and 1 or 0)) or
                            (card.fluidType == 2 and (cfg.useSuperCoolant and 1 or 3))
                        if fluid_listitem ~= nil then
                            sendResponse(dialogIdTable.coolantDialogId, 1, fluid_listitem, "")
                        else
                            utils.addChat("Ошибка: не удалось определить тип жидкости для карты.")
                        end
                    end
                    sendResponse(dialogIdTable.videoCardDialogId, 0, 0, "")
                end
            end)
        end
    elseif taskType == 'switchCards' then
        task.switchCards = function(self, enable)
            local cardsToProcess = {}
            for _, card in ipairs(self.data.listBoxes) do
                if card.working == (not enable) then table.insert(cardsToProcess, card) end
            end

            if #cardsToProcess == 0 then
                return utils.addChat("Видеокарты и так уже " ..
                    ((enable and "включены." or "выключены.")))
            end
            createProtectedTask(function(sendResponse)
                for i, card in ipairs(cardsToProcess) do
                    sendResponse(self.data.mainId, 1, card.index - 1, "")
                    sendResponse(dialogIdTable.videoCardDialogId, 1, 0, "")
                    sendResponse(dialogIdTable.videoCardDialogId, 0, 0, "")
                end
            end)
        end
    elseif taskType == 'takeCrypto' then
        task.takeCrypto = function(self)
            local cardsToProcess = {}
            for _, card in ipairs(self.data.listBoxes) do
                if card.btc >= 1 or card.asc >= 1 then table.insert(cardsToProcess, card) end
            end

            if #cardsToProcess == 0 then return utils.addChat("Нет криптовалюты для снятия.") end
            data.withdraw = { asc = 0, btc = 0 }
            createProtectedTask(function(sendResponse)
                for _, card in pairs(cardsToProcess) do
                    sendResponse(self.data.mainId, 1, card.index - 1, "")

                    if card.btc >= 1 then
                        sendResponse(dialogIdTable.videoCardDialogId, 1, 1, "")
                        sendResponse(dialogIdTable.videoCardAcceptDialogId, 1, 0, "")
                    end

                    if card.asc >= 1 then
                        sendResponse(dialogIdTable.videoCardDialogId, 1, 2, "")
                        sendResponse(dialogIdTable.videoCardAcceptDialogId, 1, 0, "")
                    end

                    if data.isRodina then
                        utils.pressButton(1024)
                        wait(1000)
                        while not (sampIsDialogActive() and sampGetCurrentDialogId() == self.data.mainId) do wait(50) end
                    else
                        sendResponse(dialogIdTable.videoCardDialogId, 0, 0, "")
                    end
                end
                wait(250)
                if data.withdraw.btc > 0 or data.withdraw.asc > 0 then
                    utils.addChat("Выведено: " ..
                        (data.withdraw.btc > 0 and ("{99ff99}%d BTC"):format(data.withdraw.btc) or "") ..
                        (data.withdraw.btc > 0 and data.withdraw.asc > 0 and "{ffffff} и " or "") ..
                        (data.withdraw.asc > 0 and ("{ffa500}%d ASC"):format(data.withdraw.asc) or "") .. "{ffffff}.")
                end
            end)
        end
    elseif taskType == 'collectFromAllHouses' then
        task.run = function(self)
            local houses = {}
            for _, h in ipairs(data.dialogData.flashminer) do table.insert(houses, h) end
            if not houses or #houses == 0 then
                utils.addChat("{F78181}Список домов не найден. Повторите попытку.")
                return false
            end
            data.withdraw = { asc = 0, btc = 0 }
            utils.addChat("Начинаю сбор криптовалюты со всех домов...")
            createProtectedTask(function(sendResponse)
                for i, house in ipairs(houses) do
                    if cfg.housesWithoutBasement and cfg.housesWithoutBasement[house.house_number] then
                        utils.addChat(string.format("Пропускаю %s - нет подвала (из кэша).", house.name))
                        goto continue_loop
                    end
                    sendResponse(dialogIdTable.houseDialogId, 1, house.index - 1, "")
                    wait(300)
                    if not cfg.useDialogMode then updateHouseStatus(house.house_number, house) end
                    local cardsInThisHouse = {}

                    for _, cardData in ipairs(data.dialogData.videocards) do
                        if cardData.btc >= 1 or cardData.asc >= 1 then
                            table.insert(cardsInThisHouse, cardData)
                        end
                    end

                    if #cardsInThisHouse > 0 then
                        for _, card in ipairs(cardsInThisHouse) do
                            sendResponse(dialogIdTable.houseFlashMinerDialogId, 1, card.index - 1, "")
                            if card.btc >= 1 then
                                sendResponse(dialogIdTable.videoCardDialogId, 1, 1, "")
                                sendResponse(dialogIdTable.videoCardAcceptDialogId, 1, 0, "")
                            end
                            if card.asc >= 1 then
                                sendResponse(dialogIdTable.videoCardDialogId, 1, 2, "")
                                sendResponse(dialogIdTable.videoCardAcceptDialogId, 1, 0, "")
                            end
                            sendResponse(dialogIdTable.videoCardDialogId, 0, 0, "")
                        end
                        wait(300)
                    end
                    sendResponse(dialogIdTable.houseFlashMinerDialogId, 0, 0, "")
                    ::continue_loop::
                end

                wait(250)
                utils.addChat("{BEF781}Обход всех домов завершен.")
                if data.withdraw.btc > 0 or data.withdraw.asc > 0 then
                    local btc_part = data.withdraw.btc > 0 and ("{99ff99}%d BTC"):format(data.withdraw.btc) or ""
                    local asc_part = data.withdraw.asc > 0 and ("{ffa500}%d ASC"):format(data.withdraw.asc) or ""
                    local separator = (data.withdraw.btc > 0 and data.withdraw.asc > 0) and "{ffffff} и " or ""
                    utils.addChat("Всего собрано: " .. btc_part .. separator .. asc_part .. "{ffffff}.")
                else
                    utils.addChat("Не было собрано ни одной целой монеты.")
                end
            end)
        end
    elseif taskType == 'massSwitchCards' then
        task.run = function(self, enable)
            local houses = {}

            for _, h in ipairs(data.dialogData.flashminer) do table.insert(houses, h) end
            if not houses or #houses == 0 then
                utils.addChat("{F78181}Список домов не найден. Повторите попытку.")
                return false
            end

            local actionText = enable and "Включаю" or "Выключаю"

            utils.addChat(actionText .. " видеокарты во всех домах...")
            createProtectedTask(function(sendResponse, enable_arg)
                for i, house in ipairs(houses) do
                    if cfg.housesWithoutBasement and cfg.housesWithoutBasement[house.house_number] then
                        utils.addChat(string.format("Пропускаю %s - нет подвала (из кэша).", house.name))
                        goto continue_loop
                    end
                    sendResponse(dialogIdTable.houseDialogId, 1, house.index - 1, "")
                    wait(300)
                    if not cfg.useDialogMode then updateHouseStatus(house.house_number, house) end
                    local cardsToSwitch = {}

                    for _, cardData in ipairs(data.dialogData.videocards) do
                        if (enable_arg and not cardData.working) or (not enable_arg and cardData.working) then
                            table.insert(cardsToSwitch, cardData)
                        end
                    end
                    if #cardsToSwitch > 0 then
                        for _, card in ipairs(cardsToSwitch) do
                            sendResponse(dialogIdTable.houseFlashMinerDialogId, 1, card.index - 1, "")
                            sendResponse(dialogIdTable.videoCardDialogId, 1, 0, "")
                            sendResponse(dialogIdTable.videoCardDialogId, 0, 0, "")
                        end
                        wait(300)
                    end
                    sendResponse(dialogIdTable.houseFlashMinerDialogId, 0, 0, "")
                    ::continue_loop::
                end
                wait(250)
                utils.addChat("{BEF781}Переключение видеокарт завершено.")
            end, enable)
        end
    elseif taskType == 'updateStatuses' then
        task.run = function(self)
            local houses = {}
            for _, h in ipairs(data.dialogData.flashminer) do table.insert(houses, h) end
            if not houses or #houses == 0 then return false end
            createProtectedTask(function(sendResponse)
                for i, house in ipairs(houses) do
                    if cfg.housesWithoutBasement and cfg.housesWithoutBasement[house.house_number] then
                        goto continue_loop
                    end
                    sendResponse(dialogIdTable.houseDialogId, 1, house.index - 1, "")
                    smart_wait(150, any_dialog_clock)
                    updateHouseStatus(house.house_number, house)
                    sendResponse(dialogIdTable.houseFlashMinerDialogId, 0, 0, "")
                    ::continue_loop::
                end

                if not data.initialScanCompleted then
                    data.initialScanCompleted = true
                end
            end)
        end
    elseif taskType == 'scanBasements' then
        task.run = function(self)
            local houses = {}
            for _, h in ipairs(data.dialogData.flashminer) do table.insert(houses, h) end
            if not houses or #houses == 0 then return false end
            createProtectedTask(function(sendResponse)
                cfg.housesWithoutBasement = {}
                for i, house in ipairs(houses) do
                    data.houseHasNoBasement = false
                    sendResponse(dialogIdTable.houseDialogId, 1, house.index - 1, "")
                    local start_time = os.clock()
                    while os.clock() - start_time < 0.5 do
                        wait(50)
                        if data.houseHasNoBasement then break end
                    end

                    if data.houseHasNoBasement then
                        cfg.housesWithoutBasement[house.house_number] = true
                        sampSendChat("/flashminer")
                        wait(150)
                    else
                        sendResponse(dialogIdTable.houseFlashMinerDialogId, 0, 0, "")
                    end
                end
                cfg.lastKnownHouseCount = #houses

                save()
            end)
        end
    elseif taskType == 'fixAllProblems' then
        task.run = function(self)
            local houses = {}
            for _, h in ipairs(data.dialogData.flashminer) do table.insert(houses, h) end
            if not houses or #houses == 0 then
                utils.addChat("{F78181}Список домов не найден. Сначала обновите его.")
                return false
            end
            createProtectedTask(function(sendResponse)
                local summary = {
                    btc_collected = 0,
                    asc_collected = 0,
                    cards_switched_on = 0,
                    money_on_balance = 0,
                    taxes_paid = 0,
                    houses_to_top_up = {},
                    houses_with_high_tax = {}
                }
                for _, house in ipairs(houses) do
                    if data.houseStatuses[house.house_number] and data.houseStatuses[house.house_number].hasBasement == false then
                        goto continue_analysis
                    end
                    if house.balance < cfg.targetHouseBalance and (cfg.targetHouseBalance - house.balance) > 10000 then
                        table.insert(summary.houses_to_top_up, house)
                    end
                    if house.tax and house.tax >= cfg.taxPayment then
                        table.insert(summary.houses_with_high_tax, house)
                    end
                    ::continue_analysis::
                end

                if #summary.houses_to_top_up > 0 then
                    data.activeTaskState = true

                    sampSendChat("/phone")
                    sendcef('launchedApp|24')
                    sampSendChat("/phone")
                    sendResponse(dialogIdTable.phoneBankMenuId, 1, 10, "") -- Банк -> Пополнить счёт на электричество

                    for i, house in ipairs(summary.houses_to_top_up) do
                        local total_amount_needed = math.min(cfg.targetHouseBalance - 1, 19999999) - house.balance

                        if total_amount_needed < 10000 then
                            goto continue_top_up_loop
                        end

                        local amounts_to_deposit = {}
                        local remaining_to_add = total_amount_needed
                        while remaining_to_add >= 10000 do
                            local amount_this_transaction = math.min(remaining_to_add, 10000000)
                            local leftover = remaining_to_add - amount_this_transaction
                            if leftover > 0 and leftover < 10000 then
                                amount_this_transaction = amount_this_transaction - 10000
                            end
                            if amount_this_transaction >= 10000 then
                                table.insert(amounts_to_deposit, amount_this_transaction)
                                remaining_to_add = remaining_to_add - amount_this_transaction
                            else
                                break
                            end
                        end
                        if remaining_to_add >= 10000 then
                            table.insert(amounts_to_deposit, remaining_to_add)
                        end

                        for _, amount in ipairs(amounts_to_deposit) do
                            sendResponse(dialogIdTable.houseListBankId, 1, house.index - 1, "")
                            sendResponse(dialogIdTable.topUpBalanceDialogId, 1, 0, tostring(amount))
                            summary.money_on_balance = summary.money_on_balance + amount
                        end

                        ::continue_top_up_loop::
                    end

                    if sampIsDialogActive() and sampGetCurrentDialogId() == dialogIdTable.houseDialogId then
                        sendResponse(dialogIdTable.houseListBankId, 0, 0, "")
                    end
                    data.activeTaskState = false
                    wait(100)
                end

                for i, house in ipairs(houses) do
                    if cfg.housesWithoutBasement and cfg.housesWithoutBasement[house.house_number] then
                        utils.addChat(string.format("Пропускаю %s - нет подвала (из кэша).", house.name))
                        goto continue_main_loop
                    end

                    sendResponse(dialogIdTable.houseDialogId, 1, house.index - 1, "")
                    wait(500)

                    local cardsToCollect = {}
                    local cardsToSwitchOn = {}

                    for _, cardData in ipairs(data.dialogData.videocards) do
                        if cardData.btc >= 1 or cardData.asc >= 1 then
                            table.insert(cardsToCollect, cardData)
                        end
                        if not cardData.working and cardData.coolant >= cfg.useCoolantPercent then
                            table.insert(cardsToSwitchOn, cardData)
                        end
                    end
                    if not cfg.useDialogMode then updateHouseStatus(house.house_number, house) end
                    if #cardsToCollect > 0 or #cardsToSwitchOn > 0 then
                        -- Сбор криптовалюты
                        for _, card in ipairs(cardsToCollect) do
                            sendResponse(dialogIdTable.houseFlashMinerDialogId, 1, card.index - 1, "")
                            if card.btc >= 1 then
                                sendResponse(dialogIdTable.videoCardDialogId, 1, 1, "")
                                sendResponse(dialogIdTable.videoCardAcceptDialogId, 1, 0, "")
                                summary.btc_collected = summary.btc_collected + card.btc
                            end
                            if card.asc >= 1 then
                                sendResponse(dialogIdTable.videoCardDialogId, 1, 2, "")
                                sendResponse(dialogIdTable.videoCardAcceptDialogId, 1, 0, "")
                                summary.asc_collected = summary.asc_collected + card.asc
                            end
                            sendResponse(dialogIdTable.videoCardDialogId, 0, 0, "")
                        end
                        wait(300)

                        -- Включение видеокарт
                        for _, card in ipairs(cardsToSwitchOn) do
                            sendResponse(dialogIdTable.houseFlashMinerDialogId, 1, card.index - 1, "")
                            sendResponse(dialogIdTable.videoCardDialogId, 1, 0, "")
                            sendResponse(dialogIdTable.videoCardDialogId, 0, 0, "")
                            summary.cards_switched_on = summary.cards_switched_on + 1
                        end
                        wait(300)
                    end

                    sendResponse(dialogIdTable.houseFlashMinerDialogId, 0, 0, "")
                    ::continue_main_loop::
                end


                if sampIsDialogActive() then
                    sampCloseCurrentDialogWithButton(0)
                end


                if #summary.houses_with_high_tax > 0 then
                    sampSendChat("/phone")
                    sendcef('launchedApp|24')
                    sampSendChat("/phone")
                    sendResponse(dialogIdTable.phoneBankMenuId, 1, 4, "")     -- Выбираем "Оплата всех налогов"
                    sendResponse(dialogIdTable.payAllTaxesDialogId, 1, 0, "") -- Подтверждаем оплату
                    --wait(100)
                    summary.taxes_paid = data.capturedTaxAmount
                end
                wait(100)
                local report = {}
                if summary.btc_collected > 0 or summary.asc_collected > 0 then
                    local btc_part = summary.btc_collected > 0 and string.format("%d BTC", summary.btc_collected) or ""
                    local asc_part = summary.asc_collected > 0 and string.format("%d ASC", summary.asc_collected) or ""
                    local separator = (summary.btc_collected > 0 and summary.asc_collected > 0) and " и " or ""
                    table.insert(report, string.format("Собрано: {BEF781}%s%s%s", btc_part, separator, asc_part))
                end
                if summary.cards_switched_on > 0 then
                    table.insert(report, string.format("Включено видеокарт: {99ff99}%d", summary.cards_switched_on))
                end
                if summary.money_on_balance > 0 then
                    table.insert(report,
                        string.format("Пополнено ферм на: {FFD700}$%s", utils.formatNumber(summary.money_on_balance)))
                end
                if summary.taxes_paid > 0 then
                    table.insert(report,
                        string.format("Оплачено налогов на (приблизительно): {F78181}$%s",
                            utils.formatNumber(summary.taxes_paid)))
                end

                if #report > 0 then
                    utils.addChat("Итоги операции:")
                    for _, line in ipairs(report) do
                        sampAddChatMessage('{ffa500}' .. thisScript().name .. '{ffffff}: ' .. line, -1)
                    end
                else
                    utils.addChat("Никаких действий не потребовалось. Все системы в норме.")
                end
            end)
        end
    end
    return task
end

local fa = require('fAwesome6')

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true
    local iconRanges = imgui.new.ImWchar[3](fa.min_range, fa.max_range, 0)
    imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(fa.get_font_data_base85('solid'), 14, config, iconRanges)
    do
        imgui.SwitchContext()
        local style                       = imgui.GetStyle()
        local colors                      = style.Colors
        local Col                         = imgui.Col
        local ImVec4                      = imgui.ImVec4
        local ImVec2                      = imgui.ImVec2

        colors[Col.Text]                  = ImVec4(1, 1, 1, 1)
        colors[Col.TextDisabled]          = ImVec4(0.5, 0.5, 0.5, 1)
        colors[Col.WindowBg]              = ImVec4(0.07, 0.07, 0.07, 1)
        colors[Col.ChildBg]               = ImVec4(0.07, 0.07, 0.07, 1)
        colors[Col.PopupBg]               = ImVec4(0.07, 0.07, 0.07, 1)
        colors[Col.Border]                = ImVec4(0.25, 0.25, 0.26, 0.54)
        colors[Col.BorderShadow]          = ImVec4(0, 0, 0, 0)
        colors[Col.FrameBg]               = ImVec4(0.12, 0.12, 0.12, 1)
        colors[Col.FrameBgHovered]        = ImVec4(0.25, 0.25, 0.26, 1)
        colors[Col.FrameBgActive]         = ImVec4(0.25, 0.25, 0.26, 1)
        colors[Col.TitleBg]               = ImVec4(0.12, 0.12, 0.12, 1)
        colors[Col.TitleBgActive]         = ImVec4(0.12, 0.12, 0.12, 1)
        colors[Col.TitleBgCollapsed]      = ImVec4(0.12, 0.12, 0.12, 1)
        colors[Col.MenuBarBg]             = ImVec4(0.12, 0.12, 0.12, 1)
        colors[Col.ScrollbarBg]           = ImVec4(0.12, 0.12, 0.12, 1)
        colors[Col.ScrollbarGrab]         = ImVec4(0, 0, 0, 1)
        colors[Col.ScrollbarGrabHovered]  = ImVec4(0.41, 0.41, 0.41, 1)
        colors[Col.ScrollbarGrabActive]   = ImVec4(0.51, 0.51, 0.51, 1)
        colors[Col.CheckMark]             = ImVec4(1, 1, 1, 1)
        colors[Col.SliderGrab]            = ImVec4(1, 1, 1, 0.3)
        colors[Col.SliderGrabActive]      = ImVec4(1, 1, 1, 0.3)
        colors[Col.Button]                = ImVec4(0.12, 0.12, 0.12, 1)
        colors[Col.ButtonHovered]         = ImVec4(0.21, 0.2, 0.2, 1)
        colors[Col.ButtonActive]          = ImVec4(0.41, 0.41, 0.41, 1)
        colors[Col.Header]                = ImVec4(0.12, 0.12, 0.12, 1)
        colors[Col.HeaderHovered]         = ImVec4(0.2, 0.2, 0.2, 1)
        colors[Col.HeaderActive]          = ImVec4(0.47, 0.47, 0.47, 1)
        colors[Col.Separator]             = ImVec4(0.12, 0.12, 0.12, 1)
        colors[Col.SeparatorHovered]      = ImVec4(0.12, 0.12, 0.12, 1)
        colors[Col.SeparatorActive]       = ImVec4(0.12, 0.12, 0.12, 1)
        colors[Col.ResizeGrip]            = ImVec4(1, 1, 1, 0.25)
        colors[Col.ResizeGripHovered]     = ImVec4(1, 1, 1, 0.67)
        colors[Col.ResizeGripActive]      = ImVec4(1, 1, 1, 0.95)
        colors[Col.Tab]                   = ImVec4(0.12, 0.12, 0.12, 1)
        colors[Col.TabHovered]            = ImVec4(0.28, 0.28, 0.28, 1)
        colors[Col.TabActive]             = ImVec4(0.3, 0.3, 0.3, 1)
        colors[Col.TabUnfocused]          = ImVec4(0.07, 0.1, 0.15, 0.97)
        colors[Col.TabUnfocusedActive]    = ImVec4(0.14, 0.26, 0.42, 1)
        colors[Col.PlotLines]             = ImVec4(0.61, 0.61, 0.61, 1)
        colors[Col.PlotLinesHovered]      = ImVec4(1, 0.43, 0.35, 1)
        colors[Col.PlotHistogram]         = ImVec4(0.9, 0.7, 0, 1)
        colors[Col.PlotHistogramHovered]  = ImVec4(1, 0.6, 0, 1)
        colors[Col.TextSelectedBg]        = ImVec4(1, 0, 0, 0.35)
        colors[Col.DragDropTarget]        = ImVec4(1, 1, 0, 0.9)
        colors[Col.NavHighlight]          = ImVec4(0.26, 0.59, 0.98, 1)
        colors[Col.NavWindowingHighlight] = ImVec4(1, 1, 1, 0.7)
        colors[Col.NavWindowingDimBg]     = ImVec4(0.8, 0.8, 0.8, 0.2)
        colors[Col.ModalWindowDimBg]      = ImVec4(0, 0, 0, 0.7)

        style.WindowPadding               = ImVec2(5, 5)
        style.FramePadding                = ImVec2(5, 5)
        style.ItemSpacing                 = ImVec2(5, 5)
        style.ItemInnerSpacing            = ImVec2(2, 2)
        style.TouchExtraPadding           = ImVec2(0, 0)
        style.IndentSpacing               = 0
        style.ScrollbarSize               = 10
        style.GrabMinSize                 = 10
        style.WindowBorderSize            = 1
        style.ChildBorderSize             = 1
        style.PopupBorderSize             = 1
        style.FrameBorderSize             = 0
        style.TabBorderSize               = 1
        style.WindowRounding              = 5
        style.ChildRounding               = 5
        style.FrameRounding               = 5
        style.PopupRounding               = 5
        style.ScrollbarRounding           = 5
        style.GrabRounding                = 5
        style.TabRounding                 = 5
        style.WindowTitleAlign            = ImVec2(0.5, 0.5)
        style.ButtonTextAlign             = ImVec2(0.5, 0.5)
        style.SelectableTextAlign         = ImVec2(0.5, 0.5)
    end
end)

local notifications = {}

imgui.OnFrame(function() return data.main[0] end, function(self)
    local w, h = getScreenResolution()
    local windowSize = imgui.ImVec2(480.0, 323.0)
    local margin_right = 0.0
    local y_percent_top = 0.40

    local posX = w - windowSize.x - margin_right
    local posY = h * y_percent_top

    posX = math.max(0, math.min(posX, w - windowSize.x))
    posY = math.max(0, math.min(posY, h - windowSize.y))

    imgui.SetNextWindowSize(windowSize, imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(posX, posY), imgui.Cond.Always)

    if imgui.Begin("##main_windos", data.main, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar +
            imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar +
            imgui.WindowFlags.NoMove) then
        imgui.customTitleBar(data.main, resetDefaultCfg, imgui.GetWindowWidth())

        __i__main()
        imgui.showNotifications(2)
        imgui.End()
    end
end)

imgui.OnFrame(function()
    return data.showHouseControlWindow[0]
end, function()
    RenderUpdateDialog()
    local sw, sh = getScreenResolution()
    local windowSize = imgui.ImVec2(880, 620)

    imgui.SetNextWindowSize(windowSize, imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    local function iconText(icon, text)
        imgui.Text(icon .. " ")
        imgui.SameLine()
        imgui.TextColoredRGB(text)
    end
    if imgui.Begin(u8("Управление майнинг-фермами"), data.showHouseControlWindow,
            imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar +
            imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar) then
        imgui.customTitleBar(data.showHouseControlWindow, resetDefaultCfg, imgui.GetWindowWidth())

        -- === Заголовок с статистикой ===
        imgui.BeginChild("##header_panel", imgui.ImVec2(0, 40), true)

        local totalHouses = #data.dialogData.flashminer
        local housesGood, housesWarning, housesBad = 0, 0, 0
        local totalBalance, totalBTC, totalASC = 0, 0, 0
        local badHousesIssues = {}
        local warningHousesIssues = {}

        for _, house in ipairs(data.dialogData.flashminer) do
            local status = data.houseStatuses[house.house_number]
            totalBalance = totalBalance + (house.balance or 0)
            if not (status and status.lastCheck > 0) then goto continue end

            local earnings = status.earnings or {}
            totalBTC = totalBTC + (earnings.btc or 0)
            totalASC = totalASC + (earnings.asc or 0)

            if status.status == "good" then
                housesGood = housesGood + 1
            elseif status.status == "warning" then
                housesWarning = housesWarning + 1
                if status.issues and #status.issues > 0 then
                    warningHousesIssues[house.house_number] = status.issues
                end
            elseif status.status == "bad" then
                housesBad = housesBad + 1
                if status.issues and #status.issues > 0 then
                    badHousesIssues[house.house_number] = status.issues
                end
            end

            ::continue::
        end

        imgui.Spacing()

        -- Верхняя статистика в 4 колонки
        imgui.Columns(4, "##stats_cols", false)

        -- Колонка 1: Общая информация

        imgui.BeginGroup()
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 60 / 2)
        imgui.SetCursorPosY(imgui.GetCursorPosY() + 4)
        iconText(fa.HOUSE, "{87CEFA}Всего домов: {FFFFFF}" .. totalHouses)
        imgui.EndGroup()
        imgui.Hint(u8("Общее количество домов с майнинг-фермами"))

        imgui.NextColumn()

        -- Колонка 2: Криптовалюта
        imgui.BeginGroup()
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 60 / 2)
        imgui.SetCursorPosY(imgui.GetCursorPosY() + 4)
        iconText(fa.COINS, "{BEF781}Доступно:")

        local parts = {}
        if totalBTC > 0 then table.insert(parts, string.format("{BEF781}%d BTC", totalBTC)) end
        if totalASC > 0 and not data.isRodina then table.insert(parts, string.format("{FFA500}%d ASC", totalASC)) end

        local text = #parts > 0 and table.concat(parts, " {FFFFFF}| ") or "{808080}0"
        imgui.SameLine()
        imgui.TextColoredRGB(text)
        imgui.EndGroup()

        imgui.Hint(u8("Общее количество криптовалюты для снятия"))

        imgui.NextColumn()

        -- Колонка 3: Общий баланс
        imgui.BeginGroup()
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 60 / 2)
        imgui.SetCursorPosY(imgui.GetCursorPosY() + 4)
        iconText(fa.DOLLAR_SIGN, string.format("{FFD700}Баланс: {FFFFFF}$%s", utils.formatNumber(totalBalance)))
        imgui.EndGroup()
        imgui.Hint(u8("Общий баланс всех домов"))

        imgui.NextColumn()

        -- Колонка 4: Статусы домов
        imgui.BeginGroup()
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 60 / 2)
        imgui.SetCursorPosY(imgui.GetCursorPosY() + 4)
        iconText(fa.CHART_PIE, "{87CEFA}Состояние:")

        local parts = {}
        if housesGood > 0 then table.insert(parts, string.format("{4DE94C}%d", housesGood)) end
        if housesWarning > 0 then table.insert(parts, string.format("{FFE133}%d", housesWarning)) end
        if housesBad > 0 then table.insert(parts, string.format("{FF3333}%d", housesBad)) end

        local statusText = #parts > 0 and table.concat(parts, " {FFFFFF}/ ") or "{808080}Не проверено"
        imgui.SameLine()
        imgui.TextColoredRGB(statusText)
        imgui.EndGroup()
        if imgui.IsItemHovered() then
            imgui.BeginTooltip()
            imgui.TextColoredRGB("{FFFFFF}" .. "Сводка по состоянию домов:")
            imgui.Separator()

            local hasIssues = false

            if next(badHousesIssues) ~= nil then
                hasIssues = true
                iconText(fa.CIRCLE_EXCLAMATION, "Критические проблемы:")
                for houseNum, issues in pairs(badHousesIssues) do
                    imgui.TextColoredRGB("  {FFA500}Дом №" .. houseNum .. ":")
                    for _, issue in ipairs(issues) do
                        imgui.Text(u8("    • " .. issue))
                    end
                end
                imgui.Spacing()
            end

            if next(warningHousesIssues) ~= nil then
                hasIssues = true
                iconText(fa.TRIANGLE_EXCLAMATION, "Требуют внимания:")
                for houseNum, issues in pairs(warningHousesIssues) do
                    imgui.TextColoredRGB("  {FFA500}Дом №" .. houseNum .. ":")
                    for _, issue in ipairs(issues) do
                        imgui.Text(u8("    • " .. issue))
                    end
                end
                imgui.Spacing()
            end

            if not hasIssues then
                iconText(fa.CIRCLE_CHECK, "Проблем не обнаружено.")
            end
            imgui.EndTooltip()
        end


        imgui.Columns(1)
        imgui.EndChild()

        -- === Панель массовых действий ===
        imgui.BeginChild("##action_panel", imgui.ImVec2(0, 75), true)
        iconText(fa.WAND_MAGIC_SPARKLES, "{FFFFFF}Массовые действия:")
        imgui.Spacing()

        local buttonWidth = (imgui.GetContentRegionAvail().x - imgui.GetStyle().ItemSpacing.x * 4) / 5
        local buttonSize = imgui.ImVec2(buttonWidth, 35)

        local function actionButton(icon, label, color, taskName, callback)
            if color then
                imgui.PushStyleColor(imgui.Col.Button, color)
                imgui.PushStyleColor(imgui.Col.ButtonHovered,
                    imgui.ImVec4(color.x * 1.2, color.y * 1.2, color.z * 1.2, color.w))
                imgui.PushStyleColor(imgui.Col.ButtonActive,
                    imgui.ImVec4(color.x * 0.8, color.y * 0.8, color.z * 0.8, color.w))
            end

            local pressed = imgui.Button(icon .. " " .. u8(label), buttonSize)

            if color then imgui.PopStyleColor(3) end
            if not pressed then return end
            if data.selectedHouseIndex and data.dialogData.flashminer[data.selectedHouseIndex] then
                data.lastSelectedHouse = data.dialogData.flashminer[data.selectedHouseIndex].house_number
            end
            local task = buildTaskTable(taskName)
            runTaskAndReopenDialog(function() task:run(callback) end)
            if taskName ~= 'updateStatuses' then data.showHouseControlWindow[0] = false end
            return pressed
        end

        actionButton(fa.DOLLAR_SIGN, "Собрать", imgui.ImVec4(0.3, 0.8, 0.3, 1), "collectFromAllHouses")
        imgui.Hint(u8("Собрать криптовалюту со всех домов"))
        imgui.SameLine()
        actionButton(fa.POWER_OFF, "Включить", imgui.ImVec4(0.2, 0.6, 1, 1), "massSwitchCards", true)
        imgui.Hint(u8("Включить все видеокарты во всех домах"))
        imgui.SameLine()
        actionButton(fa.PLUG, "Выключить", imgui.ImVec4(1, 0.3, 0.3, 1), "massSwitchCards", false)
        imgui.Hint(u8("Выключить все видеокарты во всех домах"))
        imgui.SameLine()
        actionButton(fa.ROTATE, "Обновить", imgui.ImVec4(0.8, 0.6, 0.2, 1), "updateStatuses")
        imgui.Hint(u8("Быстро обновить статусы всех домов (баланс, налоги, жидкость).\nНе проверяет наличие подвалов."))
        imgui.SameLine()
        actionButton(fa.WAND_MAGIC_SPARKLES, "Выполнение всего", imgui.ImVec4(0.6, 0.4, 0.9, 1), "fixAllProblems")
        imgui.Hint(u8("Пополнить баланс ферм\nCобрать криптовалюту\nВключить видеокарты\nОплатить налоги"))

        imgui.EndChild()

        -- === Список домов ===
        iconText(fa.LIST, " {FFFFFF}Список домов " .. string.format("{808080}(%d)", totalHouses))
        imgui.Spacing()

        if imgui.BeginChild("##house_list", imgui.ImVec2(0, 0), true, imgui.WindowFlags.AlwaysVerticalScrollbar + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollWithMouse) then
            local io = imgui.GetIO()

            local mouseWheel = io.MouseWheel

            if mouseWheel ~= 0 and imgui.IsWindowHovered(imgui.HoveredFlags.ChildWindows) then
                if mouseWheel < 0 then
                    data.selectedHouseIndex = data.selectedHouseIndex + 1
                elseif mouseWheel > 0 then
                    data.selectedHouseIndex = data.selectedHouseIndex - 1
                end

                if data.selectedHouseIndex > #data.dialogData.flashminer then
                    data.selectedHouseIndex = #data.dialogData.flashminer -- Прокрутка с блоком
                    --data.selectedHouseIndex = 1 -- Прокрутка цикличная
                end
                if data.selectedHouseIndex < 1 then
                    data.selectedHouseIndex = 1 -- Прокрутка с блоком
                    --data.selectedHouseIndex = #data.dialogData.flashminer -- Прокрутка цикличная
                end

                data.scrollToSelection = true
            end

            local style = imgui.GetStyle()
            local itemHeight = 75 + style.ItemSpacing.y

            if data.scrollToSelection then
                imgui.Scroller("house_list", data.selectedHouseIndex, #data.dialogData.flashminer, itemHeight, 400)

                local currentScroll = imgui.GetScrollY()
                local visibleWindowHeight = imgui.GetWindowHeight() - style.WindowPadding.y * 2
                local targetY = (data.selectedHouseIndex - 1) * itemHeight - (visibleWindowHeight / 2) + (itemHeight / 2)
                if math.abs(currentScroll - targetY) < 1 then
                    data.scrollToSelection = false
                end
            end
            for i, house in ipairs(data.dialogData.flashminer) do
                local status = data.houseStatuses[house.house_number]

                local colors = {
                    bad     = imgui.ImVec4(1, 0.2, 0.2, 1),
                    warning = imgui.ImVec4(1, 0.88, 0.2, 1),
                    good    = imgui.ImVec4(0.3, 1, 0.3, 1),
                    unknown = imgui.ImVec4(0.5, 0.5, 0.5, 1),
                }

                local icons = {
                    bad     = fa.CIRCLE_EXCLAMATION,
                    warning = fa.TRIANGLE_EXCLAMATION,
                    good    = fa.CIRCLE_CHECK,
                    unknown = fa.CIRCLE_QUESTION,
                }
                local statusType, statusColor, statusIcon
                if isKnownNoBasement then
                    statusType = "no_basement"
                    statusColor = colors.unknown
                    statusIcon = fa.XMARK
                else
                    statusType = (status and status.lastCheck > 0) and status.status or "unknown"
                    statusColor = colors[statusType] or colors.unknown
                    statusIcon = icons[statusType] or icons.unknown
                end
                local tooltipLines = {}
                if status and status.lastCheck and status.lastCheck > 0 then
                    table.insert(tooltipLines, "Проверено: " .. os.date('%d.%m.%Y в %H:%M', status.lastCheck))
                    table.insert(tooltipLines, "--------------------")
                end
                if statusType == "unknown" then
                    tooltipLines = { "Статус неизвестен (дом не проверялся)" }
                elseif status and status.issues and #status.issues > 0 then
                    for _, issue in ipairs(status.issues) do
                        table.insert(tooltipLines, "• " .. issue)
                    end
                else
                    tooltipLines = { "Проблем не обнаружено" }
                end

                if house.tax and house.tax > 50000 then
                    table.insert(tooltipLines, string.format("Высокий налог: $%s", utils.formatNumber(house.tax)))
                end
                local isKnownNoBasement = cfg.housesWithoutBasement and cfg.housesWithoutBasement[house.house_number]
                if isKnownNoBasement then
                    table.insert(tooltipLines, 1, "В доме нет подвала (из кэша)")
                    table.insert(tooltipLines, 2, "--------------------")
                end

                local isSelected = (i == data.selectedHouseIndex)
                local isClickable = not isKnownNoBasement

                if imgui.CustomSelectableCard("house_card_" .. i, isSelected, imgui.ImVec2(0, itemHeight), function()
                        local columnWidths = { 50, 180, 210, 200, 200 }
                        imgui.Columns(#columnWidths, "##cols_" .. i, false)
                        for col, width in ipairs(columnWidths) do
                            imgui.SetColumnWidth(col - 1, width)
                        end

                        -- Колонка 0: Большая иконка статуса
                        imgui.SetCursorPosY(imgui.GetCursorPosY() + 25)
                        local iconSize = 35
                        imgui.PushFont(nil)
                        imgui.SetCursorPosX(imgui.GetCursorPosX() + (60 - iconSize) / 2)
                        imgui.TextColored(statusColor, statusIcon)
                        imgui.PopFont()

                        imgui.Hint(u8(table.concat(tooltipLines, "\n")))
                        imgui.NextColumn()
                        -- Колонка 1: Информация о доме
                        imgui.BeginGroup()
                        imgui.SetCursorPosY(imgui.GetCursorPosY() + 10)
                        iconText(fa.HOUSE, "{FFFFFF} Дом №{FFA500}" .. house.house_number)

                        if isKnownNoBasement then
                            imgui.TextColoredRGB("{F78181}Нет подвала")
                        else
                            iconText(fa.MAP_PIN, house.city or "Неизвестно")
                        end
                        if imgui.IsItemHovered() then
                            imgui.BeginTooltip()
                            imgui.Text(u8("ПКМ - найти дом"))
                            imgui.EndTooltip()
                            if imgui.IsMouseClicked(1) then
                                local command = string.format("/findihouse %d", house.house_number)
                                sampSendChat(command)
                                imgui.addNotification(u8("Команда " .. command .. " отправлена"))
                            end
                        end
                        if house.cycles then
                            local cyclesColor = house.cycles > 100 and "{4DE94C}" or "{FFE133}"
                            iconText(fa.ROTATE, cyclesColor .. " " .. house.cycles .. " {808080}циклов")
                            imgui.Hint(u8("Количество оплаченных циклов"))
                        end
                        imgui.EndGroup()
                        imgui.NextColumn()

                        -- Колонка 2: Охлаждающая жидкость и Баланс
                        imgui.BeginGroup()
                        if not isKnownNoBasement then
                            imgui.SetCursorPosY(imgui.GetCursorPosY())
                            local balanceColor = (house.balance or 0) < 5000000 and "{FFE133}" or "{FFFFFF}"
                            iconText(fa.DOLLAR_SIGN, "{FFD700}Баланс: " ..
                                balanceColor .. "$" .. utils.formatNumber(house.balance or 0))
                            imgui.Hint(u8(string.format("Баланс дома: $%s / $%s",
                                utils.formatNumber(house.balance or 0),
                                utils.formatNumber(house.max_balance or 0))))

                            iconText(fa.DROPLET, "{87CEFA}Жидкость:")

                            if status and status.lastCheck > 0 and status.minCoolant <= 100 then
                                local coolantFraction = status.minCoolant / 100.0
                                local barColor
                                if coolantFraction < (cfg.useCoolantPercent / 100.0) then
                                    barColor = imgui.ImVec4(1, 0.2, 0.2, 1)
                                elseif coolantFraction < 0.7 then
                                    barColor = imgui.ImVec4(1, 0.88, 0.2, 1)
                                else
                                    barColor = imgui.ImVec4(0.3, 0.8, 1, 1)
                                end

                                imgui.PushStyleColor(imgui.Col.PlotHistogram, barColor)
                                imgui.ProgressBar(coolantFraction, imgui.ImVec2(180, 0),
                                    string.format("%.1f%%", status.minCoolant))
                                imgui.PopStyleColor()
                                imgui.Hint(u8(string.format(
                                    "Минимальный уровень жидкости в доме: %.1f%%\nПорог для заливки: %d%%",
                                    status.minCoolant, cfg.useCoolantPercent)))
                            else
                                -- Если данные еще не сканировались
                                imgui.TextColoredRGB("{808080}Не проверено")
                            end
                        else
                            imgui.SetCursorPosY(imgui.GetCursorPosY() + 25)
                            imgui.TextDisabled(u8("Информация недоступна"))
                        end
                        imgui.EndGroup()
                        imgui.NextColumn()

                        -- Колонка 3: Криптовалюта и налог
                        imgui.BeginGroup()
                        if not isKnownNoBasement then
                            imgui.SetCursorPosY(imgui.GetCursorPosY() + 5)

                            if status and status.lastCheck > 0 and status.earnings then
                                iconText(fa.COINS, "{BEF781}Криптовалюта:")

                                local parts = {}
                                if status.earnings.btc and status.earnings.btc >= 1 then
                                    table.insert(parts, string.format("{BEF781}%d BTC", status.earnings.btc))
                                end
                                if status.earnings.asc and status.earnings.asc >= 1 and not data.isRodina then
                                    table.insert(parts, string.format("{FFA500}%d ASC", status.earnings.asc))
                                end

                                imgui.TextColoredRGB(#parts > 0 and table.concat(parts, "  ") or "{808080}Нет для снятия")
                            else
                                imgui.TextColoredRGB("{808080}Криптовалюта:")
                                imgui.TextColoredRGB("{808080}Не проверено")
                            end
                            imgui.Spacing()
                            iconText(fa.FILE_INVOICE_DOLLAR, "{FFFFFF}Налог:")
                            imgui.SameLine()

                            if house.tax then
                                local taxColor = "{FFFFFF}"
                                if house.tax >= 90000 then
                                    taxColor = "{FF3333}"
                                elseif house.tax >= 50000 then
                                    taxColor = "{FFE133}"
                                end
                                imgui.TextColoredRGB(taxColor .. "$" .. utils.formatNumber(house.tax))
                            else
                                imgui.TextColoredRGB("{808080}Неизвестно")
                            end
                        else
                            imgui.SetCursorPosY(imgui.GetCursorPosY() + 25)
                            imgui.TextDisabled(u8("Информация недоступна"))
                        end
                        imgui.EndGroup()
                        imgui.NextColumn()

                        -- Колонка 4: Видеокарты
                        imgui.SetCursorPosY(imgui.GetCursorPosY() + 20)


                        local totalCards, workingCards = 0, 0
                        local hasCardData = status and status.lastCheck > 0 and status.cardLevels and
                            next(status.cardLevels)

                        if hasCardData then
                            for _, counts in pairs(status.cardLevels) do
                                totalCards = totalCards + counts.total
                                workingCards = workingCards + counts.working
                            end
                        end

                        if hasCardData and totalCards > 0 then
                            local cardColor = (workingCards == totalCards) and "{BEF781}" or "{FFE133}"
                            local cardText = string.format('{ffffff}Карты: %s%d/%d', cardColor, totalCards, 20)

                            local tooltipLines = {}
                            table.insert(tooltipLines, string.format("Работают: %d из %d", workingCards, totalCards))
                            table.insert(tooltipLines, "--------------------")

                            local levelParts = {}
                            local sortedLevels = {}
                            for level in pairs(status.cardLevels) do table.insert(sortedLevels, level) end
                            table.sort(sortedLevels)

                            for _, level in ipairs(sortedLevels) do
                                table.insert(levelParts,
                                    string.format("• %d уровень: %d шт.", level, status.cardLevels[level].total))
                            end

                            if #levelParts > 0 then
                                table.insert(tooltipLines, "Уровни установленных карт:")
                                for _, part in ipairs(levelParts) do
                                    table.insert(tooltipLines, part)
                                end
                            else
                                table.insert(tooltipLines, "Нет данных об уровнях карт.")
                            end

                            local tooltipText = table.concat(tooltipLines, "\n")
                            iconText(fa.MICROCHIP, cardText)
                            imgui.Hint(u8(tooltipText))
                        else
                            iconText(fa.MICROCHIP, "{808080}Карты: нет данных")
                        end

                        local hoursLeft = nil
                        if status and status.lastCheck > 0 and status.minCoolant <= 100 then
                            hoursLeft = math.floor(utils.calculateRemainingHours(status.minCoolant or 0))
                        end

                        if hoursLeft and hoursLeft > 0 then
                            imgui.TextColoredRGB('{ffffff}Проработает: {ffa500}~' .. hoursLeft .. ' {ffffff}часов')
                            imgui.Hint(u8('Примерное оставшееся время до обслуживания фермы'))
                        else
                            imgui.TextColoredRGB('{808080}Проработает: нет данных')
                        end

                        imgui.Columns(1)
                    end, isClickable) then
                    data.selectedHouseIndex = i
                    sampSendDialogResponse(data.dFlashminerId, 1, house.index - 1, "")
                    data.showHouseControlWindow[0] = false
                    data.lastSelectedHouse = house.house_number
                end
            end
            imgui.EndChild()
        end

        imgui.End()
    end
end)

function __i__main()
    imgui.BeginChild('##top_panel_unified', imgui.ImVec2(0, 104), true, imgui.WindowFlags.NoScrollbar)
    imgui.Columns(2, "##main_columns_unified", false, imgui.WindowFlags.NoScrollbar)
    imgui.SetColumnWidth(0, 255)
    -- Левая колонка с информацией
    __i__infoPanel()
    imgui.NextColumn()
    -- Правая колонка с кнопками управления
    __i__controlPanel()

    imgui.Columns(1)
    imgui.EndChild()

    -- Нижняя панель
    __i__bottomPanel()
end

function __i__infoPanel()
    imgui.BeginChild('##info_panel_child', imgui.ImVec2(0, -1), false, imgui.WindowFlags.NoScrollbar)
    local title_text = data.forImgui.dTitle or "Ожидание..."
    imgui.TextColoredRGB('{ffffff}Дом: {ffa500}№ ' .. title_text)
    imgui.TextColoredRGB('{ffffff}Статус фермы: ' ..
        (data.forImgui.allGood and '{BEF781}Всё хорошо.' or '{F78181}Требует внимания.'))
    imgui.TextColoredRGB('{ffffff}Количество видеокарт: {99ff99}' .. data.forImgui.videocardCount)
    imgui.TextColoredRGB('{ffffff}Можно снять: {BEF781}' ..
        data.forImgui.earnings.btc .. ' BTC' ..
        (not data.isRodina and ' {ffffff}|| {ffa500}' .. data.forImgui.earnings.asc .. ' ASC' or ''))
    imgui.TextColoredRGB('{ffffff}Проработает: {ffa500}~' ..
        math.floor(utils.calculateRemainingHours(data.forImgui.attentionTime)) .. " {ffffff}часов")
    imgui.EndChild()
end

function __i__controlPanel()
    local availableWidth = imgui.GetContentRegionAvail().x
    local buttonSide = ((availableWidth - imgui.GetStyle().ItemSpacing.x) / 2) - 2
    local buttonSize = imgui.ImVec2(buttonSide, buttonSide - 5)
    if data.isFlashminer then
        if imgui.Button(fa.ARROW_LEFT .. "##left", buttonSize) then navigateFlashminer(-1) end
        imgui.Hint(u8 "Переключиться на предыдущую ферму.")
        imgui.SameLine(0, imgui.GetStyle().ItemSpacing.x + 5)
        if imgui.Button(fa.ARROW_RIGHT .. "##right", buttonSize) then navigateFlashminer(1) end
        imgui.Hint(u8 "Переключиться на следующую ферму.")
    else
        -- Неактивные кнопки
        imgui.ButtonClickable("Доступно только в Флешке Майнера.", data.isFlashminer, fa.ARROW_LEFT .. "##left_disabled",
            buttonSize)
        imgui.SameLine(0, imgui.GetStyle().ItemSpacing.x + 5)
        imgui.ButtonClickable("Доступно только в Флешке Майнера.", data.isFlashminer,
            fa.ARROW_RIGHT .. "##right_disabled", buttonSize)
    end
end

function __i__bottomPanel()
    imgui.BeginChild('##bottom_panel_child', imgui.ImVec2(0, 0), false, imgui.WindowFlags.NoScrollbar)

    local style = imgui.GetStyle()
    local textLineHeight = imgui.GetTextLineHeight()
    local sliderHeight = textLineHeight + style.FramePadding.y * 2
    local staticContentHeight = (textLineHeight * 2) + sliderHeight +
        (style.ItemSpacing.y * 2)

    local availableHeight = imgui.GetContentRegionAvail().y
    local dynamicHeight = availableHeight - staticContentHeight

    local elementHeight = (dynamicHeight - (style.ItemSpacing.y * 3)) / 4 - 1

    if elementHeight < 20 then elementHeight = 20 end

    -- Ряд 1: Кнопка "Снять криптовалюту"
    local canWithdraw = data.forImgui.earnings.btc >= 1 or data.forImgui.earnings.asc >= 1
    if imgui.ButtonClickable("Нет криптовалюты для снятия.", canWithdraw and not data.working, u8 "Снять криптовалюту", imgui.ImVec2(-1, elementHeight)) then
        local task = buildTaskTable('takeCrypto')
        task.data.listBoxes = data.dialogData.videocards
        task:takeCrypto()
    end

    -- Ряд 2: Кнопки "Включить/Выключить"
    local halfButtonWidth = (imgui.GetContentRegionAvail().x - style.ItemSpacing.x) / 2
    if imgui.ButtonClickable("В процессе...", not data.working, u8 "Включить видеокарты", imgui.ImVec2(halfButtonWidth, elementHeight)) then
        local task = buildTaskTable('switchCards')
        task.data.listBoxes = data.dialogData.videocards
        task:switchCards(true)
    end
    imgui.SameLine()
    if imgui.ButtonClickable("В процессе...", not data.working, u8 "Выключить видеокарты", imgui.ImVec2(halfButtonWidth, elementHeight)) then
        local task = buildTaskTable('switchCards')
        task.data.listBoxes = data.dialogData.videocards
        task:switchCards(false)
    end

    -- Ряд 3: Кнопка "Залить жидкость"
    local canRefill = not data.isFlashminer and not data.working
    if imgui.ButtonClickable(data.isFlashminer and "Недоступно в флешке майнера" or "В процессе...", canRefill, u8 "Залить жидкость", imgui.ImVec2(-1, elementHeight)) then
        local task = buildTaskTable('coolant')
        task.data.listBoxes = data.dialogData.videocards
        task:coolant()
    end

    -- Ряд 4: Чекбоксы.
    local cursorY_before = imgui.GetCursorPosY()
    imgui.Dummy(imgui.ImVec2(-1, elementHeight))
    local cursorY_after = imgui.GetCursorPosY()

    local checkboxHeight = textLineHeight + style.FramePadding.y * 2
    imgui.SetCursorPosY(cursorY_before + (elementHeight - checkboxHeight) / 2)

    if imgui.Checkbox(u8 "Использовать Супер Охлаждающую Жидкость", imcfg.useSuperCoolant) then
        cfg.useSuperCoolant = imcfg.useSuperCoolant[0]; save()
    end
    imgui.Hint(u8("Использовать Супер Охлаждающую Жидкость вместо обычной.\n(Для  BTC карт и Asic Miner)"))
    imgui.SameLine()
    if imgui.Checkbox(u8 "Режим Экономии##econom", imcfg.economyMode) then
        cfg.economyMode = imcfg.economyMode[0]; save()
    end
    imgui.Hint(u8 "Включает экономию охлаждающей жидкости.\nРаботает только с обычными жидкостями и вне Вайс-Сити (и не для суперохлаждающих).\nКак это работает: если посли заливки одной жидкости уровень охлаждения достигает 70% и выше, то вторая жидкость не расходуется.\nБез этого режима скрипт всегда заполняет охлаждение до 100%.")

    imgui.SetCursorPosY(cursorY_after)

    imgui.Text(u8 "Порог срабатывания заливки:")
    imgui.TextDisabled(u8 "Если процент охлаждающей жикости < настроенной ниже, то заливаем.")
    imgui.PushItemWidth(-1)
    if imgui.SliderInt("##coolantPercent", imcfg.useCoolantPercent, 1, 100) then
        cfg.useCoolantPercent = imcfg.useCoolantPercent[0]; save()
    end
    imgui.PopItemWidth()

    imgui.EndChild()
end

function imgui.customTitleBar(param, resetFunc, windowWidth)
    local imStyle = imgui.GetStyle()

    imgui.SetCursorPosY(imStyle.ItemSpacing.y + 5)
    if imgui.Link("t.me/justfedotScript", u8("Telegram канал автора.\nНажми чтобы перейти/скопировать")) then
        imgui.addNotification(u8 "Ссылка скопирована!")
        imgui.SetClipboardText("https://t.me/justfedotScript")
        os.execute(('explorer.exe "%s"'):format("https://t.me/justfedotScript"))
    end

    imgui.SameLine()
    imgui.SetCursorPosX((windowWidth - 170 - imStyle.ItemSpacing.x + imgui.CalcTextSize("t.me/justfedotScript").x) / 2 -
        imgui.CalcTextSize(script.this.name).x / 2)
    imgui.TextColoredRGB(script.this.name)

    imgui.SameLine()

    imgui.SetCursorPosX(windowWidth - 170 - imStyle.ItemSpacing.x)
    imgui.SetCursorPosY(imStyle.ItemSpacing.y)
    if imgui.Button(fa('MONUMENT') .. "##popup_donation_button", imgui.ImVec2(50, 25)) then
        imgui.OpenPopup("donationPopupMenu")
    end

    imgui.SameLine()

    imgui.SetCursorPosX(windowWidth - 110 - imStyle.ItemSpacing.x)
    imgui.SetCursorPosY(imStyle.ItemSpacing.y)
    if imgui.Button(fa("BARS") .. "##popup_menu_button", imgui.ImVec2(50, 25)) then
        imgui.OpenPopup("upWindowPupupMenu")
    end

    imgui.SameLine()

    imgui.SetCursorPosX(windowWidth - 50 - imStyle.ItemSpacing.x)
    imgui.SetCursorPosY(imStyle.ItemSpacing.y)
    if imgui.ButtonClickable("Закрыть", true, fa("XMARK") .. "##close_button", imgui.ImVec2(50, 25)) then
        if data.showHouseControlWindow[0] then
            fixI()
            param[0] = false
        end
    end

    if imgui.BeginPopup("upWindowPupupMenu") then
        imgui.TextColoredRGB("Доп. Функции:")
        imgui.Separator()
        if imgui.Checkbox(u8 "Тихий режим##silentMode", imcfg.silentMode) then
            cfg.silentMode = imcfg.silentMode[0]
            save()
        end
        imgui.Hint(u8("Отключает все сообщения от скрипта в чате."))

        if imgui.Checkbox(u8 "Старый вид меню (диалог)", imcfg.useDialogMode) then
            cfg.useDialogMode = imcfg.useDialogMode[0]
            save()
            if cfg.useDialogMode then
                sampSendChat('/flashminer')
            end
        end
        imgui.Hint(u8("Вместо отдельного окна добавляет пункты в стандартный диалог SAMP."))

        if not cfg.useDialogMode and not data.isRodina then
            imgui.Separator()
            imgui.TextColoredRGB("{FFA500}Настройки функции 'Исправить'")

            imgui.Text(u8("Пополнять баланс дома до:"))
            if imgui.SliderInt("##targetBalance", imcfg.targetHouseBalance, 5000000, 20000000, u8("$" .. utils.formatNumber(imcfg.targetHouseBalance[0]))) then
                cfg.targetHouseBalance = imcfg.targetHouseBalance[0]
                save()
            end
            imgui.Hint(u8("Если баланс дома упадет ниже этого значения, скрипт пополнит его до этой суммы."))

            imgui.Text(u8("Оплачивать налоги если >:"))
            if imgui.SliderInt("##taxThreshold", imcfg.taxPayment, 1000, 100000, u8("$" .. utils.formatNumber(imcfg.taxPayment[0]))) then
                local raw_value = imcfg.taxPayment[0]
                local rounded_value = math.floor(raw_value / 1000 + 0.5) * 1000
                cfg.taxPayment = rounded_value
                imcfg.taxPayment[0] = rounded_value
                save()
            end
            imgui.Hint(u8("Скрипт оплатит налоги за все дома, если сумма налога на дом превысит это значение."))
            imgui.Separator()
            if imgui.Selectable(u8("Проверить подвалы"), false) then
                if not data.working then
                    local task = buildTaskTable('scanBasements')
                    runTaskAndReopenDialog(function() task:run() end)
                    data.showHouseControlWindow[0] = false
                else
                    utils.addChat("{F78181}Дождитесь завершения текущей операции.")
                end
            end
            imgui.Hint(u8(
                "Запускает долгое сканирование для проверки наличия подвалов во всех домах.\nИспользуйте, если вы построили новый подвал."))
        end

        if imgui.Selectable(u8("Перезагрузить скрипт") .. "##reloadScriptButton", false) then
            cfg.isReloaded = true
            save()
            thisScript():reload()
        end
        if imgui.Selectable(u8("Сбросить все настройки") .. "##resetSettingsButton", false) then
            resetFunc()
        end
        if not data.isRodina then
            imgui.Text(u8 "Пауза между действиями:")
            if imgui.SliderInt("##pause", imcfg.pause_duration, 70, 200, u8("%d мс")) then
                cfg.pause_duration = imcfg.pause_duration[0]
                save()
            end
            imgui.Hint(u8(
                "Чем больше задержка, тем медленее работа скрипта.\nЭто помогает избежать киков за слишком быстрые действия."))

            imgui.Text(u8 "Количество действий:")
            if imgui.SliderInt("##count", imcfg.count_action, 1, 20) then
                cfg.count_action = imcfg.count_action[0]
                save()
            end
            imgui.Hint(u8("Сколько команд (кликов) отправить серверу до срабатывания задержки."))
        end

        imgui.TextDisabled(u8("Версия: ") .. script.this.version)
        imgui.EndPopup()
    end

    if imgui.BeginPopup("donationPopupMenu") then
        imgui.Text(u8(
            "Оригинальный автор скрипта Just Fedot"
        ))
        if imgui.Link("https://www.blast.hk/threads/213948/", u8 "Ссылка на исходный скрипт") then
            os.execute(('explorer.exe "%s"'):format("https://www.blast.hk/threads/213948/"))
        end

        imgui.Text(u8(
            "А так же вы можете почтить его память в данной теме"
        ))
        if imgui.Link("https://www.blast.hk/threads/235846/", u8 "Нажмите чтобы перейти") then
            os.execute(('explorer.exe "%s"'):format("https://www.blast.hk/threads/235846/"))
        end
        imgui.EndPopup()
    end
end

function imgui.addNotification(text)
    table.insert(notifications, {
        text = text,
        startTime = os.clock()
    })
end

function imgui.CustomSelectableCard(id, is_selected, size, draw_content_func, is_clickable)
    is_clickable = is_clickable ~= false

    local start = imgui.GetCursorScreenPos()
    local width = size.x > 0 and size.x or imgui.GetContentRegionAvail().x
    size = imgui.ImVec2(width, size.y)
    local endp = imgui.ImVec2(start.x + size.x, start.y + size.y)
    local dl = imgui.GetWindowDrawList()
    local bgColor = is_selected and imgui.GetColorU32(0.2, 0.4, 0.7, 1) or imgui.GetColorU32(0.09, 0.09, 0.09, 1)
    dl:AddRectFilled(start, endp, bgColor, 5)

    imgui.SetCursorScreenPos(start)
    local clicked = imgui.InvisibleButton("##card_" .. id, size)

    if draw_content_func then
        imgui.SetCursorScreenPos(imgui.ImVec2(start.x + 10, start.y + 5))
        imgui.PushClipRect(start, endp, true)
        draw_content_func()
        imgui.PopClipRect()
    end

    imgui.SetCursorPosY(imgui.GetCursorPosY() + size.y - 65)

    return clicked and is_clickable
end

function imgui.showNotifications(duration)
    local currentTime = os.clock()
    local activeNotifications = #notifications

    -- Начинаем отображение подсказок, если есть активные уведомления
    if activeNotifications ~= 0 then
        imgui.BeginTooltip()
    end
    for i = #notifications, 1, -1 do
        local notification = notifications[i]
        -- Проверяем, прошло ли время показа
        if currentTime - notification.startTime < duration then
            imgui.Text(notification.text)
            activeNotifications = activeNotifications + 1
            -- Если это не последнее уведомление, добавляем разделитель
            if i > 1 then
                imgui.Separator()
            end
        else
            table.remove(notifications, i)
        end
    end

    if activeNotifications ~= 0 then
        imgui.EndTooltip()
    end
end

imgui.Scroller = {
    _ids = {}
}

setmetatable(imgui.Scroller, {
    __call = function(self, id, targetIndex, totalItems, itemHeight, animationDuration)
        if not targetIndex then return end

        if not imgui.Scroller._ids[id] then
            imgui.Scroller._ids[id] = {}
        end

        local currentScroll = imgui.GetScrollY()
        local scrollMax = imgui.GetScrollMaxY()

        local visibleWindowHeight = imgui.GetWindowHeight() - imgui.GetStyle().WindowPadding.y * 2
        local targetY = (targetIndex - 1) * itemHeight - (visibleWindowHeight / 2) + (itemHeight / 2)

        if targetY < 0 then targetY = 0 end
        if targetY > scrollMax then targetY = scrollMax end

        if not imgui.Scroller._ids[id].start_clock or imgui.Scroller._ids[id].target_position ~= targetY then
            imgui.Scroller._ids[id].start_clock = os.clock()
            imgui.Scroller._ids[id].start_position = currentScroll
            imgui.Scroller._ids[id].target_position = targetY
        end

        if imgui.Scroller._ids[id].start_clock then
            local elapsed = (os.clock() - imgui.Scroller._ids[id].start_clock) * 1000

            if elapsed >= animationDuration then
                imgui.SetScrollY(imgui.Scroller._ids[id].target_position)
                imgui.Scroller._ids[id].start_clock = nil
            else
                local t = elapsed / animationDuration
                local ease = 1 - (1 - t) * (1 - t)
                local distance = imgui.Scroller._ids[id].target_position - imgui.Scroller._ids[id].start_position
                local newPosition = imgui.Scroller._ids[id].start_position + distance * ease
                imgui.SetScrollY(newPosition)
            end
        end
    end
})

function imgui.TextColoredRGB(text)
    local style = imgui.GetStyle()
    local colors = style.Colors
    local ImVec4 = imgui.ImVec4

    local explode_argb = function(argb)
        local a = bit.band(bit.rshift(argb, 24), 0xFF)
        local r = bit.band(bit.rshift(argb, 16), 0xFF)
        local g = bit.band(bit.rshift(argb, 8), 0xFF)
        local b = bit.band(argb, 0xFF)
        return a, r, g, b
    end

    local getcolor = function(color)
        if color:sub(1, 6):upper() == 'SSSSSS' then
            local r, g, b = colors[1].x, colors[1].y, colors[1].z
            local a = tonumber(color:sub(7, 8), 16) or colors[1].w * 255
            return ImVec4(r, g, b, a / 255)
        end
        local color = type(color) == 'string' and tonumber(color, 16) or color
        if type(color) ~= 'number' then return end
        local r, g, b, a = explode_argb(color)
        return imgui.ImVec4(r / 255, g / 255, b / 255, a / 255)
    end

    local render_text = function(text_)
        for w in text_:gmatch('[^\r\n]+') do
            local text, colors_, m = {}, {}, 1
            w = w:gsub('{(......)}', '{%1FF}')
            while w:find('{........}') do
                local n, k = w:find('{........}')
                local color = getcolor(w:sub(n + 1, k - 1))
                if color then
                    text[#text], text[#text + 1] = w:sub(m, n - 1), w:sub(k + 1, #w)
                    colors_[#colors_ + 1] = color
                    m = n
                end
                w = w:sub(1, n - 1) .. w:sub(k + 1, #w)
            end
            if text[0] then
                for i = 0, #text do
                    imgui.TextColored(colors_[i] or colors[1], u8(text[i]))
                    imgui.SameLine(nil, 0)
                end
                imgui.NewLine()
            else
                imgui.Text(u8(w))
            end
        end
    end

    render_text(text)
end

function imgui.ButtonClickable(hint, clickable, ...)
    if clickable then
        return imgui.Button(...)
    else
        local r, g, b, a = imgui.GetStyle().Colors[imgui.Col.Button].x, imgui.GetStyle().Colors[imgui.Col.Button].y,
            imgui.GetStyle().Colors[imgui.Col.Button].z, imgui.GetStyle().Colors[imgui.Col.Button].w
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(r, g, b, a / 2))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(r, g, b, a / 2))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(r, g, b, a / 2))
        imgui.PushStyleColor(imgui.Col.Text, imgui.GetStyle().Colors[imgui.Col.TextDisabled])
        imgui.Button(...)
        imgui.PopStyleColor()
        imgui.PopStyleColor()
        imgui.PopStyleColor()
        imgui.PopStyleColor()
        if hint then
            if imgui.IsItemHovered() then
                imgui.SetTooltip(u8(hint))
            end
        end
    end
end

function imgui.Hint(text, active)
    if not active then
        active = not imgui.IsItemActive()
    end

    -- Если активен элемент или active == true, показываем подсказку
    if imgui.IsItemHovered() and active then
        imgui.SetTooltip(text)
    end
end

function imgui.Link(label, description)
    local size, p, p2 = imgui.CalcTextSize(label), imgui.GetCursorScreenPos(), imgui.GetCursorPos()
    local result = imgui.InvisibleButton(label, size)
    imgui.SetCursorPos(p2)

    if imgui.IsItemHovered() then
        if description then
            imgui.BeginTooltip()
            imgui.PushTextWrapPos(600)
            imgui.TextUnformatted(description)
            imgui.PopTextWrapPos()
            imgui.EndTooltip()
        end
        imgui.TextColored(imgui.ImVec4(0.27, 0.53, 0.87, 1.00), label)
        imgui.GetWindowDrawList():AddLine(imgui.ImVec2(p.x, p.y + size.y), imgui.ImVec2(p.x + size.x, p.y + size.y),
            imgui.GetColorU32(imgui.Col.CheckMark))
    else
        imgui.TextColored(imgui.ImVec4(0.27, 0.53, 0.87, 1.00), label)
    end

    return result
end

function RenderUpdateDialog()
    if show_update_dialog then
        imgui.OpenPopup(u8"Найдено новое обновление!")
        show_update_dialog = false
    end

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowSize(imgui.ImVec2(550, 220), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))

    if imgui.BeginPopupModal(u8"Найдено новое обновление!", nil, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove) then
        imgui.Text(u8"Обнаружена новая версия скрипта: " .. latest_version_str)
        imgui.Text(u8"Ваша текущая версия: " .. script.this.version)
        imgui.Separator()
        imgui.TextWrapped(u8"Рекомендуется всегда использовать последнюю версию для получения новых функций и исправлений ошибок.")
        imgui.Spacing()

        if imgui.Button(u8"Обновить сейчас", imgui.ImVec2(imgui.GetContentRegionAvail().x, 30)) then
            utils.addChat("Начинаю загрузку обновления...")
            asyncHttpRequest("GET", updater_config.script_url, {}, function(response)
                if response.status_code == 200 then
                    local new_script_name = "JF_Mining_Tools_new.lua"
                    local new_script_path = getWorkingDirectory() .. '\\' .. new_script_name
                    
                    local file, err = io.open(new_script_path, "w")
                    if file then
                        file:write(response.text)
                        file:close()
                        utils.addChat("{BEF781}Обновление загружено.")
                        
                        local success, result = pcall(script.load, new_script_name)
                        if not success then
                            utils.addChat("{F78181}Ошибка при загрузке нового скрипта: " .. tostring(result))
                            os.remove(new_script_path)
                            return
                        end

                        local old_script_path = thisScript().path
                        thisScript():unload()

                        os.remove(old_script_path)
                        os.rename(new_script_path, old_script_path)
                        
                        utils.addChat("{BEF781}Скрипт успешно обновлен и перезапущен!")
                    else
                        utils.addChat("{F78181}Ошибка: не удалось сохранить файл обновления. " .. tostring(err))
                    end
                else
                    utils.addChat("{F78181}Ошибка загрузки: сервер вернул статус " .. response.status_code)
                end
            end, function(err)
                utils.addChat("{F78181}Ошибка сети при загрузке обновления: " .. tostring(err))
            end)
            imgui.CloseCurrentPopup()
        end

        if imgui.Button(u8"Напомнить позже", imgui.ImVec2(imgui.GetContentRegionAvail().x, 30)) then
            imgui.CloseCurrentPopup()
        end

        imgui.EndPopup()
    end
end

function checkForUpdates()
    if not updater_config.enabled then return end

    asyncHttpRequest("GET", updater_config.version_url, {}, function(response)
        if response.status_code == 200 then
            local online_version = tonumber(response.text)
            if online_version and online_version > script.this.version_number then
                utils.addChat(string.format("Доступна новая версия! (Ваша: %d, последняя: %d)", script.this.version_number, online_version))
                
                asyncHttpRequest("GET", updater_config.script_url, {}, function(script_response)
                    if script_response.status_code == 200 then
                        latest_version_str = script_response.text:match("script_version%s*'%s*([%d%.]+)%s*'") or tostring(online_version)
                    else
                        latest_version_str = tostring(online_version)
                    end
                    show_update_dialog = true
                end)
            end
        end
    end, function(err)
        print(string.format("[JF Mining Tools] Update check failed: %s", tostring(err)))
    end)
end


function requestRunner()
    return effil.thread(function(httpMethod, url, encodedRequestBody)
        local requestLib = require("requests")
        local jsonLib = require("dkjson")

        local requestBody = (encodedRequestBody and #encodedRequestBody > 2) and jsonLib.decode(encodedRequestBody) or nil

        local success, response = pcall(requestLib.request, httpMethod, url, requestBody)

        if success then
            response.json, response.xml = nil
            return true, response
        else
            return false, response
        end
    end)
end

function handleAsyncHttpRequestThread(requestThread, successCallback, errorCallback)
    local threadStatus
    local threadError

    repeat
        threadStatus, threadError = requestThread:status()
        wait(0)
    until threadStatus ~= "running"

    if not threadError then
        if threadStatus == "completed" then
            local requestSuccess, response = requestThread:get()
            if requestSuccess then
                successCallback(response)
            else
                errorCallback(response)
            end
            return
        elseif threadStatus == "canceled" then
            return errorCallback(threadStatus)
        end
    else
        return errorCallback(threadError)
    end
end

function asyncHttpRequest(httpMethod, url, requestBody, successCallback, errorCallback)
    local encodedBody = require('dkjson').encode(requestBody or {})
    local requestThread = requestRunner()(httpMethod, url, encodedBody)

    successCallback = successCallback or function() end
    errorCallback = errorCallback or function() end

    return {
        effilRequestThread = requestThread,
        luaHttpHandleThread = lua_thread.create(handleAsyncHttpRequestThread, requestThread, successCallback,
            errorCallback)
    }
end