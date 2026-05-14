script_name('Mining Tools')
script_author('JustFedot -- Modified by kernelich')
script_version('2.5.0')
script_version_number(2)
script_description('Скрипт для упрощения майнинга на сервере.')

local sampfuncs = require("sampfuncs")
local sampev = require("samp.events")
local encoding = require("encoding")
encoding.default = 'CP1251'
u8 = encoding.UTF8
local imgui = require("mimgui")
local effil = require('effil')
local ffi = require('ffi')
local fa = require('fAwesome6')
local raknet = require('samp.raknet')
local wm = require('windows.message')
local new = imgui.new

--local UPDATE_CHECK_URL = nil
local UPDATE_CHECK_URL = "https://raw.githubusercontent.com/abc1st/Mining-Tools/main/version.json"

local searchBuffer = new.char[256]()
local currentStatusFilter = new.int(0)
local selectedCardLevels = {}
local selectedCities = {}
local _snapshotSaveT = 0

local sortItems = { u8 "По номеру", u8 "По балансу", u8 "По циклам", u8 "По жидкости", u8 "По видеокартам", u8 "По городу" }
local statusItems = { u8 "Все дома", u8 "В норме", u8 "Требует внимания", u8 "Есть проблемы", u8 "Без подвала" }
require('samp.synchronization')

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

local dialogIdTable          = {
    arizona = {
        videoCardSt = 25244,             -- ID диалога полки
        videoCardDialogId = 25245,       -- ID диалога управления видеокартой (Стойка/Полка)
        coolantDialogId = 25271,         -- ID диалога выбора охлаждающей жидкости
        houseDialogId = 7238,            -- ID диалога выбора дома
        houseFlashMinerDialogId = 25182, -- ID диалога выбора видеокарты в доме
        videoCardAcceptDialogId = 25246, -- ID диалога подтверждения вывода прибыли

        phoneBankMenuId = 6565,          -- ID главного меню банка в телефоне
        payAllTaxesDialogId = 15252,     -- ID диалога подтверждения оплаты всех налогов
        houseListBankId = 7238,          -- ID диалога выбора дома для пополнения (тот же что и houseDialogId)
        topUpBalanceDialogId = 27035,    -- ID диалога ввода суммы пополнения

    },
    rodina = {
        videoCardSt = 25244,           -- ID диалога полки
        videoCardDialogId = 270,       -- ID диалога управления видеокартой (Стойка/Полка)
        coolantDialogId = 25271,       -- ID диалога выбора охлаждающей жидкости
        houseDialogId = 7238,          -- ID диалога выбора дома
        houseFlashMinerDialogId = 269, -- ID диалога выбора видеокарты в доме
        videoCardAcceptDialogId = 271, -- ID диалога подтверждения вывода прибыли
    }
}

local gpuImprovePriceByLevel = {
    [1] = 8000000,
    [2] = 6000000,
    [3] = 5000000,
    [4] = 4000000,
    [5] = 3000000,
    [6] = 2000000,
    [7] = 1000000,
    [8] = 700000,
    [9] = 500000,
}

local improveStep            = {
    STOPPED     = 0,
    SELECT_CARD = 1,
    CONFIRM     = 3,
    WAIT_RESULT = 4,
}
local improveStepNames       = {
    [0] = "Выключено",
    [1] = "Выбор карты",
    [3] = "Подтверждение",
    [4] = "Ожидание результата",
}

local IMPROVE_SPOT           = { x = -1653.13, y = -249.75, z = 14.15 }
local IMPROVE_HINT_RADIUS    = 1

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

local function getDefaultCfg()
    return {
        isReloaded               = false,
        active                   = true,
        debug                    = false,
        silentMode               = false,
        checkForUpdates          = false,
        useDialogMode            = false,

        -- Заливка
        useSuperCoolant          = false,
        useCoolantPercent        = 50,
        economyMode              = false,
        pause_duration           = 300,
        count_action             = 8,

        -- Дома
        housesWithoutBasement    = {},
        excludedHouses           = {},
        basementScanned          = {},
        cardSnapshots            = {},
        lastHouseListHash        = "",
        currentSort              = 0,
        sortAscending            = true,
        showExcludedHouses       = false,
        groupByCity              = false,
        targetHouseBalance       = 10000000,
        minBalanceWarning        = 5000000,

        -- Включение карт
        autoEnableCards          = false,
        autoEnableCardsOnCollect = false,
        autoEnableCardsOnOpen    = false,

        -- Авто-сбор
        cheatModeEnabled         = false,
        autoCollectEnabled       = false,
        collectTimesPerDay       = 2,
        lastCollectTime          = 0,
        collectOnlyIfMin         = 0,
        pauseOnPayday            = true,
        smartCollectEnabled      = false,
        smartCollectTarget       = 50,
        randomDelayEnabled       = false,
        randomDelayMin           = 1,
        randomDelayMax           = 120,

        -- Налоги
        autoPayTaxesEnabled      = false,
        autoPayTaxesWithCollect  = true,
        autoPayTaxesByTimer      = false,
        autoPayTaxesInterval     = 24,
        lastTaxPayTime           = 0,

        -- Пополнение баланса
        autoTopUpEnabled         = false,
        autoTopUpWithCollect     = true,
        autoTopUpByThreshold     = false,
        autoTopUpThreshold       = 3000000,
        autoTopUpByTimer         = false,
        autoTopUpTimerInterval   = 12,
        lastAutoTopUpTime        = 0,
        useSimpleTopUp           = true,
        fixTopUpEnabled          = true,

        -- Фон. обновление статусов
        autoRefreshEnabled       = false,
        autoRefreshInterval      = 30,
        lastAutoRefreshTime      = 0,
        refreshPostponeOnDialog  = true,
        refreshPostponeMinutes   = 1,

        -- Подключение
        waitForConnection        = true,
        delayAfterConnectMin     = 5,

        -- Уведомления
        reminderEnabled          = false,
        reminderInterval         = 10,
        btcThreshold             = 100,
        notifyAutoCollectEnabled = true,
        notifyBeforeSec          = 120,
        notifyShowDuration       = 8,
        notifyWindowPosX         = 0.75,
        notifyWindowPosY         = 0.05,
        logsWindowPosX           = 0.3,
        logsWindowPosY           = 0.1,

        -- Заточка
        improveEnabled           = false,
        improveMenuAll           = true,
        improveTypeCards         = 1,
        improveMode              = 1,
        improveMaxLevel          = 2,
        improveCheckOilsOnStart  = true,
        improveUseStorageUpgrade = false,
        improveStorageAfterAll   = false,
        improveRetryUseDelay     = 1200,
        improveWaitStartTimeout  = 12,
        improveWaitResultTimeout = 20,
        improveWaitResult        = 500,
        improveWaitTryClick      = 500,
        improveTimeoutDialog     = 10,
        improveProbeOpenDelay    = 1500,

        -- Фиксы
        fixSwitchEnabled         = true,
        fixCollectEnabled        = true,
        fixCoolantEnabled        = false,
    }
end

local cfg = getDefaultCfg()

jcfg.update(cfg)
local imcfg = jcfg.setupImgui(cfg)

function save()
    jcfg.save(cfg)
end

function resetDefaultCfg()
    cfg = getDefaultCfg()
    save()
    thisScript():reload()
end

local data = {
    -- Окна
    main                   = imgui.new.bool(false),
    showHouseControlWindow = imgui.new.bool(false),
    showLogsWindow         = imgui.new.bool(false),
    showSettingsWindow     = imgui.new.bool(false),
    showImproveWindow      = imgui.new.bool(false),
    settingsTab            = 0,
    cheatSubTab            = 0,
    debugSubTab            = 0,
    improveSubTab          = 0,
    logsTab                = imgui.new.int(0),
    lastWindowState        = {
        main         = false,
        houseControl = false,
    },

    -- Список домов
    selectedHouseIndex     = 1,
    lastSelectedHouse      = -1,
    scrollToSelection      = false,
    dialogData             = {
        flashminer = {},
        videocards = {},
    },
    taskTypeNow            = '',
    houseStatuses          = {},
    isFlashminer           = false,
    hasFlashminer          = nil,
    dFlashminerId          = 0,
    flashminerSwitchId     = { direction = 0, id = 0 },
    houseHasNoBasement     = false,
    initialScanCompleted   = false,
    filteredHouses         = nil,

    -- Сервер
    isRodina               = false,
    isViceCity             = false,

    -- Состояние
    working                = false,
    fix                    = false,
    silentWindowOpen       = false,
    stopAction             = false,
    suppressDialogs        = false,
    suppressDialogsUntil   = 0,
    stopBySystem           = false,
    collectCancelled       = false,
    globalActionCounter    = {
        count          = 0,
        lastActionTime = 0,
    },
    connectionState        = {
        connected         = true,
        wasDisconnected   = false,
        readyAfterConnect = 0,
        lastCheck         = 0,
    },

    -- Прогресс сбора
    currentCollectHouse    = "",
    progressCurrent        = 0,
    progressTotal          = 0,
    progressHouseCurrent   = 0,
    progressHouseTotal     = 0,
    progressSmooth         = {
        outer          = 0,
        outerVelocity  = 0,
        inner          = 0,
        innerVelocity  = 0,
        lastUpdateTime = 0,
    },

    -- Авто-сбор
    pendingCollectAt       = 0,
    pendingCollectLocked   = false,

    -- Уведомления
    notifyWindow           = {
        show            = imgui.new.bool(false),
        mode            = '',
        btcAmount       = 0,
        countdownTarget = 0,
        autoHideAt      = 0,
        isPreview       = false,
    },

    -- Сбор
    withdraw               = { btc = 0, asc = 0 },
    forImgui               = {
        allGood        = false,
        videocardCount = 0,
        earnings       = { btc = 0, asc = 0 },
        attentionTime  = 0,
    },

    -- PayDay
    isWaitingPayday        = false,
    paydaySkippedAt        = 0,
    skipPayday             = false,

    -- Подтверждения сброса
    logsResetConfirm       = false,
    logsResetTimer         = 0,
    logsResetMode          = "all",
    statsResetConfirm      = false,
    statsResetTimer        = 0,
    settingsResetConfirm   = false,
    settingsResetTimer     = 0,

    -- Фильтры списков
    logsPeriodFilter       = 0,
    levelFilterOpenTime    = 0,
    levelFilterItemRect    = nil,
    cityFilterOpenTime     = 0,
    cityFilterItemRect     = nil,
    cityFilterInvert       = false,

    -- Заточка
    -- спизженно у MMT | Mining Improver
    improve                = {
        isOn              = false,
        step              = 0,
        videoCards        = {},
        select            = 0,

        selectedSlots     = {},
        storageQueue      = {},
        currentIndex      = 0,
        useStorageUpgrade = false,
        consumedThisTry   = false,
        waitStart         = false,
        waitStartAt       = 0,
        waitResultAt      = 0,
        lastUseAt         = 0,
        needCheckOils     = false,
        waitOils          = false,
        oils              = {
            arizona = 0,
            classic = 0,
            busy    = false,
            busyAt  = 0,
            lastAt  = '-',
        },
        cef               = {
            cards                = {},
            probing              = false,
            probeDone            = false,
            probed               = false,
            pendingSlot          = nil,
            pendingIndex         = 0,
            needInventoryRefresh = true,
            waitInventory        = false,
            probeAbort           = false,
            probeAbortReason     = '',
            probeProgress        = 0,
            probeTotal           = 0,
            lastProbeAt          = 0,
            knownLevels          = {},
            knownStorage         = {},
        },
        stats             = {
            byLevel         = {},
            cards           = {},
            attemptsByLevel = {},
            sessionId       = 0,
            active          = false,
            startedAt       = 0,
            finishedAt      = 0,
            attempts        = 0,
            success         = 0,
            fail            = 0,
            oilsUsed        = 0,
            spent           = 0,
            lastReason      = '',
        },
    },
}

local utils = (function()
    local self = {}
    function self.addChat(a)
        if cfg.silentMode or not a then return end

        a = type(a) == 'number' and tostring(a) or (type(a) == 'string' and a or nil)
        if not a then return end

        sampAddChatMessage('{ffa500}' .. thisScript().name .. '{ffffff}: ' .. a, -1)
    end

    function self.debugChat(a)
        if not cfg.debug or not a then return end

        a = type(a) == 'number' and tostring(a) or (type(a) == 'string' and a or nil)
        if not a then return end

        sampAddChatMessage('{ffa500}' .. thisScript().name .. ' DEBUG' .. '{ffffff}: ' .. a, -1)
    end

    function self.calculateRemainingHours(percent)
        local consumptionPerHour = 0.48
        return percent / consumptionPerHour
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

    return self
end)()

function requestRunner()
    return effil.thread(function(httpMethod, url, requestBody)
        local requestLib = require('requests')
        local success, response = pcall(requestLib.request, httpMethod, url, requestBody)
        if success then
            response.json, response.xml = nil
            return true, response
        else
            return false, tostring(response)
        end
    end)
end

function handleAsyncHttpRequestThread(requestThread, successCallback, errorCallback)
    local threadStatus, threadError
    repeat
        threadStatus, threadError = requestThread:status()
        wait(0)
    until threadStatus ~= 'running'
    if not threadError then
        if threadStatus == 'completed' then
            local requestSuccess, response = requestThread:get(0)
            if requestSuccess then successCallback(response) else errorCallback(response) end
            return
        elseif threadStatus == 'canceled' then
            return errorCallback(threadStatus)
        end
    else
        return errorCallback(tostring(threadError))
    end
end

function asyncHttpRequest(httpMethod, url, requestBody, successCallback, errorCallback)
    requestBody         = requestBody or {}
    requestBody.headers = requestBody.headers or {}

    local requestThread = requestRunner()(httpMethod, url, requestBody)
    successCallback     = successCallback or function() end
    errorCallback       = errorCallback or function() end

    return {
        effilRequestThread  = requestThread,
        luaHttpHandleThread = lua_thread.create(
            handleAsyncHttpRequestThread, requestThread, successCallback, errorCallback
        )
    }
end

local updateState = {
    hasUpdate     = false,
    latestVersion = nil,
    updateUrl     = nil,
    changelog     = "",
    showPopup     = imgui.new.bool(false),
    declined      = false,
    checking      = false,
}

function downloadAndUpdate()
    if not updateState.updateUrl then return end
    utils.addChat("{FFE133}Загружаю обновление...")
    updateState.showPopup[0] = false

    asyncHttpRequest("GET", updateState.updateUrl, {}, function(resp)
        if resp.status_code == 200 or resp.status_code == 201 then
            local oldPath = thisScript().path
            local dir = oldPath:match("(.+)[/\\]")
            local newPath = dir .. "\\Mining Tools.lua"
            local sameFile = (oldPath:lower() == newPath:lower())

            local file = io.open(newPath, "wb")
            if file then
                file:write(resp.text)
                file:close()
                wait(50)

                if sameFile then
                    thisScript():reload()
                else
                    script.load(newPath)
                    wait(50)
                    for _, s in pairs(script.list()) do
                        if s.path == oldPath then
                            s:unload()
                            break
                        end
                    end
                    wait(50)
                    os.remove(oldPath)
                end
            else
                utils.addChat("{F78181}Не удалось сохранить файл обновления.")
            end
        else
            utils.addChat("{F78181}Ошибка загрузки: HTTP " .. tostring(resp.status_code))
        end
    end, function()
        utils.addChat("{F78181}Ошибка соединения при загрузке обновления.")
    end)
end

function checkForUpdates()
    if not cfg.checkForUpdates or updateState.checking then return end
    if UPDATE_CHECK_URL == nil then return end
    updateState.checking = true
    utils.debugChat("[UPDATE] Проверяю обновления...")

    asyncHttpRequest("GET", UPDATE_CHECK_URL, {}, function(resp)
        updateState.checking = false
        if resp.status_code == 200 or resp.status_code == 304 then
            local json     = require('dkjson')
            local ok, info = pcall(json.decode, resp.text)
            if ok and info and info.latest then
                if info.latest ~= script.this.version then
                    updateState.hasUpdate     = true
                    updateState.latestVersion = info.latest
                    updateState.updateUrl     = info.updateurl
                    updateState.changelog     = u8:decode(info.changelog or "")
                    updateState.showPopup[0]  = false
                    utils.debugChat("[UPDATE] Доступна версия: " .. info.latest)
                else
                    utils.debugChat("[UPDATE] Версия актуальна (" .. info.latest .. ")")
                end
            else
                utils.debugChat("[UPDATE] Не удалось разобрать ответ сервера")
            end
        else
            utils.debugChat("[UPDATE] HTTP ошибка: " .. tostring(resp.status_code))
        end
    end, function(err)
        updateState.checking = false
        utils.debugChat("[UPDATE] Ошибка соединения: " .. tostring(err or "unknown"))
    end)
end

local progressTracker = {
    reset = function()
        data.progressCurrent = 0
        data.progressTotal = 0
        data.progressHouseCurrent = 0
        data.progressHouseTotal = 0
    end,
    setTotal = function(total, houseTotal)
        data.progressTotal = total or 0
        data.progressHouseTotal = houseTotal or 0
    end,
    setHouseTotal = function(houseTotal)
        data.progressHouseTotal = houseTotal or 0
        data.progressHouseCurrent = 0
    end,
    increment = function(isHouse)
        if isHouse then
            data.progressHouseCurrent = data.progressHouseCurrent + 1
        else
            data.progressCurrent = data.progressCurrent + 1
        end
    end
}

local dialogActions = {
    selectHouse = function(sr, houseIndex)
        sr(dialogIdTable.houseDialogId, 1, houseIndex, "")
    end,
    selectCard = function(sr, cardIndex)
        local dialogId = data.isFlashminer and dialogIdTable.houseFlashMinerDialogId or dialogIdTable.videoCardSt
        sr(dialogId, 1, cardIndex, "")
    end,
    closeDialog = function(sr, dialogId)
        sr(dialogId or dialogIdTable.houseFlashMinerDialogId, 0, 0, "")
    end,
    withdrawBTC = function(sr)
        sr(dialogIdTable.videoCardDialogId, 1, 1, "")
        sr(dialogIdTable.videoCardAcceptDialogId, 1, 0, "")
    end,
    withdrawASC = function(sr)
        sr(dialogIdTable.videoCardDialogId, 1, 2, "")
        sr(dialogIdTable.videoCardAcceptDialogId, 1, 0, "")
    end,
    switchCard = function(sr)
        sr(dialogIdTable.videoCardDialogId, 1, 0, "")
        sr(dialogIdTable.videoCardDialogId, 0, 0, "")
    end,
    refillCoolant = function(sr, fluidType, useSuper, isAsic)
        local coolantIndex
        if data.isRodina then
            coolantIndex = isAsic and 3 or 2
        else
            coolantIndex = isAsic and 4 or 3
        end
        sr(dialogIdTable.videoCardDialogId, 1, coolantIndex, "")
        local fluid_listitem = (fluidType == 1 and (useSuper and 1 or 0)) or
            (fluidType == 2 and (useSuper and 1 or 2))
        if fluid_listitem ~= nil then
            sr(dialogIdTable.coolantDialogId, 1, fluid_listitem, "")
        end
    end
}

-- Логи
local logsTool = (function()
    local self                = {}

    local _logsPath           = getWorkingDirectory() .. '\\config\\' .. thisScript().name .. '\\logs.json'
    local _logs               = {}
    local _cache              = { collectBtc = 0, collectAsc = 0, sessions = 0 }
    local _statsCache         = { dirty = true, buildDate = "", byPeriod = {} }
    local _lastCoolantLogTime = 0

    local actions             = {
        collect = {
            icon   = fa.COINS,
            label  = "Сбор крипты",
            format = function(e)
                local parts = {}
                if (e.btc or 0) > 0 then table.insert(parts, string.format("%d BTC", e.btc)) end
                if (e.asc or 0) > 0 then table.insert(parts, string.format("%d ASC", e.asc)) end
                if (e.houses or 0) > 1 then table.insert(parts, string.format("%d дом.", e.houses)) end
                return table.concat(parts, "  ·  ")
            end,
        },
        switch = {
            iconFn  = function(e) return e.enabled and fa.POWER_OFF or fa.PLUG end,
            labelFn = function(e) return e.enabled and "Включение карт" or "Выключение карт" end,
            format  = function(e)
                local parts = {}
                if (e.count or 0) > 0 then table.insert(parts, string.format("%d карт", e.count)) end
                if (e.houses or 0) > 0 then table.insert(parts, string.format("%d дом.", e.houses)) end
                return table.concat(parts, "  ·  ")
            end,
        },
        coolant = {
            icon   = fa.DROPLET,
            label  = "Заливка жидкости",
            format = function(e)
                local parts = {}
                if (e.count or 0) > 0 then table.insert(parts, string.format("%d карт", e.count)) end
                if (e.bottles or 0) > 0 then
                    table.insert(parts, e.super
                        and string.format("%d супер", e.bottles)
                        or string.format("%d шт.", e.bottles))
                end
                return table.concat(parts, "  ·  ")
            end,
        },
        fix = {
            icon   = fa.WAND_MAGIC_SPARKLES,
            label  = "Авто-обслуживание",
            format = function(e)
                local parts = {}
                if (e.btc or 0) > 0 then table.insert(parts, string.format("%d BTC", e.btc)) end
                if (e.asc or 0) > 0 then table.insert(parts, string.format("%d ASC", e.asc)) end
                if (e.cards or 0) > 0 then table.insert(parts, string.format("%d вкл.", e.cards)) end
                if (e.topup or 0) > 0 then table.insert(parts, string.format("$%s", utils.formatNumber(e.topup))) end
                return table.concat(parts, "  ·  ")
            end,
        },
        topup = {
            icon   = fa.DOLLAR_SIGN,
            label  = "Пополнение баланса",
            format = function(e)
                local parts = {}
                if (e.topup or 0) > 0 then table.insert(parts, string.format("$%s", utils.formatNumber(e.topup))) end
                if (e.houses or 0) > 0 then table.insert(parts, string.format("%d дом.", e.houses)) end
                return table.concat(parts, "  ·  ")
            end,
        },
        tax = {
            icon   = fa.FILE_INVOICE_DOLLAR,
            label  = "Оплата налогов",
            format = function(e)
                return (e.amount or 0) > 0
                    and string.format("$%s", utils.formatNumber(e.amount))
                    or ""
            end,
        },
        improve = {
            icon    = fa.MICROCHIP,
            labelFn = function(e)
                if type(e.cards) == 'table' and #e.cards > 0 then
                    local hasStorage, hasPerf = false, false
                    for _, c in ipairs(e.cards) do
                        if c.isStorage then hasStorage = true else hasPerf = true end
                        if hasStorage and hasPerf then break end
                    end
                    if hasStorage and not hasPerf then return "Улучшение хранилища" end
                    if hasStorage and hasPerf then return "Заточка карт + хранилище" end
                end
                return "Заточка карт"
            end,
            format  = function(e)
                local parts = {}
                if (e.success or 0) > 0 then table.insert(parts, string.format("%d усп.", e.success)) end
                if (e.fail or 0) > 0 then table.insert(parts, string.format("%d пров.", e.fail)) end
                if (e.spent or 0) > 0 then table.insert(parts, string.format("$%s", utils.formatNumber(e.spent))) end
                if (e.attempts or 0) == 0 and (e.reason or "") ~= "" then
                    table.insert(parts, e.reason)
                end
                return table.concat(parts, "  ·  ")
            end,
        },
    }


    local function isDateInPeriod(dateStr, period)
        if period == 0 then return true end
        local d, m, y = dateStr:match("(%d+)%.(%d+)%.(%d+)")
        if not d then return false end
        if period == 1 then return dateStr == os.date('%d.%m.%Y') end
        local entryTime = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
        local diff = os.time() - entryTime
        if period == 2 then return diff < 7 * 86400 end
        if period == 3 then return diff < 30 * 86400 end
        return true
    end

    local function rebuildCache()
        _cache.collectBtc = 0
        _cache.collectAsc = 0
        _cache.sessions   = 0
        for _, dayEntries in pairs(_logs) do
            for _, e in ipairs(dayEntries) do
                _cache.sessions = _cache.sessions + 1
                if (e.action or 'collect') == 'collect' then
                    _cache.collectBtc = _cache.collectBtc + (e.btc or 0)
                    _cache.collectAsc = _cache.collectAsc + (e.asc or 0)
                end
            end
        end
    end

    local function rebuildStats()
        local result = {}
        for p = 0, 3 do
            result[p] = {
                btc                    = 0,
                asc                    = 0,
                collectSessions        = 0,
                switchOn               = 0,
                switchOff              = 0,
                coolantCards           = 0,
                coolantBottles         = 0,
                coolantSuper           = 0,
                topup                  = 0,
                improveSpent           = 0,
                improveOils            = 0,
                improveAttempts        = 0,
                improveSuccess         = 0,
                improveFail            = 0,
                improveSessions        = 0,
                improveByLevel         = {},
                improveCards           = {},
                improveAttemptsByLevel = {},
                improveStorageAttempts = 0,
                improveStorageSuccess  = 0,
                improveStorageFail     = 0,
                improveStorageOils     = 0,
                improveStorageSpent    = 0,
            }
        end
        for dateStr, dayEntries in pairs(_logs) do
            local inP = {}
            for p = 0, 3 do inP[p] = isDateInPeriod(dateStr, p) end
            for _, e in ipairs(dayEntries) do
                local act = e.action or 'collect'
                for p = 0, 3 do
                    if inP[p] then
                        local s = result[p]
                        if act == 'collect' then
                            s.btc = s.btc + (e.btc or 0)
                            s.asc = s.asc + (e.asc or 0)
                            s.collectSessions = s.collectSessions + 1
                        elseif act == 'switch' then
                            if e.enabled then
                                s.switchOn = s.switchOn + (e.count or 0)
                            else
                                s.switchOff = s.switchOff + (e.count or 0)
                            end
                        elseif act == 'coolant' then
                            s.coolantCards = s.coolantCards + (e.count or 0)
                            if e.super then
                                s.coolantSuper = s.coolantSuper + (e.bottles or 0)
                            else
                                s.coolantBottles = s.coolantBottles + (e.bottles or 0)
                            end
                        elseif act == 'fix' then
                            s.btc = s.btc + (e.btc or 0)
                            s.asc = s.asc + (e.asc or 0)
                            s.switchOn = s.switchOn + (e.cards or 0)
                            s.topup = s.topup + (e.topup or 0)
                        elseif act == 'topup' then
                            s.topup = s.topup + (e.topup or 0)
                        elseif act == 'improve' then
                            s.improveSpent    = s.improveSpent + (e.spent or 0)
                            s.improveOils     = s.improveOils + (e.oils or 0)
                            s.improveAttempts = s.improveAttempts + (e.attempts or 0)
                            s.improveSuccess  = s.improveSuccess + (e.success or 0)
                            s.improveFail     = s.improveFail + (e.fail or 0)
                            s.improveSessions = s.improveSessions + 1
                            if type(e.cards) == 'table' then
                                for _, c in ipairs(e.cards) do
                                    if c.isStorage then
                                        local cAtk               = c.attempts or 0
                                        local cSuc               = c.success or 0
                                        s.improveStorageAttempts = s.improveStorageAttempts + cAtk
                                        s.improveStorageSuccess  = s.improveStorageSuccess + cSuc
                                        s.improveStorageFail     = s.improveStorageFail + (cAtk - cSuc)
                                        s.improveStorageOils     = s.improveStorageOils + (c.oils or 0)
                                        s.improveStorageSpent    = s.improveStorageSpent + (c.spent or 0)
                                    end
                                end
                            end
                            if type(e.byLevel) == 'table' then
                                for lvl, cnt in pairs(e.byLevel) do
                                    local key = tonumber(lvl) or lvl
                                    s.improveByLevel[key] = (s.improveByLevel[key] or 0) + (cnt or 0)
                                end
                            end
                            if type(e.attemptsByLevel) == 'table' then
                                for lvl, cnt in pairs(e.attemptsByLevel) do
                                    local key = tonumber(lvl) or lvl
                                    s.improveAttemptsByLevel[key] =
                                        (s.improveAttemptsByLevel[key] or 0) + (cnt or 0)
                                end
                            end
                            if type(e.cards) == 'table' then
                                for _, c in ipairs(e.cards) do
                                    local cd = {
                                        date      = dateStr,
                                        time      = e.time,
                                        startedAt = e.startedAt,
                                        sessionId = (e.startedAt or 0) .. "|" .. (e.time or ""),
                                    }
                                    for k, v in pairs(c) do cd[k] = v end
                                    table.insert(s.improveCards, cd)
                                end
                            end
                        end
                    end
                end
            end
        end
        _statsCache.byPeriod = result
        _statsCache.dirty = false
        _statsCache.buildDate = os.date('%d.%m.%Y')
    end

    function self.load()
        local result = jcfg.load(_logsPath)
        if type(result) == 'table' then _logs = result end
        rebuildCache()
        self.invalidate()
    end

    function self.save()
        jcfg.save(_logs, _logsPath)
    end

    function self.add(action, details)
        local dateStr = os.date('%d.%m.%Y')
        local timeStr = os.date('%H:%M')
        if not _logs[dateStr] then _logs[dateStr] = {} end
        local entry = { time = timeStr, action = action }
        for k, v in pairs(details or {}) do entry[k] = v end
        table.insert(_logs[dateStr], entry)
        _cache.sessions = _cache.sessions + 1
        if action == 'collect' or action == 'fix' then
            _cache.collectBtc = _cache.collectBtc + (details.btc or 0)
            _cache.collectAsc = _cache.collectAsc + (details.asc or 0)
        end
        self.invalidate()
        self.save()
    end

    function self.addCoolant(count, bottles, isSuper)
        local now = os.time()
        if now - _lastCoolantLogTime < 10 then
            local dateStr = os.date('%d.%m.%Y')
            if _logs[dateStr] and #_logs[dateStr] > 0 then
                local last = _logs[dateStr][#_logs[dateStr]]
                if last.action == 'coolant' then
                    last.count   = (last.count or 0) + count
                    last.bottles = (last.bottles or 0) + bottles
                    self.invalidate()
                    self.save()
                    return
                end
            end
        end
        _lastCoolantLogTime = now
        self.add('coolant', { count = count, bottles = bottles, super = isSuper })
    end

    function self.getEntriesByDate(dateStr) return _logs[dateStr] or {} end

    function self.getAllByDate() return _logs end

    function self.getCacheSummary() return _cache end

    function self.getStats(period)
        local today = os.date('%d.%m.%Y')
        if _statsCache.dirty or _statsCache.buildDate ~= today then
            rebuildStats()
        end
        return _statsCache.byPeriod[period] or _statsCache.byPeriod[0]
    end

    function self.getAction(action) return actions[action] end

    function self.format(entry)
        local spec = actions[entry.action or 'collect']
        if not spec then return "", "", "" end
        local icon   = spec.iconFn and spec.iconFn(entry) or spec.icon or ""
        local label  = spec.labelFn and spec.labelFn(entry) or spec.label or ""
        local detail = spec.format and spec.format(entry) or ""
        return icon, label, detail
    end

    function self.invalidate() _statsCache.dirty = true end

    function self.clear()
        _logs  = {}
        _cache = { collectBtc = 0, collectAsc = 0, sessions = 0 }
        self.invalidate()
        self.save()
    end

    function self.clearImprove()
        for dateStr, dayEntries in pairs(_logs) do
            local filtered = {}
            for _, e in ipairs(dayEntries) do
                if (e.action or 'collect') ~= 'improve' then
                    table.insert(filtered, e)
                end
            end
            if #filtered > 0 then
                _logs[dateStr] = filtered
            else
                _logs[dateStr] = nil
            end
        end
        rebuildCache()
        self.invalidate()
        self.save()
    end

    self.load()

    return self
end)()

logsTool.load()

-- Для парсинга
local flashminerTool = (function()
    local self = {}

    local function parseList(text)
        data.dialogData.flashminer = {}

        local function parseAmount(str)
            if not str then return 0 end
            local kk, k = str:match(":KK:%s*([%d%.]+)%s+:K:%s*([%d%.]+)")
            kk, k = str:match(":KK:%s*([%d%.]+)%s+:K:%s*([%d%.]+)")
            if kk and k then
                return math.floor(tonumber((kk:gsub('%.', ''))) * 1e6 + tonumber((k:gsub('%.', ''))))
            end
            kk = str:match(":KK:%s*([%d%.]+)")
            if kk then return math.floor(tonumber((kk:gsub('%.', ''))) * 1e6) end
            k = str:match(":K:%s*([%d%.]+)")
            if k then return math.floor(tonumber((k:gsub('%.', '')))) end
            local clean = str:gsub("[%$%.%s]", "")
            return tonumber(clean) or 0
        end

        for line in text:gmatch("[^\r\n]+") do
            if line:find("Номер дома") or line:find("Город") or line:find("Налог") then
                goto continue
            end

            local list_id, house_num = line:match("%[(%d+)%]%s+Дом №(%d+)")
            if not (list_id and house_num) then goto continue end

            local after_num = (line:match("Дом №%d+%s+(.+)") or ""):gsub("{%w+}", ""):gsub("%[%x%x%x%x%x%x%]", "")
            local parts = {}
            for w in after_num:gmatch("%S+") do table.insert(parts, w) end

            local city, tax, cycles, balance, max_balance = "", nil, 0, 0, 0
            local cycles_index = nil
            for i, part in ipairs(parts) do
                cycles_index = part == "циклов" and i or cycles_index
                if cycles_index then break end
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
                    local left_str, right_str = bal_paren:match("^(.-)%s*/%s*(.-)$")
                    balance                   = parseAmount(left_str)
                    max_balance               = parseAmount(right_str)
                end
            end

            local house_data = {
                index        = tonumber(list_id),
                name         = "Дом №" .. house_num,
                house_number = tonumber(house_num),
                city         = city,
                tax          = tax,
                cycles       = cycles,
                balance      = balance,
                max_balance  = max_balance,
                raw_line     = line
            }

            table.insert(data.dialogData.flashminer, house_data)
            if not data.houseStatuses then data.houseStatuses = {} end
            if not data.houseStatuses[house_data.house_number] then
                data.houseStatuses[house_data.house_number] = {
                    status         = balance < 5000000 and "warning" or "good",
                    lastCheck      = 0,
                    needsAttention = false,
                    lastBalance    = balance
                }
            end

            ::continue::
        end
    end

    function self.parseDialogText(text) parseList(text) end

    function self.requestList(timeoutMs, cancelCheckFn)
        timeoutMs = timeoutMs or 5000
        data.dialogData.flashminer = {}
        sampSendChat("/flashminer")
        wait(200)
        local t = 0
        while #data.dialogData.flashminer == 0 and t < timeoutMs do
            wait(200); t = t + 200
            if data.hasFlashminer == false then return false end
            if cancelCheckFn and cancelCheckFn() then return false end
        end
        return #data.dialogData.flashminer > 0
    end

    function self.navigate(direction)
        if data.working then return end
        data.flashminerSwitchId.direction = direction
        data.flashminerSwitchId.id = data.dFlashminerId
        sampSendDialogResponse(data.dFlashminerId, 0, -1, "")
    end

    function self.getHouses() return data.dialogData.flashminer end

    function self.hasIt() return data.hasFlashminer ~= false end

    function self.isOpen() return data.isFlashminer end

    return self
end)()

-- Предикт
local houseFilter = (function()
    local self = {}

    function self.isExcluded(houseNum)
        return cfg.excludedHouses[tostring(houseNum)] == true
    end

    function self.hasNoBasement(houseNum)
        return cfg.housesWithoutBasement
            and cfg.housesWithoutBasement[tostring(houseNum)] == true
    end

    function self.shouldSkip(houseNum)
        return self.isExcluded(houseNum) or self.hasNoBasement(houseNum)
    end

    function self.shouldProcess(house)
        return not self.shouldSkip(house.house_number)
    end

    function self.getDailyIncome(houseNum)
        local houseId = tostring(houseNum)
        local snapshot = cfg.cardSnapshots[houseId]

        if snapshot and snapshot.dailyBtcRate and snapshot.dailyBtcRate > 0 then
            return snapshot.dailyBtcRate, 0
        end

        return 0, 0
    end

    return self
end)()

-- Контроль задач
local taskState = (function()
    local self = {}
    local SUPPRESS_TAIL_SEC = 0.5
    function self.refreshSuppressDialogs()
        data.suppressDialogs =
            data.working
            or data.silentWindowOpen
            or (os.clock() < (data.suppressDialogsUntil or 0))
    end

    function self.setWorking(state)
        if data.working and not state then
            data.suppressDialogsUntil = os.clock() + SUPPRESS_TAIL_SEC
        end
        data.working = state
        self.refreshSuppressDialogs()
    end

    function self.setSilent(state)
        if data.silentWindowOpen and not state then
            data.suppressDialogsUntil = os.clock() + SUPPRESS_TAIL_SEC
        end
        data.silentWindowOpen = state
        self.refreshSuppressDialogs()
    end

    function self.ifNotWorking(func)
        if not data.working then return func() end
        utils.addChat("{F78181}Уже выполняется другая операция.")
        return false
    end

    function self.isAutomationAllowed()
        if not cfg.waitForConnection then return true end
        if not data.connectionState.connected then return false end
        if os.time() < data.connectionState.readyAfterConnect then return false end
        return true
    end

    return self
end)()

-- Для заточки
local improveTool = (function()
    local self = {}
    local imp  = data.improve

    local function normalizeCardName(name)
        local s = tostring(name or '')
        s = s:gsub('^%s+', ''):gsub('%s+$', '')
        s = s:gsub('%s+%(%+1%)', '(+1)')
        return s
    end

    local function parseCardMeta(name)
        local n = normalizeCardName(name)
        if n == 'Видеокарта' then return 1, false end
        if n == 'Видеокарта(+1)' then return 1, true end
        if n == 'Arizona Video Card' then return 2, false end
        if n == 'Arizona Video Card(+1)' then return 2, true end
        return nil, false
    end

    function self.getOilCount()
        local isAZ  = (cfg.improveTypeCards == 2)
        local count = isAZ and (imp.oils.arizona or 0) or (imp.oils.classic or 0)
        local name  = isAZ and "Arizona смазка" or "Обычная смазка"
        return count, name
    end

    function self.hasRequiredOils(n)
        if imp.useStorageUpgrade then return true end
        if not cfg.improveCheckOilsOnStart then return true end
        local count = self.getOilCount()
        return count >= (n or 2)
    end

    function self.consumeOils(n)
        n = n or 2
        if cfg.improveTypeCards == 2 then
            imp.oils.arizona = math.max(0, (imp.oils.arizona or 0) - n)
        else
            imp.oils.classic = math.max(0, (imp.oils.classic or 0) - n)
        end
        imp.pendingOilsUsed = (imp.pendingOilsUsed or 0) + n
        utils.debugChat(string.format("[IMPROVE] Резерв %d смазки (учёт отложен). Остаток: AZ=%d, Обычная=%d.",
            n, imp.oils.arizona, imp.oils.classic))
    end

    local function resetCefInventory()
        imp.cef.cards            = {}
        imp.cef.probing          = false
        imp.cef.probeDone        = false
        imp.cef.probed           = false
        imp.cef.pendingSlot      = nil
        imp.cef.pendingIndex     = 0
        imp.cef.probeAbort       = false
        imp.cef.probeAbortReason = ''
        imp.cef.probeProgress    = 0
        imp.cef.probeTotal       = 0
    end

    local function addCefCardSlot(slot, itemName, hasStorage, cardType)
        slot = tonumber(slot or 0) or 0
        if slot <= 0 then return end
        local parsedType, parsedStorage = parseCardMeta(itemName)
        local ctype                     = tonumber(cardType or parsedType or 0) or 0
        local storage                   = (hasStorage == true) or parsedStorage
        if ctype ~= 1 and ctype ~= 2 then return end

        for _, c in ipairs(imp.cef.cards) do
            if c.slot == slot then
                c.name           = tostring(itemName or c.name or '')
                c.cardType       = ctype
                c.storageUpgrade = storage or (c.storageUpgrade == true)
                return
            end
        end

        table.insert(imp.cef.cards, {
            slot           = slot,
            name           = tostring(itemName or ''),
            cardType       = ctype,
            level          = imp.cef.knownLevels[slot] or 0,
            storageUpgrade = (imp.cef.knownStorage[slot] == true) or storage,
        })
    end

    local function moveMaxLevelToEnd(cards)
        if type(cards) ~= "table" or #cards <= 1 then return cards end
        local active, maxed = {}, {}
        for _, c in ipairs(cards) do
            if (tonumber(c.level or 0) or 0) >= 10 then
                table.insert(maxed, c)
            else
                table.insert(active, c)
            end
        end
        if #maxed == 0 or #active == 0 then return cards end
        for _, c in ipairs(maxed) do table.insert(active, c) end
        return active
    end

    local function syncVideoCards()
        local cards = {}
        local selectedType = tonumber(cfg.improveTypeCards or 1) or 1
        for _, c in ipairs(imp.cef.cards or {}) do
            if tonumber(c.cardType or 0) == selectedType then
                table.insert(cards, {
                    slot           = c.slot,
                    cardType       = tonumber(c.cardType or 0) or 0,
                    level          = tonumber(c.level or 0) or 0,
                    storageUpgrade = c.storageUpgrade == true,
                })
            end
        end
        if cfg.improveMode == 1 and cfg.improveMenuAll then
            table.sort(cards, function(a, b) return (a.level or 0) < (b.level or 0) end)
        end
        imp.videoCards = moveMaxLevelToEnd(cards)
    end
    self.syncVideoCards = syncVideoCards

    function self.parseInventoryPage(text)
        for line in (text or ''):gmatch("[^\r\n]+") do
            local indexSlot, name, count = line:match("%[([^%]]+)%]%s(.-)%s%{.-}%[([^%]]+)%sшт%]")
            local slotNum                = tonumber(indexSlot)
            count                        = tonumber(count)
            if indexSlot and name and count then
                if name == "Смазка для разгона Arizona Video Card" then
                    imp.oils.arizona = imp.oils.arizona + count
                elseif name == "Смазка для разгона видеокарты" then
                    imp.oils.classic = imp.oils.classic + count
                end
                if slotNum and count > 0 then
                    local cardType, cardStorage = parseCardMeta(name)
                    if cardType ~= nil then
                        addCefCardSlot(slotNum, name, cardStorage, cardType)
                    end
                end
            end
        end
    end

    local function parseLevelFromDialog(text)
        local t = tostring(text or '')
        local cur = t:match('Сейчас%s+уровень%s+производительности%s+видеокарты:%s*(%d+)%s*из%s*10')
        if cur then return math.max(0, tonumber(cur) or 0) end
        for line in t:gmatch('[^\r\n]+') do
            if line:find('Улучшить производительность видео-карты', 1, true) then
                local m = tonumber(line:match('до%s+(%d+)%s+уровн'))
                if m then return math.max(0, m - 1) end
            end
        end
        return nil
    end

    local function clickCefSlot(slot, action, clickType)
        slot      = tonumber(slot or 0) or 0
        action    = tonumber(action or 1) or 1
        clickType = tonumber(clickType or 1) or 1
        if slot <= 0 then return false end
        sendcef(string.format('clickOnButton|{"type": %d,"slot": %d, "action": %d}',
            clickType, slot, action))
        return true
    end

    local function openCardDialog(slot)
        if (tonumber(slot) or 0) <= 0 then return false end
        sampSendChat('/invent')
        wait(cfg.improveProbeOpenDelay or 1500)
        return clickCefSlot(slot, 1, 1)
    end
    self.openCardDialog = openCardDialog

    function self.refreshInventory(async)
        if imp.oils.busy then return end
        imp.oils.arizona, imp.oils.classic = 0, 0
        resetCefInventory()
        imp.oils.busy = true
        imp.oils.busyAt = os.clock()
        utils.debugChat("[IMPROVE] /stats — обновление инвентаря.")
        sampSendChat('/stats')

        local function done()
            utils.debugChat(string.format(
                "[IMPROVE] Инвентарь обновлён: AZ=%d, Обычная=%d, видеокарт=%d.",
                imp.oils.arizona, imp.oils.classic, #imp.cef.cards))
            syncVideoCards()
            imp.cef.probed = false
        end

        if async then
            lua_thread.create(function()
                while imp.oils.busy do wait(10) end
                done()
            end)
        else
            while imp.oils.busy do wait(10) end
            done()
            return true
        end
    end

    function self.handleOilsDialog(dialogId, title, text)
        if not imp.oils.busy then return false end

        if (title or ''):find("Основная статистика") then
            sampSendDialogResponse(dialogId, 1, 0, '')
            return true
        end

        if (title or ''):find("ID:") then
            self.parseInventoryPage(text or '')
            if (text or ''):find("Следующая страница", 1, true) then
                sampSendDialogResponse(dialogId, 1, 0, '')
                return true
            end
            imp.oils.busy   = false
            imp.oils.busyAt = 0
            imp.oils.lastAt = os.date('%H:%M')
            sampSendDialogResponse(dialogId, 0, 0, '')
            return true
        end

        return false
    end

    local function sessionStart()
        local s           = imp.stats
        s.sessionId       = (s.sessionId or 0) + 1
        s.active          = true
        s.startedAt       = os.time()
        s.byLevel         = {}
        s.cards           = {}
        s.attemptsByLevel = {}
        s.finishedAt      = 0
        s.attempts        = 0
        s.success         = 0
        s.fail            = 0
        s.oilsUsed        = 0
        s.spent           = 0
        s.lastReason      = ""
        s.lastAttempt     = nil
        utils.debugChat(string.format(
            "[IMPROVE] Старт заточки #%d. Карты: %s, режим: %s, цель: %d ур.",
            s.sessionId,
            cfg.improveTypeCards == 2 and "Arizona" or "Обычные",
            cfg.improveMode == 1 and "Последовательное" or "Поочередное",
            cfg.improveMaxLevel))
    end

    local function sessionStop(reason)
        local s = imp.stats
        if not s.active then return end
        s.active     = false
        s.finishedAt = os.time()
        s.lastReason = reason or "не указано"

        if (s.attempts or 0) > 0 then
            logsTool.add('improve', {
                attempts        = s.attempts,
                success         = s.success,
                fail            = s.fail,
                oils            = s.oilsUsed,
                spent           = s.spent,
                reason          = s.lastReason,
                byLevel         = s.byLevel or {},
                duration        = (s.finishedAt or 0) - (s.startedAt or 0),
                startedAt       = s.startedAt,
                attemptsByLevel = s.attemptsByLevel or {},
                cards           = (function()
                    local arr = {}
                    for _, c in pairs(s.cards or {}) do
                        if (c.attempts or 0) > 0 then table.insert(arr, c) end
                    end
                    return arr
                end)(),
            })
        end

        utils.addChat(string.format(
            "{BEF781}Заточка завершена. {ffffff}Попыток: %d, удачно: %d, неудачно: %d, потрачено: $%s",
            s.attempts, s.success, s.fail, utils.formatNumber(s.spent or 0)))
    end

    local function attemptStart()
        local s = imp.stats
        if not s.active then return end
        s.attempts      = (s.attempts or 0) + 1

        local idx       = imp.currentIndex or 0
        local card      = imp.videoCards[idx]
        local fromLevel = tonumber(card and card.level or 0) or 0
        local price     = 0

        s.lastAttempt   = {
            isStorage = imp.useStorageUpgrade == true,
            fromLevel = fromLevel,
            toLevel   = fromLevel + 1,
        }

        if not imp.useStorageUpgrade and fromLevel >= 1 and fromLevel <= 9 then
            s.attemptsByLevel[fromLevel] = (s.attemptsByLevel[fromLevel] or 0) + 1
        end
        if not imp.useStorageUpgrade and fromLevel >= 1 and fromLevel <= 9 then
            price = tonumber(gpuImprovePriceByLevel[fromLevel]) or 0
            s.spent = (s.spent or 0) + price
            s.lastAttempt.spent = price
        end

        local slot = card and card.slot
        if slot then
            s.cards = s.cards or {}
            local c = s.cards[slot]
            if not c then
                c = {
                    slot       = slot,
                    startLevel = fromLevel,
                    endLevel   = fromLevel,
                    attempts   = 0,
                    success    = 0,
                    spent      = 0,
                    oils       = 0,
                    isStorage  = imp.useStorageUpgrade == true,
                }
                s.cards[slot] = c
            end
            c.attempts        = c.attempts + 1
            c.spent           = c.spent + price
            s.currentCardSlot = slot

            local pending     = imp.pendingOilsUsed or 0
            if pending > 0 then
                s.oilsUsed = (s.oilsUsed or 0) + pending
                c.oils     = (c.oils or 0) + pending
            end
        end
        imp.pendingOilsUsed = 0

        utils.debugChat(string.format(
            "[IMPROVE] Попытка #%d: карта #%d, ур. %d, цена: $%d",
            s.attempts, idx, fromLevel, price))
    end

    local function doStop(reason)
        sessionStop(reason or "остановлено вручную")
        imp.isOn            = false
        imp.step            = improveStep.STOPPED
        imp.needCheckOils   = false
        imp.waitOils        = false
        imp.waitStart       = false
        imp.waitStartAt     = 0
        imp.waitResultAt    = 0
        imp.lastUseAt       = 0
        imp.consumedThisTry = false
        imp.currentIndex    = 0
        imp.pendingOilsUsed = 0
        imp.pendingStop     = nil
        resetCefInventory()
        imp.cef.needInventoryRefresh = true
        fixI()
    end

    function self.stop(reason)
        if reason == "Остановлено"
            and imp.isOn and imp.stats.active
            and imp.step == improveStep.WAIT_RESULT
            and imp.stats.lastAttempt then
            if not imp.pendingStop then
                imp.pendingStop = { reason = reason }
                utils.addChat("{FFE133}Ожидаю результат текущей попытки перед остановкой...")
            end
            return
        end
        doStop(reason)
    end

    function self.start()
        if imp.isOn then return end
        imp.isOn                     = true
        imp.consumedThisTry          = false
        imp.waitStartAt              = 0
        imp.waitResultAt             = 0
        imp.lastUseAt                = 0
        imp.cef.needInventoryRefresh = false
        imp.cef.waitInventory        = false
        imp.cef.probed               = false
        imp.cef.probing              = false
        imp.pendingOilsUsed          = 0
        imp.pendingStop              = nil


        if cfg.improveCheckOilsOnStart then
            imp.step          = improveStep.STOPPED
            imp.needCheckOils = true
        else
            imp.step          = improveStep.SELECT_CARD
            imp.needCheckOils = false
        end
        imp.cef.needInventoryRefresh = not cfg.improveCheckOilsOnStart
        imp.useStorageUpgrade = cfg.improveUseStorageUpgrade
        sessionStart()
        utils.addChat("{BEF781}Заточка видеокарт запущена.")
    end

    local function onResult(success, serverMsg)
        if not imp.currentIndex or imp.currentIndex <= 0 then return end
        local card = imp.videoCards[imp.currentIndex]
        if not card then return end

        local s = imp.stats

        if imp.useStorageUpgrade then
            if success then
                card.storageUpgrade = true
                imp.cef.knownStorage[card.slot] = true
                if data.improve.storageQueue then
                    data.improve.storageQueue[card.slot] = nil
                end
            end
        else
            local oldLvl = card.level or 0
            local newLvl = oldLvl
            if success then
                local parsedLvl
                if serverMsg then
                    local lvlText = serverMsg:match("до%s+(%d+)%D+уров")
                        or serverMsg:match("до%s+(%d+)%s+уровн")
                    if lvlText then parsedLvl = tonumber(lvlText) end
                end
                newLvl = parsedLvl or (oldLvl + 1)
                if newLvl > 10 then newLvl = 10 end
                card.level = newLvl
                imp.cef.knownLevels[card.slot] = newLvl
                if s.active then
                    s.byLevel = s.byLevel or {}
                    s.byLevel[newLvl] = (s.byLevel[newLvl] or 0) + 1
                    s.cards = s.cards or {}
                    local c = s.cards[card.slot]
                    if c then
                        c.endLevel = newLvl
                        c.success  = (c.success or 0) + 1
                    end
                end
            end
            if cfg.improveMenuAll and cfg.improveMode == 1 then
                table.sort(imp.videoCards, function(a, b) return (a.level or 0) < (b.level or 0) end)
            end
            imp.videoCards = moveMaxLevelToEnd(imp.videoCards)
        end

        if s.active then
            if success then
                s.success = (s.success or 0) + 1
            else
                s.fail = (s.fail or 0) + 1
            end
            s.lastAttempt = nil
        end

        utils.debugChat(string.format("[IMPROVE] Результат: %s, карта #%d",
            success and "УСПЕХ" or "ОШИБКА", imp.currentIndex))
    end

    local function markAttemptTimedOut()
        local s = imp.stats
        if not s.active then return end
        s.fail = (s.fail or 0) + 1
        s.lastAttempt = nil
    end

    local function handleWaitStartMessage(text)
        if not (imp.isOn and imp.waitStart) then return end
        local matched
        if imp.useStorageUpgrade then
            matched = text:find('начали%s+процесс') and text:find('увеличения%s+объема')
        else
            matched = text:find('начали%s+процесс') and text:find('производительности')
        end
        if matched then
            imp.waitStart    = false
            imp.waitStartAt  = 0
            imp.waitResultAt = os.clock()
            imp.step         = improveStep.WAIT_RESULT
            attemptStart()
        end
    end

    local function handleRetryMessage(text)
        if not (imp.isOn and imp.step == improveStep.CONFIRM) then return end
        if text:find('Подождите немного') then
            utils.debugChat("[IMPROVE] Сервер: 'Подождите немного' — повтор клика.")
            lua_thread.create(function()
                wait(1000)
                if imp.isOn and imp.step == improveStep.CONFIRM then
                    local card = imp.videoCards[imp.currentIndex or 0]
                    local slot = card and tonumber(card.slot or 0) or 0
                    if slot > 0 then
                        openCardDialog(slot)
                        imp.lastUseAt = os.clock()
                    end
                end
            end)
        end
    end

    local function handleNoOilsMessage(text)
        if not imp.isOn then return end
        if text:find('нет%s+%d+шт%.?%s*смазки') or text:find('нет%s+смазки%s+для%s+видеокарты') then
            utils.addChat("{F78181}Нет смазки! Заточка остановлена.")
            self.stop("Сервер: нет смазки")
        end
    end

    local function handleNoMoneyMessage(text)
        if not imp.isOn then return end
        if text:find('недостаточно денег', 1, true) then
            utils.addChat("{F78181}У вас недостаточно денег! Заточка остановлена.")
            self.stop("Сервер: недостаточно денег")
        end
    end

    local function handleStorageUpgradeMessage(text)
        if not (imp.isOn and imp.step == improveStep.CONFIRM and imp.useStorageUpgrade) then return end

        if text:find('У вас нет увеличителя пропускной способности', 1, true) then
            utils.addChat("{F78181}У вас нет увеличителя пропускной способности!")
            self.stop("Нет увеличителя пропускной способности")
        elseif text:find('уже увеличен объём хранение криптовалюты', 1, true) then
            utils.debugChat("[IMPROVE] Карта уже улучшена, пропускаем.")
            lua_thread.create(function()
                wait(cfg.improveWaitResult or 600)
                local card = imp.videoCards[imp.currentIndex]
                if card then card.storageUpgrade = true end
                imp.step            = improveStep.SELECT_CARD
                imp.consumedThisTry = false
            end)
        end
    end

    local function handleResultMessage(text)
        if not (imp.isOn and imp.step == improveStep.WAIT_RESULT) then return end

        local isFail = text:find('При%s+улучшении') and text:find('допустили%s+техническую%s+ошибку')
        local isSuccess
        if imp.useStorageUpgrade then
            isSuccess = text:find('успешно%s+увеличили%s+объем')
        else
            isSuccess = text:find('успешно%s+улучшили')
        end

        if isFail or isSuccess then
            onResult(isSuccess ~= nil and isSuccess ~= false, text)
            lua_thread.create(function()
                wait(cfg.improveWaitResult or 600)
                imp.waitResultAt    = 0
                imp.lastUseAt       = 0
                imp.step            = improveStep.SELECT_CARD
                imp.consumedThisTry = false
            end)
        end
    end

    local function handleProbeMessage(text)
        if imp.cef.probing and text:find('должны находиться в подвале возле одной из специальных стоек') then
            imp.cef.probeAbort       = true
            imp.cef.probeAbortReason = 'нужно стоять у стойки в подвале'
            imp.cef.probeDone        = true
        end
    end

    function self.handleServerMessage(text)
        handleWaitStartMessage(text)
        handleRetryMessage(text)
        handleStorageUpgradeMessage(text)
        handleResultMessage(text)
        handleProbeMessage(text)
        handleNoOilsMessage(text)
        handleNoMoneyMessage(text)
    end

    function self.handleChooseDialog(dialogId, title, text)
        local dt        = tostring(title or '')
        local dx        = tostring(text or '')
        local isChoose  = dt:find('{BFBBBA}Выберите вид улучшения для видеокарты', 1, true) ~= nil
        local isUpgrade = dt:find('{BFBBBA}Улучшение видеокарты', 1, true) ~= nil

        if (isChoose or isUpgrade) and not imp.isOn and not imp.cef.probing then
            sampSendDialogResponse(dialogId, 0, 0, '')
            return true
        end

        if (isChoose or isUpgrade)
            and (imp.cef.lastProbeAt or 0) > 0
            and (os.clock() - imp.cef.lastProbeAt) < 5 then
            sampSendDialogResponse(dialogId, 0, 0, '')
            return true
        end

        if not isChoose and not (imp.cef.probing and isUpgrade) then return false end


        if imp.cef.probing and imp.cef.pendingSlot then
            local card
            for _, c in ipairs(imp.cef.cards or {}) do
                if tonumber(c.slot or 0) == tonumber(imp.cef.pendingSlot or 0) then
                    card = c; break
                end
            end
            if card then
                local lvl = parseLevelFromDialog(dx)
                if lvl ~= nil then
                    card.level = lvl
                else
                    card.level = 10
                end
                imp.cef.knownLevels[card.slot] = card.level
                if dx:find('Увеличить объем хранения криптовалюты на видео-карте', 1, true) then
                    card.storageUpgrade = false
                elseif isChoose then
                    card.storageUpgrade = true
                end
                imp.cef.knownStorage[card.slot] = card.storageUpgrade
            end
            imp.cef.probeDone = true
            sampSendDialogResponse(dialogId, 0, 0, '')
            return true
        end

        if not isChoose then return false end
        if imp.isOn and imp.step ~= improveStep.CONFIRM then
            utils.debugChat(string.format(
                "[IMPROVE] Choose-диалог пришел на шаге %s (не CONFIRM) — закрываем.",
                tostring(imp.step)))
            sampSendDialogResponse(dialogId, 0, 0, '')
            return true
        end

        local perfIndex, storageIndex
        local idx = -1
        for line in dx:gmatch('[^\r\n]+') do
            idx = idx + 1
            if line:find('Улучшить производительность видео-карты', 1, true) then perfIndex = idx end
            if line:find('Увеличить объем хранения криптовалюты на видео-карте', 1, true) then storageIndex = idx end
        end

        local listToClick = 0
        if imp.useStorageUpgrade and storageIndex then
            listToClick = storageIndex
        elseif perfIndex then
            listToClick = perfIndex
        end

        sampSendDialogResponse(dialogId, 1, listToClick, '')
        return true
    end

    function self.handleConfirmDialog(dialogId, title)
        local isUpgradeDialog = (title or ''):find('{BFBBBA}Улучшение видеокарты') ~= nil

        if isUpgradeDialog and not (imp.isOn and imp.step == improveStep.CONFIRM) then
            sampSendDialogResponse(dialogId, 0, 0, '')
            return true
        end

        if not (imp.isOn and imp.step == improveStep.CONFIRM) then return false end
        if not isUpgradeDialog then return false end

        if not imp.useStorageUpgrade then
            if not self.hasRequiredOils(2) then
                utils.addChat("{F78181}Недостаточно смазки (нужно 2). Заточка остановлена.")
                self.stop("Недостаточно смазки")
                return true
            end
            if not imp.consumedThisTry then
                self.consumeOils(2)
                imp.consumedThisTry = true
            end
        end

        sampSendDialogResponse(dialogId, 1, 0, '')
        imp.waitStart   = true
        imp.waitStartAt = os.clock()
        return true
    end

    local function runProbeLoop(allowWhenStopped, forceAll)
        imp.cef.probing          = true
        imp.cef.probeDone        = false
        imp.cef.probed           = false
        imp.cef.probeAbort       = false
        imp.cef.probeAbortReason = ''
        imp.cef.probeProgress    = 0

        local selectedType       = tonumber(cfg.improveTypeCards or 1) or 1
        local totalOfType        = 0
        local probeCards         = {}
        for _, c in ipairs(imp.cef.cards or {}) do
            if tonumber(c.cardType or 0) == selectedType then
                totalOfType = totalOfType + 1
                if forceAll or (c.level or 0) == 0 then
                    table.insert(probeCards, c)
                end
            end
        end

        if totalOfType == 0 then
            imp.cef.probeAbort       = true
            imp.cef.probeAbortReason = 'нет карт выбранного типа'
        end
        if totalOfType > 0 and #probeCards == 0 then
            imp.cef.probing       = false
            imp.cef.probed        = true
            imp.cef.probeProgress = 0
            imp.cef.probeTotal    = 0
            syncVideoCards()
            imp.cef.lastProbeAt = os.clock()
            utils.debugChat("[IMPROVE] Все уровни уже известны, probe пропущен.")
            return
        end

        if #probeCards == 0 then
            imp.cef.probeAbort       = true
            imp.cef.probeAbortReason = 'нет карт выбранного типа'
        end

        imp.cef.probeTotal = #probeCards
        utils.debugChat(string.format("[IMPROVE] Проверка уровней: %d карт.", #probeCards))

        for idx, card in ipairs(probeCards) do
            if ((not imp.isOn) and (not allowWhenStopped)) then break end
            if imp.cef.probeAbort then break end

            imp.cef.pendingIndex  = idx
            imp.cef.pendingSlot   = card.slot
            imp.cef.probeProgress = math.max(0, idx - 1)
            imp.cef.probeDone     = false

            openCardDialog(card.slot)

            local timeoutAt = os.clock() + (cfg.improveTimeoutDialog or 10)
            while (imp.isOn or allowWhenStopped)
                and not imp.cef.probeDone
                and not imp.cef.probeAbort
                and os.clock() < timeoutAt do
                wait(25)
            end

            if imp.cef.probeAbort then break end
            if not imp.cef.probeDone then
                imp.cef.probeAbort       = true
                imp.cef.probeAbortReason = string.format('таймаут диалога (slot %d)', card.slot)
                break
            end
            imp.cef.probeProgress = idx
            wait(cfg.improveWaitTryClick or 300)
        end

        local aborted        = imp.cef.probeAbort == true
        local abortReason    = imp.cef.probeAbortReason or ''

        imp.cef.probing      = false
        imp.cef.pendingSlot  = nil
        imp.cef.pendingIndex = 0
        imp.cef.probeDone    = false

        syncVideoCards()

        if aborted then
            imp.cef.probed = false
            utils.addChat("{F78181}Проверка уровней остановлена: " .. abortReason)
            if imp.isOn and not allowWhenStopped then
                self.stop("Probe: " .. abortReason)
            end
        else
            imp.cef.probed        = true
            imp.cef.probeProgress = imp.cef.probeTotal or #imp.videoCards
            utils.debugChat(string.format("[IMPROVE] Проверка завершена, карт: %d.", #imp.videoCards))
        end
        imp.cef.lastProbeAt = os.clock()
    end

    local function startProbe(allowWhenStopped, forceAll)
        if imp.cef.probing then return end
        syncVideoCards()
        if #imp.videoCards == 0 then
            imp.cef.probed = true
            return
        end
        runProbeLoop(allowWhenStopped, forceAll)
    end

    function self.checkLevels()
        if imp.oils.busy then
            if (imp.oils.busyAt or 0) > 0 and os.clock() - imp.oils.busyAt > 15 then
                imp.oils.busy   = false
                imp.oils.busyAt = 0
                utils.debugChat("[IMPROVE] checkLevels: насильно сбрасываю busy.")
            else
                utils.addChat("{FFE133}Дождитесь обновления инвентаря.")
                return
            end
        end
        if imp.cef.probing then
            utils.addChat("{FFE133}Проверка уровней уже выполняется.")
            return
        end
        lua_thread.create(function()
            self.refreshInventory(false)
            if #imp.cef.cards == 0 then
                utils.addChat("{FFE133}Видеокарты в инвентаре не найдены.")
                return
            end
            syncVideoCards()
            imp.cef.probed = false
            startProbe(true, true)
        end)
    end

    local function tickWatchdogs()
        if not imp.isOn then return end
        local now = os.clock()

        if imp.step == improveStep.CONFIRM then
            local retryMs = math.max(200, tonumber(cfg.improveRetryUseDelay or 1200) or 1200)
            if not imp.waitStart then
                if (imp.lastUseAt or 0) <= 0 then
                    imp.lastUseAt = now
                elseif (now - imp.lastUseAt) * 1000 >= retryMs then
                    local card = imp.videoCards[imp.currentIndex or 0]
                    local slot = card and tonumber(card.slot or 0) or 0
                    if slot > 0 then
                        openCardDialog(slot)
                        imp.lastUseAt = now
                    else
                        imp.step            = improveStep.SELECT_CARD
                        imp.consumedThisTry = false
                        imp.lastUseAt       = 0
                    end
                end
            else
                local timeout = math.max(1, tonumber(cfg.improveWaitStartTimeout or 8) or 8)
                if (imp.waitStartAt or 0) > 0 and (now - imp.waitStartAt) >= timeout then
                    utils.debugChat("[IMPROVE] Таймаут ожидания старта.")
                    imp.waitStart       = false
                    imp.waitStartAt     = 0
                    imp.step            = improveStep.SELECT_CARD
                    imp.consumedThisTry = false
                end
            end
        elseif imp.step == improveStep.WAIT_RESULT then
            local timeout = math.max(1, tonumber(cfg.improveWaitResultTimeout or 20) or 20)
            if (imp.waitResultAt or 0) > 0 and (now - imp.waitResultAt) >= timeout then
                utils.debugChat("[IMPROVE] Таймаут результата — фиксирую как ошибку.")
                markAttemptTimedOut()
                imp.waitResultAt    = 0
                imp.step            = improveStep.SELECT_CARD
                imp.consumedThisTry = false
            end
        end
    end

    local function tickSelectCard()
        if imp.step ~= improveStep.SELECT_CARD then return end

        if imp.pendingStop then
            local reason = imp.pendingStop.reason
            imp.pendingStop = nil
            doStop(reason)
            return
        end

        if imp.oils.busy then return end

        if (not imp.useStorageUpgrade) and (not self.hasRequiredOils(2)) then
            utils.addChat("{F78181}Смазка закончилась. Заточка остановлена.")
            self.stop("Закончилась смазка")
            return
        end

        if imp.cef.needInventoryRefresh then
            if not imp.oils.busy then
                self.refreshInventory(true)
                imp.cef.needInventoryRefresh = false
                imp.cef.waitInventory        = true
                utils.debugChat("[IMPROVE] Обновляю инвентарь перед стартом.")
            end
            return
        end

        if imp.cef.waitInventory then
            if imp.oils.busy then return end
            imp.cef.waitInventory = false
            syncVideoCards()
            if #imp.videoCards == 0 then
                utils.addChat("{F78181}Видеокарты в инвентаре не найдены.")
                self.stop("Нет видеокарт")
                return
            end
            imp.cef.probed = false
            startProbe(false)
            return
        end

        if imp.cef.probing then return end
        if not imp.cef.probed then
            startProbe(false)
            return
        end

        local target = cfg.improveMaxLevel or 2
        local candidate, idxCandidate

        local storageQ = data.improve.storageQueue or {}

        local function isStorageCandidate(v)
            if v.storageUpgrade then return false end
            if storageQ[v.slot] then return true end
            if cfg.improveStorageAfterAll and cfg.improveMenuAll then return true end
            return false
        end

        if cfg.improveMenuAll then
            for idx, v in ipairs(imp.videoCards) do
                if imp.useStorageUpgrade then
                    if isStorageCandidate(v) then
                        candidate = v; idxCandidate = idx; break
                    end
                else
                    if not storageQ[v.slot] and (v.level or 0) < target then
                        candidate = v; idxCandidate = idx; break
                    end
                end
            end
        else
            local hasSelection = false
            for _ in pairs(imp.selectedSlots) do
                hasSelection = true; break
            end
            local hasStorageQ = next(storageQ) ~= nil
            if not hasSelection and not hasStorageQ then
                utils.addChat("{F78181}Выбери хотя бы одну видеокарту в списке.")
                self.stop("Не выбраны видеокарты")
                return
            end

            for idx, v in ipairs(imp.videoCards) do
                local fits
                if imp.useStorageUpgrade then
                    fits = isStorageCandidate(v)
                else
                    fits = imp.selectedSlots[v.slot] and (v.level or 0) < target
                end
                if fits then
                    candidate    = v
                    idxCandidate = idx
                    break
                end
            end
        end

        if not candidate and not imp.useStorageUpgrade then
            local needStoragePass = false
            for _, v in ipairs(imp.videoCards) do
                if isStorageCandidate(v) then
                    needStoragePass = true; break
                end
            end
            if needStoragePass then
                imp.useStorageUpgrade = true
                utils.debugChat("[IMPROVE] Переключение во 2-й проход (storage).")
                return
            end
        end

        if not candidate then
            self.stop(imp.useStorageUpgrade
                and "Все карты улучшены по хранилищу"
                or "Все карты на целевом уровне")
            return
        end

        local slot = tonumber(candidate.slot or 0) or 0
        if slot <= 0 then
            self.stop("Некорректный slot")
            return
        end

        if not imp.useStorageUpgrade and (candidate.level or 0) >= target then
            utils.debugChat(string.format(
                "[IMPROVE] Карта slot=%d уже на целевом уровне %d, пропускаем.",
                slot, candidate.level or 0))
            for i = #imp.videoCards, 1, -1 do
                if imp.videoCards[i].slot == slot then
                    table.remove(imp.videoCards, i)
                    break
                end
            end
            imp.currentIndex = 0
            return
        end

        imp.currentIndex    = idxCandidate
        imp.consumedThisTry = false
        imp.step            = improveStep.CONFIRM
        openCardDialog(slot)
        imp.lastUseAt = os.clock()
    end

    function self.tick()
        if imp.oils.busy and (imp.oils.busyAt or 0) > 0
            and os.clock() - imp.oils.busyAt > 20 then
            utils.debugChat("[IMPROVE] Watchdog: oils.busy висит >20с, сбрасываю.")
            imp.oils.busy   = false
            imp.oils.busyAt = 0
        end
        if imp.isOn and imp.needCheckOils then
            imp.needCheckOils = false
            local needsLevelPass = not cfg.improveUseStorageUpgrade
            if needsLevelPass and not cfg.improveMenuAll then
                needsLevelPass = next(imp.selectedSlots) ~= nil
            end
            if cfg.improveCheckOilsOnStart and needsLevelPass then
                utils.debugChat("[IMPROVE] Проверяю наличие смазки.")
                lua_thread.create(function()
                    self.refreshInventory(false)
                    if not imp.isOn then return end
                    local count, name = self.getOilCount()
                    if count < 2 then
                        utils.addChat(string.format(
                            "{F78181}Смазки нет (%s). Нужно минимум 2.", name))
                        self.stop("Недостаточно смазки при старте")
                    else
                        utils.debugChat(string.format(
                            "[IMPROVE] Инвентарь: %s = %d шт.", name, count))
                        imp.cef.needInventoryRefresh = false
                        imp.step = improveStep.SELECT_CARD
                    end
                end)
            else
                if not needsLevelPass then
                    imp.useStorageUpgrade = true
                end
                imp.cef.needInventoryRefresh = true
                imp.step = improveStep.SELECT_CARD
            end
        end

        if not imp.isOn then return end
        tickWatchdogs()
        if imp.waitOils then return end
        tickSelectCard()
    end

    function self.getStateText()
        return improveStepNames[imp.step] or "?"
    end

    return self
end)()

-- Для заливки и включения карт
local coolantTool = (function()
    local self  = {}
    local state = {
        pending       = false,
        doneForDialog = false,
        outOfSupply   = false,
    }

    local function shouldArm()
        return (cfg.fixCoolantEnabled or cfg.autoEnableCardsOnOpen)
            and not data.isFlashminer
            and not data.working
            and not state.doneForDialog
            and not (data.improve and data.improve.isOn)
    end

    local function refillIfNeeded()
        local needsCoolant = false
        for _, card in ipairs(data.dialogData.videocards) do
            if card.coolant < cfg.useCoolantPercent then
                needsCoolant = true
                break
            end
        end

        local willRefill                = cfg.fixCoolantEnabled and needsCoolant and not state.outOfSupply
        local fillAttempted, fillRanOut = false, false

        if willRefill then
            state.doneForDialog = true
            fillAttempted       = true

            local coolantTask   = buildTaskTable('coolant')
            coolantTask:coolant()
            while data.working do wait(200) end
            fillRanOut = data.stopBySystem == true

            if not data.stopAction then
                for _, card in ipairs(data.dialogData.videocards) do
                    if card.coolant < cfg.useCoolantPercent then
                        card.coolant = 100
                    end
                end
            end
            if fillRanOut then state.outOfSupply = true end
            data.stopAction   = false
            data.stopBySystem = false
            wait(300)
        end
        return fillAttempted
    end

    local function enableIfNeeded(fillAttempted)
        local hasEnableable = false
        for _, card in ipairs(data.dialogData.videocards) do
            if not card.working and card.coolant > 0 then
                hasEnableable = true
                break
            end
        end
        local should = (cfg.autoEnableCardsOnOpen and hasEnableable)
            or (cfg.autoEnableCards and fillAttempted and hasEnableable)
        if should and not data.working then
            local switchTask = buildTaskTable('switchCards')
            switchTask:switchCards(true)
            while data.working do wait(200) end
        end
    end

    function self.handleShowDialog(dialogId, style, title, button1, button2, text, placeholder)
        if shouldArm() then state.pending = true end
        return false
    end

    function self.handleDialogClose(dialogId, button, listitem, input)
        if dialogId == dialogIdTable.videoCardSt
            or dialogId == dialogIdTable.videoCardDialogId
            or dialogId == dialogIdTable.houseFlashMinerDialogId then
            state.outOfSupply   = false
            state.doneForDialog = false
        end
    end

    function self.tick()
        if not (state.pending and not data.working) then return end
        state.pending = false
        wait(200)
        if data.working then return end
        local fillAttempted = refillIfNeeded()
        enableIfNeeded(fillAttempted)
        state.doneForDialog = false
    end

    function self.resetSupplyFlag()
        state.outOfSupply = false
    end

    function self.isOutOfSupply() return state.outOfSupply end

    return self
end)()

-- Для оплаты налогов
local taxTool = (function()
    local self  = {}
    local state = {
        capturedAmount = 0,
    }

    function self.handleShowDialog(dialogId, style, title, button1, button2, text, placeholder)
        if (title or ''):find("Оплата всех налогов")
            and (text or ''):find("нет налогов")
            and data.taskTypeNow == 'autoPayTaxes' then
            sampSendDialogResponse(dialogId, 1, 0, "")
            return true
        end
        return false
    end

    function self.handleServerMessage(color, text)
        if not data.working then return false end
        if (text or ''):find("Вы оплатили все налоги на сумму") then
            local amount_str = text:match("%$([%d%.,%s]+)")
            if amount_str then
                local clean = amount_str:gsub("[^%d]", "")
                if clean ~= "" then state.capturedAmount = tonumber(clean) or 0 end
            end
            return true
        end
        return false
    end

    function self.tickTimer(now)
        if data.working then return end
        if not cfg.cheatModeEnabled then return end
        if not (cfg.autoPayTaxesEnabled and cfg.autoPayTaxesByTimer) then return end
        if (cfg.lastTaxPayTime + cfg.autoPayTaxesInterval * 3600) > now then return end
        runSilentTask('autoPayTaxes')
    end

    function self.runWithCollect()
        if not (cfg.cheatModeEnabled
                and cfg.autoPayTaxesEnabled
                and cfg.autoPayTaxesWithCollect) then
            return
        end
        wait(300)
        while data.working do wait(200) end
        local taxTask = buildTaskTable('autoPayTaxes')
        taxTask:run()
        wait(500)
        while data.working do wait(200) end
    end

    function self.resetCapturedAmount() state.capturedAmount = 0 end

    function self.getCapturedAmount() return state.capturedAmount end

    return self
end)()

-- Для пополнения баланса
local autoTopUpTool = (function()
    local self  = {}
    local state = {
        lastThresholdCheckAt = 0,
    }

    function self.tickTimer(now)
        if data.working then return end
        if not cfg.cheatModeEnabled then return end
        if not cfg.autoTopUpEnabled then return end

        if cfg.autoTopUpByTimer
            and (cfg.lastAutoTopUpTime + cfg.autoTopUpTimerInterval * 3600) <= now then
            runSilentTask('autoTopUp')
            return
        end

        if cfg.autoTopUpByThreshold
            and (now - state.lastThresholdCheckAt) >= 300 then
            state.lastThresholdCheckAt = now
            for _, house in ipairs(data.dialogData.flashminer) do
                if houseFilter.shouldProcess(house) and house.balance < cfg.autoTopUpThreshold then
                    runSilentTask('autoTopUp')
                    return
                end
            end
        end
    end

    function self.runWithCollect()
        if not (cfg.cheatModeEnabled
                and cfg.autoTopUpEnabled
                and cfg.autoTopUpWithCollect) then
            return
        end
        wait(300)
        while data.working do wait(200) end
        if flashminerTool.requestList(5000) then
            local topUpTask = buildTaskTable('autoTopUp')
            topUpTask:run()
            wait(500)
            while data.working do wait(200) end
        end
    end

    return self
end)()

-- Для переодического обновления домов
local autoRefreshTool = (function()
    local self  = {}
    local state = {
        postponedUntil = 0,
    }

    function self.runSilent()
        local result = withSilentFlashminer(function()
            local updateTask = buildTaskTable('updateStatuses')
            updateTask:run()
            wait(300)
            while data.working do wait(200) end
        end)
        cfg.lastAutoRefreshTime = os.time()
        save()
        if result then
            utils.debugChat("[REFRESH] Фоновое обновление статусов завершено.")
        end
        return result
    end

    function self.tickTimer(now)
        if not cfg.autoRefreshEnabled then return end
        if (cfg.lastAutoRefreshTime + cfg.autoRefreshInterval * 60) > now then return end
        if now < state.postponedUntil then return end

        if cfg.refreshPostponeOnDialog
            and sampIsDialogActive()
            and not data.silentWindowOpen then
            state.postponedUntil = now + cfg.refreshPostponeMinutes * 60
            utils.debugChat(string.format(
                "[REFRESH] Диалог открыт — обновление отложено на %d мин.",
                cfg.refreshPostponeMinutes))
        else
            self.runSilent()
        end
    end

    function self.getPostponedUntil() return state.postponedUntil end

    return self
end)()

-- Для автосбора
local collectTool = (function()
    local self = {}

    local triggerState = { reminder = {}, scheduled = {}, smart = {} }

    local function getSmartAggregate()
        local hasData, totalBtc, totalDaily = false, 0, 0
        local now = os.time()
        for houseId, snapshot in pairs(cfg.cardSnapshots) do
            local houseNum = tonumber(houseId)
            if houseNum and not houseFilter.shouldSkip(houseNum) then
                local st = data.houseStatuses[houseNum]
                if st and st.lastCheck > 0 and snapshot.dailyBtcRate and snapshot.dailyBtcRate > 0 then
                    hasData    = true
                    local dBtc = snapshot.dailyBtcRate
                    totalBtc   = totalBtc + (st.earnings and st.earnings.btc or 0)
                        + dBtc * ((now - st.lastCheck) / 86400)
                    totalDaily = totalDaily + dBtc
                end
            end
        end
        return hasData, totalBtc, totalDaily
    end

    -- Триггеры
    local triggers = {
        {
            name = 'reminder',
            kind = 'notify_only',
            enabled = function()
                return cfg.reminderEnabled
                    and not cfg.autoCollectEnabled
                    and not cfg.smartCollectEnabled
                    and data.hasFlashminer ~= false
            end,
            tick = function(state, now)
                local estBTC, hasData = estimateTotalBTC()
                if hasData and estBTC >= cfg.btcThreshold
                    and now - (state.lastShownAt or 0) > cfg.reminderInterval * 60 then
                    state.lastShownAt            = now
                    data.notifyWindow.btcAmount  = estBTC
                    data.notifyWindow.mode       = 'reminder'
                    data.notifyWindow.autoHideAt = now + cfg.notifyShowDuration
                    data.notifyWindow.isPreview  = false
                    data.notifyWindow.show[0]    = true
                end
            end,
        },
        {
            name            = 'scheduled',
            kind            = 'collect',
            enabled         = function()
                return cfg.autoCollectEnabled and cfg.cheatModeEnabled
                    and not (data.improve and data.improve.isOn)
            end,
            getSecondsLeft  = function() return self.getTimeUntil() end,
            getCountdownAt  = function() return self.getNextTime() end,
            fireThrottleSec = function() return self.getInterval() - 60 end,
        },
        {
            name                = 'smart',
            kind                = 'collect',
            enabled             = function()
                return cfg.smartCollectEnabled
                    and not cfg.autoCollectEnabled
                    and not cfg.reminderEnabled
                    and cfg.cheatModeEnabled
                    and not (data.improve and data.improve.isOn)
            end,
            getSecondsLeft      = function()
                local ok, btc, daily = getSmartAggregate()
                if not ok or daily <= 0 then return nil end
                local hoursLeft = (cfg.smartCollectTarget - btc) / (daily / 24)
                return math.floor(hoursLeft * 3600), btc
            end,
            getCountdownAt      = function(secsLeft) return os.time() + secsLeft end,
            fireThrottleSec     = function() return 300 end,
            shouldCancelPending = function(btc)
                return btc and btc < cfg.smartCollectTarget * 0.5
            end,
        },
    }

    -- Запуск сбора по триггеру
    local function collectNow(st, now)
        cfg.lastCollectTime  = now
        st.countdownNotified = false
        st.pendingNotified   = false
        save()
        if cfg.notifyAutoCollectEnabled then
            data.notifyWindow.mode       = 'collecting'
            data.notifyWindow.autoHideAt = 0
            data.notifyWindow.isPreview  = false
            data.notifyWindow.show[0]    = true
        end
        self.runSilent(true)
    end

    -- Тик одного триггера
    local function tickTrigger(trig, now)
        if not trig.enabled() then return end
        local st = triggerState[trig.name]

        if trig.kind == 'notify_only' then
            if not data.working then trig.tick(st, now) end
            return
        end

        local secsLeft, extra = trig.getSecondsLeft()
        if not secsLeft then return end

        if secsLeft > cfg.notifyBeforeSec then st.countdownNotified = false end

        if cfg.notifyAutoCollectEnabled and not cfg.randomDelayEnabled then
            if secsLeft > 0 and secsLeft <= cfg.notifyBeforeSec
                and not st.countdownNotified and not data.pendingCollectLocked then
                st.countdownNotified              = true
                data.notifyWindow.countdownTarget = trig.getCountdownAt(secsLeft)
                data.notifyWindow.mode            = 'countdown'
                data.notifyWindow.autoHideAt      = 0
                data.notifyWindow.isPreview       = false
                data.notifyWindow.show[0]         = true
            end
            if secsLeft <= 0 and data.notifyWindow.mode == 'countdown'
                and not data.pendingCollectLocked then
                data.notifyWindow.mode = 'collecting'
            end
        end

        if secsLeft <= 0 and not data.pendingCollectLocked
            and now - cfg.lastCollectTime > trig.fireThrottleSec() then
            if cfg.refreshPostponeOnDialog and sampIsDialogActive()
                and not data.silentWindowOpen then
                cfg.lastCollectTime = cfg.lastCollectTime + 60
                utils.debugChat(string.format(
                    "[%s] Диалог открыт — автосбор отложен на 1 мин.",
                    trig.name:upper()))
            elseif cfg.randomDelayEnabled then
                local delay               = math.random(cfg.randomDelayMin * 60, cfg.randomDelayMax * 60)
                data.pendingCollectAt     = now + delay
                data.pendingCollectLocked = true
                st.pendingNotified        = false
                utils.debugChat(string.format("[%s] Рандомная задержка: %d сек.",
                    trig.name:upper(), delay))
            elseif not data.working then
                collectNow(st, now)
            end
        end

        if data.pendingCollectLocked then
            if trig.shouldCancelPending and trig.shouldCancelPending(extra) then
                data.pendingCollectLocked = false
                st.pendingNotified        = false
                utils.debugChat(string.format("[%s] Условие сброшено, отмена задержки.",
                    trig.name:upper()))
            elseif now >= data.pendingCollectAt and not data.working then
                data.pendingCollectLocked = false
                collectNow(st, now)
            elseif cfg.notifyAutoCollectEnabled then
                local pendLeft = data.pendingCollectAt - now
                if pendLeft > 0 and pendLeft <= cfg.notifyBeforeSec and not st.pendingNotified then
                    st.pendingNotified                = true
                    data.notifyWindow.countdownTarget = data.pendingCollectAt
                    data.notifyWindow.mode            = 'countdown'
                    data.notifyWindow.autoHideAt      = 0
                    data.notifyWindow.isPreview       = false
                    data.notifyWindow.show[0]         = true
                end
            end
        end
    end

    function self.runSilent(doUpdateStatuses)
        if data.hasFlashminer == false then
            return false
        end
        local restoreHouseControl  = data.showHouseControlWindow[0] == true
        data.silentWindowOpen      = true
        data.showLogsWindow[0]     = false
        data.showSettingsWindow[0] = false
        data.dialogData.flashminer = {}
        sampSendChat("/flashminer")
        wait(200)
        local t = 0
        while #data.dialogData.flashminer == 0 and t < 5000 do
            wait(200); t = t + 200
            if data.collectCancelled then
                data.collectCancelled = false
                taskState.setSilent(false)
                return false
            end
        end
        if #data.dialogData.flashminer == 0 then
            data.silentWindowOpen     = false
            data.notifyWindow.show[0] = false
            return false
        end
        if doUpdateStatuses then
            local needsUpdate = true
            local now2 = os.time()
            for _, house in ipairs(data.dialogData.flashminer) do
                local status = data.houseStatuses[house.house_number]
                if status and status.lastCheck > 0 and (now2 - status.lastCheck) < 300 then
                    needsUpdate = false; break
                end
            end
            if needsUpdate then
                local updateTask = buildTaskTable('updateStatuses')
                updateTask:run()
                wait(300)
                while data.working do
                    wait(200)
                    if data.collectCancelled then
                        data.collectCancelled = false
                        taskState.setSilent(false)
                        data.stopAction = true
                        return false
                    end
                end
            end
        end
        wait(300)
        while data.working do
            wait(200)
            if data.collectCancelled then
                data.collectCancelled = false
                taskState.setSilent(false)
                data.stopAction = true
                return false
            end
        end
        local task = buildTaskTable('collectFromAllHouses')
        task:run()
        wait(500)
        while data.working do
            wait(200)
            if data.collectCancelled then
                data.collectCancelled = false
                taskState.setSilent(false)
                data.stopAction = true
                return false
            end
        end
        if cfg.autoEnableCardsOnCollect then
            wait(300)
            if flashminerTool.requestList(5000) then
                local switchTask = buildTaskTable('massSwitchCards')
                switchTask:run(true)
                wait(500)
                while data.working do wait(200) end
            end
        end

        taxTool.runWithCollect()
        autoTopUpTool.runWithCollect()

        fixI()
        data.currentCollectHouse       = ""
        data.silentWindowOpen          = false
        data.showHouseControlWindow[0] = restoreHouseControl
        data.notifyWindow.show[0]      = false
        return true
    end

    function self.tickTriggers(now)
        for _, trig in ipairs(triggers) do
            tickTrigger(trig, now)
        end
    end

    function self.getInterval()
        local times = math.max(1, math.min(cfg.collectTimesPerDay, 24))
        return math.floor(86400 / times)
    end

    function self.getNextTime()
        if cfg.lastCollectTime == 0 then return os.time() end
        return cfg.lastCollectTime + self.getInterval()
    end

    function self.getTimeUntil()
        return self.getNextTime() - os.time()
    end

    function self.cancelPending()
        data.pendingCollectLocked = false
        data.pendingCollectAt     = 0
        data.collectCancelled     = true
        data.stopAction           = true
        for _, st in pairs(triggerState) do
            st.countdownNotified = false
            st.pendingNotified   = false
        end
        cfg.lastCollectTime = os.time()
        save()
    end

    function self.resetPendingDelay()
        data.pendingCollectLocked = false
        data.pendingCollectAt     = 0
        for _, st in pairs(triggerState) do
            st.countdownNotified = false
            st.pendingNotified   = false
        end
    end

    return self
end)()

local houseStatusHelper = {
    colors = {
        bad = imgui.ImVec4(1, 0.2, 0.2, 1),
        warning = imgui.ImVec4(1, 0.88, 0.2, 1),
        good = imgui.ImVec4(0.3, 1, 0.3, 1),
        unknown = imgui.ImVec4(0.5, 0.5, 0.5, 1),
    },

    icons = {
        bad = fa.CIRCLE_EXCLAMATION,
        warning = fa.TRIANGLE_EXCLAMATION,
        good = fa.CIRCLE_CHECK,
        unknown = fa.CIRCLE_QUESTION,
    },

    colorStrings = {
        bad = "{FF3333}",
        warning = "{FFE133}",
        good = "{4DE94C}",
        unknown = "{808080}",
    },

    getColor = function(self, statusType)
        return self.colors[statusType] or self.colors.unknown
    end,

    getIcon = function(self, statusType)
        return self.icons[statusType] or self.icons.unknown
    end,

    getColorString = function(self, statusType)
        return self.colorStrings[statusType] or self.colorStrings.unknown
    end,

    determineStatus = function(self, house, status, isExcluded, isNoBasement)
        if isNoBasement then
            return "no_basement"
        end

        if isExcluded then
            return "good"
        end

        if not (status and status.lastCheck > 0) then
            return "unknown"
        end

        return status.status or "unknown"
    end,

    buildTooltip = function(self, status, house, isNoBasement)
        local lines = {}
        if isNoBasement then
            table.insert(lines, 1, "В доме нет подвала")
            table.insert(lines, 2, "--------------------")
        elseif not (status and status.lastCheck > 0) then
            lines = { "Статус неизвестен (дом не проверялся)" }
        elseif status.issues and #status.issues > 0 then
            for _, issue in ipairs(status.issues) do
                table.insert(lines, "• " .. issue)
            end
        else
            lines = { "Проблем не обнаружено" }
        end

        if house.tax and house.tax > 50000 then
            table.insert(lines, string.format("Высокий налог: $%s", utils.formatNumber(house.tax)))
        end

        return table.concat(lines, "\n")
    end
}

function formatEarnings(btc, asc, includeAsc, separator)
    separator = separator or " {FFFFFF}| "
    local parts = {}
    if btc and btc > 0 then
        table.insert(parts, string.format("{BEF781}%d BTC", btc))
    end
    if asc and asc > 0 and includeAsc then
        table.insert(parts, string.format("{FFA500}%d ASC", asc))
    end
    if #parts == 0 then return "{808080}0", false end
    return table.concat(parts, separator), true
end

function isArizonaServer()
    local serverName = sampGetCurrentServerName()
    local isMatch = serverName:match("^Arizona [^|]+ | ([^|]+) |") or serverName:match("^Arizona [^|]+ | ([^|]+)$")
    return isMatch ~= nil
end

function estimateTotalBTC()
    local total = 0
    local hasAnyData = false

    for _, house in ipairs(data.dialogData.flashminer) do
        if houseFilter.shouldSkip(house.house_number) then goto skip_house end

        local status = data.houseStatuses[house.house_number]
        if not (status and status.lastCheck > 0) then goto skip_house end

        hasAnyData = true

        local knownBtc = (status.earnings and status.earnings.btc) or 0

        local hoursSinceCheck = (os.time() - status.lastCheck) / 3600

        local dailyBtc, _ = houseFilter.getDailyIncome(house.house_number)

        local estimatedAccumulated = (dailyBtc / 24) * hoursSinceCheck

        total = total + knownBtc + estimatedAccumulated

        ::skip_house::
    end

    return total, hasAnyData
end

function formatTimeLeft(seconds)
    if seconds <= 0 then return u8 "уже пора!" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if seconds <= 60 then
        return string.format("%dс", math.floor(seconds))
    elseif h > 0 then
        return string.format("%dч %dм", h, m)
    else
        return string.format("%dм %dс", m, s)
    end
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

function isProperlyConnected()
    if not isSampAvailable() then return false end
    local name = sampGetCurrentServerName()
    if not name or name == '' or name == 'SA-MP' then return false end
    if not sampIsLocalPlayerSpawned() then return false end
    return true
end

local function updateConnectionState()
    local nowConnected = isProperlyConnected()
    local wasConnected = data.connectionState.connected
    data.connectionState.lastCheck = os.time()

    if nowConnected == wasConnected then return end

    if nowConnected then
        data.connectionState.connected = true
        if cfg.waitForConnection and data.connectionState.wasDisconnected then
            data.connectionState.readyAfterConnect =
                os.time() + cfg.delayAfterConnectMin * 60
            utils.debugChat(string.format(
                "[CONNECT] Подключение восстановлено. Отложено на %d мин.",
                cfg.delayAfterConnectMin))
        end
    else
        data.connectionState.connected = false
        data.connectionState.wasDisconnected = true
        utils.debugChat("[CONNECT] Подключение потеряно. Приостановлено.")
    end
end

function runTaskAndReopenDialog(taskFunction, ...)
    taskFunction(...)
    lua_thread.create(function()
        while data.working do wait(50) end
        wait(200)
        if sampIsDialogActive() then sampCloseCurrentDialogWithButton(0) end
        if data.hasFlashminer == false then return end
        sampSendChat("/flashminer")
    end)
end

function main()
    repeat wait(0) until isSampAvailable() and isSampfuncsLoaded()
    while not isSampLoaded() do wait(0) end
    while not sampGetCurrentServerName():find('Arizona') and not sampGetCurrentServerName():find('Rodina') do wait(0) end
    data.isRodina = not isArizonaServer()
    dialogIdTable = data.isRodina and dialogIdTable.rodina or dialogIdTable.arizona

    utils.addChat('Загружен. Команда: {ffc0cb}/mnt{ffffff}.')

    if cfg.checkForUpdates then
        checkForUpdates()
    end

    sampRegisterChatCommand('mnt', function()
        cfg.active = not cfg.active
        utils.addChat(cfg.active and "Скрипт {99ff99}включен." or "Скрипт {F78181}отключен.")
        save()
    end)
    sampRegisterChatCommand('mntd', function()
        cfg.debug = not cfg.debug
        utils.addChat(cfg.debug and "Отладка {99ff99}включена." or "Отладка {F78181}отключена.")
        save()
    end)

    sampRegisterChatCommand('fls', function()
        if data.hasFlashminer == false then
            utils.addChat("{F78181}У вас нет флешки майнера.")
            return
        end
        if data.working then
            utils.addChat("{FFE133}Дождитесь завершения текущей задачи.")
            return
        end

        if data.showHouseControlWindow[0] then
            data.showHouseControlWindow[0] = false
            return
        end

        lua_thread.create(function()
            sampSendChat("/flashminer")
        end)
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

    local escHandlers = {
        {
            cond = function() return data.showImproveWindow[0] end,
            act = function() data.showImproveWindow[0] = false end
        },
        {
            cond = function() return updateState.showPopup[0] end,
            act = function()
                updateState.showPopup[0] = false
                updateState.declined = true
            end
        },
        {
            cond = function() return data.showSettingsWindow[0] and data.showLogsWindow[0] end,
            act = function()
                data.showSettingsWindow[0] = false; data.showLogsWindow[0] = false
            end
        },
        {
            cond = function() return data.showSettingsWindow[0] end,
            act = function() data.showSettingsWindow[0] = false end
        },
        {
            cond = function() return data.showLogsWindow[0] end,
            act = function() data.showLogsWindow[0] = false end
        },

        {
            cond = function()
                return data.showHouseControlWindow[0]
                    and not data.working
                    and data.lastWindowState.houseControl
            end,
            act = function()
                sampCloseCurrentDialogWithButton(0)
                data.showHouseControlWindow[0] = false
                fixI()
            end
        },

    }
    addEventHandler('onWindowMessage', function(msg, wparam, lparam)
        if sampIsChatInputActive() then return end
        if msg ~= wm.WM_KEYDOWN then return end

        if wparam == 27 then
            for _, h in ipairs(escHandlers) do
                if h.cond() then
                    consumeWindowMessage(true, false)
                    h.act()
                    return
                end
            end
        end

        if data.main[0] and data.isFlashminer and not data.working then
            local direction = nil

            if wparam == 37 then -- Стрелка ВЛЕВО
                consumeWindowMessage(true, false)
                direction = -1
            elseif wparam == 39 then -- Стрелка ВПРАВО
                consumeWindowMessage(true, false)
                direction = 1
            end

            if direction then
                flashminerTool.navigate(direction)
                return
            end
        end
        if #data.dialogData.flashminer > 0 and data.showHouseControlWindow[0] then
            local columns = 2
            local direction = nil

            if wparam == 40 then -- Стрелка ВНИЗ
                consumeWindowMessage(true, false)
                direction = 'down'
            elseif wparam == 38 then -- Стрелка ВВЕРХ
                consumeWindowMessage(true, false)
                direction = 'up'
            elseif wparam == 37 then -- Стрелка ВЛЕВО
                consumeWindowMessage(true, false)
                direction = 'left'
            elseif wparam == 39 then -- Стрелка ВПРАВО
                consumeWindowMessage(true, false)
                direction = 'right'
            end

            if direction then
                local filteredHouses = data.filteredHouses or data.dialogData.flashminer
                local totalFiltered = #filteredHouses
                local currentIndex = nil

                if data.selectedHouseIndex then
                    local selectedHouse = data.dialogData.flashminer[data.selectedHouseIndex]
                    if selectedHouse then
                        for i, house in ipairs(filteredHouses) do
                            if house.house_number == selectedHouse.house_number then
                                currentIndex = i
                                break
                            end
                        end
                    end
                end

                if not currentIndex then currentIndex = 1 end

                local newIndex = currentIndex

                if direction == 'down' then
                    -- Вниз = +2
                    newIndex = currentIndex + columns
                    if newIndex > totalFiltered then
                        newIndex = currentIndex
                    end
                elseif direction == 'up' then
                    -- Вверх = -2
                    newIndex = currentIndex - columns
                    if newIndex < 1 then
                        newIndex = currentIndex
                    end
                elseif direction == 'left' then
                    -- Влево = -1
                    newIndex = currentIndex - 1
                    if newIndex < 1 then
                        newIndex = totalFiltered
                    end
                elseif direction == 'right' then
                    -- Вправо = +1
                    newIndex = currentIndex + 1
                    if newIndex > totalFiltered then
                        newIndex = 1
                    end
                end

                if newIndex ~= currentIndex then
                    local nextHouse = filteredHouses[newIndex]
                    if nextHouse then
                        for origIdx, origHouse in ipairs(data.dialogData.flashminer) do
                            if origHouse.house_number == nextHouse.house_number then
                                data.selectedHouseIndex = origIdx
                                data.lastSelectedHouse = nextHouse.house_number
                                data.scrollToSelection = true
                                break
                            end
                        end
                    end
                end
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
    end)


    -- для автозаливки и переключения кард
    lua_thread.create(function()
        while true do
            wait(300)
            coolantTool.tick()
        end
    end)

    -- для подсчёта тиков заточки
    lua_thread.create(function()
        while true do
            wait(10)
            improveTool.tick()
        end
    end)

    -- Для окна подсказки
    lua_thread.create(function()
        while true do
            wait(50)
            if sampIsChatInputActive() or sampIsDialogActive() then goto continue end
            if not wasKeyPressed(0x12) then goto continue end -- VK_MENU = Alt

            local px, py, pz = getCharCoordinates(PLAYER_PED)
            local dx = px - IMPROVE_SPOT.x
            local dy = py - IMPROVE_SPOT.y
            local dz = pz - IMPROVE_SPOT.z
            local r2 = IMPROVE_HINT_RADIUS * IMPROVE_HINT_RADIUS
            if dx * dx + dy * dy + dz * dz <= r2 then
                data.showImproveWindow[0] = not data.showImproveWindow[0]
            end
            ::continue::
        end
    end)

    -- для автооплаты налог и пополнения баланса
    lua_thread.create(function()
        while true do
            wait(1000)
            if not cfg.active then goto continue_timer end

            updateConnectionState()
            if not taskState.isAutomationAllowed() then goto continue_timer end

            if data.hasFlashminer == false then goto continue_timer end

            local now = os.time()
            collectTool.tickTriggers(now)

            if not cfg.cheatModeEnabled or data.working then goto continue_timer end

            taxTool.tickTimer(now)

            autoTopUpTool.tickTimer(now)

            autoRefreshTool.tickTimer(now)

            ::continue_timer::
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

addEventHandler('onReceivePacket', function(id, bs)
    if not cfg.active then return end

    if cfg.lastHouseListHash == "" and id == 220 then
        raknetBitStreamIgnoreBits(bs, 8)
        if raknetBitStreamReadInt8(bs) == 17 then
            raknetBitStreamIgnoreBits(bs, 32)
            local length = raknetBitStreamReadInt16(bs)
            local encoded = raknetBitStreamReadInt8(bs)
            local str = (encoded ~= 0) and raknetBitStreamDecodeString(bs, length + encoded) or
                raknetBitStreamReadString(bs, length)

            if str:find("event%.property%.list%.pushItems") then
                local raw = str:match("%[%[(.-)%]%]")
                if raw then
                    local houseData = decodeJson('[' .. raw .. ']')

                    if houseData and houseData[1] then
                        local house = houseData[1]
                        if house.status == "rentedOut" then
                            local houseId = tostring(house.id)
                            cfg.excludedHouses[houseId] = true
                            utils.debugChat("Дом №" .. houseId .. " добавлен в исключения (аренда)")
                        end
                    end
                end
            end
        end
    end
end)

local dialogChecker = {
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
    },
    shouldHide = function(self, title, text)
        for _, pattern in ipairs(self.titles) do
            if title:find(pattern) then return true end
        end
        for _, pattern in ipairs(self.texts) do
            if text:find(pattern) then return true end
        end
        return false
    end
}

local massActionTypes = {
    collectFromAllHouses = true,
    massSwitchCards      = true,
    fixAllProblems       = true,
    scanBasements        = true,
    updateStatuses       = true,
    autoPayTaxes         = true,
    autoTopUp            = true,
}

function sampev.onShowDialog(dialogId, style, title, button1, button2, text, placeholder)
    if not cfg.active then return end

    if title:find("Выбор дома") and text:find("циклов %(") then
        data.isFlashminer = true
    end

    if improveTool.handleChooseDialog(dialogId, title, text) then
        return false
    end
    if improveTool.handleConfirmDialog(dialogId, title) then
        return false
    end
    if taxTool.handleShowDialog(dialogId, style, title, button1, button2, text, placeholder) then
        return false
    end

    coolantTool.handleShowDialog(dialogId, style, title, button1, button2, text, placeholder)

    if improveTool.handleOilsDialog(dialogId, title, text) then
        return false
    end

    if title:find("Телефоны") and text:find("Мобильное устройство") then
        sampSendDialogResponse(dialogId, 1, 0, "")
        return false
    end
    if title:find("Выберите полку") then
        local currentIndex = 0
        for line in text:gmatch("[^\r\n]+") do
            if line:find("Свободна") then
                sampSendDialogResponse(dialogId, 1, currentIndex, "")
                return false
            end
            currentIndex = currentIndex + 1
        end
        utils.addChat("{F78181}Нет свободных слотов на полке!")
        return false
    end
    if data.fix and title:find("Игровое меню") then
        sampSendDialogResponse(dialogId, 0, 0, "")
        return false
    end

    taskState.refreshSuppressDialogs()
    local isMassAction = data.suppressDialogs and massActionTypes[data.taskTypeNow] and not cfg.useDialogMode == true
    if title:find("Выбор дома") and not text:find("домов для") then
        if text:match("циклов %(") then
            data.hasFlashminer = true
            data.isFlashminer = true
            data.dFlashminerId = dialogId
            flashminerTool.parseDialogText(text)

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
            if isMassAction then
                return false
            end

            local wasWindowAlreadyVisible = data.showHouseControlWindow[0]
            if not data.silentWindowOpen then
                data.showHouseControlWindow[0] = true
            end
            if not data.silentWindowOpen and updateState.hasUpdate and not updateState.declined then
                updateState.showPopup[0] = true
            end
            if not wasWindowAlreadyVisible then
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
            end

            local houseNumbers = {}
            for _, h in ipairs(data.dialogData.flashminer) do
                table.insert(houseNumbers, tostring(h.house_number))
            end
            table.sort(houseNumbers)
            local currentHash = table.concat(houseNumbers, ",")

            if not data.silentWindowOpen and not data.working and cfg.lastHouseListHash ~= currentHash then
                local newHouses = {}
                for _, h in ipairs(data.dialogData.flashminer) do
                    local houseNum = tostring(h.house_number)
                    if not cfg.basementScanned[houseNum] and not cfg.excludedHouses[houseNum] then
                        table.insert(newHouses, h)
                    end
                end

                local currentHouses = {}
                for _, num in ipairs(houseNumbers) do
                    currentHouses[num] = true
                end

                for houseNum in pairs(cfg.housesWithoutBasement) do
                    if not currentHouses[houseNum] then
                        cfg.housesWithoutBasement[houseNum] = nil
                    end
                end
                for houseNum in pairs(cfg.basementScanned) do
                    if not currentHouses[houseNum] then
                        cfg.basementScanned[houseNum] = nil
                    end
                end

                cfg.lastHouseListHash = currentHash
                save()

                if #newHouses > 0 then
                    local task = buildTaskTable('scanBasements')
                    runTaskAndReopenDialog(function() task:run(newHouses) end)
                    data.initialScanCompleted = true
                end
            elseif not data.silentWindowOpen and not data.initialScanCompleted and not data.working then
                cfg.lastHouseListHash = currentHash
                save()
                local task = buildTaskTable('updateStatuses')
                runTaskAndReopenDialog(function() task:run() end)
                data.initialScanCompleted = true
            end

            return false
        end
    end

    if title:find("^{......}Выберите видеокарту") or title:find("^Полка №%d+") or text:find("Баланс Bitcoin") or text:find('Обзор всех видеокарт') then
        data.flashminerSwitchId.direction = 0
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
                local hasBtc = line:find("BTC") ~= nil
                local hasAsc = line:find("ASC") ~= nil
                local card = {
                    index = listbox_index,
                    working = line:find("{......}Работает") and true or false,
                    btc_full = tonumber(line:match("([%d%.]+) BTC")) or 0,
                    asc_full = tonumber(line:match("([%d%.]+) ASC")) or 0,
                    btc = tonumber(select(1, line:match("(%d+)%.%d+ BTC"))) or 0,
                    asc = tonumber(select(1, line:match("(%d+)%.%d+ ASC"))) or 0,
                    coolant = tonumber(line:match("(%d+%.%d+)%%?%s*$")) or 0,
                    fluidType = hasBtc and 1 or (hasAsc and 2 or 0),
                    card_type = (hasBtc and hasAsc) and "ASIC" or (hasBtc and "BTC" or "ASC"),
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

        if houseNum and not cfg.useDialogMode and not cfg.excludedHouses[tostring(houseNum)] then
            local currentHouseData = nil
            for _, h in ipairs(data.dialogData.flashminer) do
                if h.house_number == tonumber(houseNum) then
                    currentHouseData = h
                    break
                end
            end
            lua_thread.create(function()
                updateHouseStatus(tonumber(houseNum), currentHouseData)
            end)
        end

        if (not data.initialScanCompleted and not cfg.useDialogMode and dialogId ~= dialogIdTable.videoCardSt) or
            isMassAction then
            return false
        end
    end

    if isMassAction then
        if dialogId == dialogIdTable.phoneBankMenuId or
            dialogId == dialogIdTable.topUpBalanceDialogId or
            dialogId == dialogIdTable.payAllTaxesDialogId then
            return false
        end

        if dialogId == dialogIdTable.videoCardDialogId or
            dialogId == dialogIdTable.videoCardAcceptDialogId or
            dialogId == dialogIdTable.coolantDialogId or
            dialogId == dialogIdTable.videoCardSt then
            return false
        end
    end

    if data.suppressDialogs and dialogChecker:shouldHide(title, text) then
        return false
    end
end

function sampev.onDialogClose(dialogId, button, listitem, input)
    if dialogId == data.dFlashminerId then
        data.showHouseControlWindow[0] = false
    end
    coolantTool.handleDialogClose(dialogId, button, listitem, input)
end

function sampev.onServerMessage(color, text)
    if not cfg.active then return end

    improveTool.handleServerMessage(text)
    if taxTool.handleServerMessage(color, text) then
        return false
    end

    if text:find("должны находиться в подвале возле одной из специальных стоек") then
        if data.improve.isOn then
            utils.addChat("{F78181}Подойдите к стойке в подвале!")
            improveTool.stop("Неподходящее место заточки")
        end
        return false
    end
    if text:find("У вас нет флешки майнера") then
        data.stopAction = true
        data.hasFlashminer = false
        utils.addChat("У вас нет флешки майнера!")
        return false
    end
    if text:find('data_center_kwt') then
        return false
    end
    if text:find("Добро пожаловать в город Vice City!") then
        data.isViceCity = true
        return
    end
    if text:find("Добро пожаловать") and not text:find("Vice City") then
        data.isViceCity = false
        return
    end
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
    elseif text:find("Выводить прибыль можно только целыми частями") then
        return false
    elseif text:find("Выберите дом с майнинг фермой") then
        data.hasFlashminer = true
        return false
    elseif text:find("Не забудьте запустить видеокарту") then
        return false
    elseif text:find("охлаждающей жидкости в видеокарту, состояние системы охлаждения восстановлено") then
        return false
    elseif data.working then
        if text:find("недостаточно денежных") then
            utils.addChat("У вас недостаточно средств!")
            data.stopAction = true
            return false
        elseif text:find("нет охлаждающей жидкости") then
            if data.taskTypeNow == 'coolant' and not data.stopAction then
                data.stopAction = true
                data.stopBySystem = true
                utils.addChat("{F78181}Охлаждающая жидкость закончилась!")
            end
            return false
        elseif text:find("необходимо восстановить состояние системы охлаждения") then
            data.cardSwitchFailed = (data.cardSwitchFailed or 0) + 1
            return false
        elseif text:find("В этом доме нет подвала") or text:find("Жильцы дома не могут совершать") then
            data.houseHasNoBasement = true
            return false
        elseif text:find("дом в котором хотите пополнить счёт") then
            return false
        elseif text:find("Вы успешно пополнили счёт дома за") then
            return false
        end
    else
        if text:find("В этом доме нет подвала") or text:find("Жильцы дома не могут совершать") then
            if data.flashminerSwitchId.direction ~= 0 then
                sampSendChat("/flashminer")
                return false
            end
        end
    end

    if text:find("Вы успешно арендовали комнату в доме №(%d+)") then
        local house_id = text:match("доме №(%d+)")
        if house_id then
            cfg.excludedHouses[tostring(house_id)] = true
            save()
            utils.addChat("Дом №" .. house_id .. " добавлен в исключения (Аренда).")
        end
    end
end

function sampev.onSendDialogResponse(dialogId, button, listitem, input)
    if dialogId == data.dFlashminerId and button == 1 and cfg.useDialogMode then
        local houseCount = #data.dialogData.flashminer
        if listitem == houseCount + 1 then
            local task = buildTaskTable('massSwitchCards')
            task:run(true)
            return false
        elseif listitem == houseCount + 2 then
            local task = buildTaskTable('collectFromAllHouses')
            task:run()
            return false
        elseif listitem == houseCount + 3 then
            local task = buildTaskTable('massSwitchCards')
            task:run(false)
            return false
        end
    end

    if dialogId == data.dFlashminerId then
        data.showHouseControlWindow[0] = false
    end
    return true
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
    status.coolantsNeeded = 0

    local cardsOff = 0
    local cardsLowCoolant = 0
    local totalCards = #data.dialogData.videocards
    local isExcluded = cfg.excludedHouses[tostring(houseNumber)] or false
    local houseId = tostring(houseNumber)

    if not cfg.cardSnapshots[houseId] then
        cfg.cardSnapshots[houseId] = { slots = {}, time = 0 }
    end
    local snapshot = cfg.cardSnapshots[houseId]
    if not snapshot.slots then snapshot.slots = {} end

    local timeDiffMinutes = 0
    if snapshot.time and snapshot.time > 0 then
        timeDiffMinutes = (os.time() - snapshot.time) / 60
    end

    local MIN_INTERVAL = 10

    if totalCards > 0 then
        for _, card in ipairs(data.dialogData.videocards) do
            if not card.working then
                cardsOff = cardsOff + 1
            end

            local cardNeeded = 0
            if card.coolant < cfg.useCoolantPercent then
                local effectiveSuper = cfg.useSuperCoolant or data.isViceCity
                if effectiveSuper then
                    cardNeeded = 1
                elseif cfg.economyMode then
                    if card.coolant < 70 then
                        cardNeeded = (card.coolant < 20) and 2 or 1
                    end
                else
                    if card.coolant < 100 then
                        cardNeeded = (card.coolant < 50) and 2 or 1
                    end
                end
            end
            status.coolantsNeeded = status.coolantsNeeded + cardNeeded

            if card.coolant < cfg.useCoolantPercent then cardsLowCoolant = cardsLowCoolant + 1 end
            if card.coolant < status.minCoolant then status.minCoolant = card.coolant end

            if card.level and card.level > 0 then
                if not status.cardLevels[card.level] then
                    status.cardLevels[card.level] = {
                        total = 0,
                        working = 0,
                        btc = { total = 0, working = 0 },
                        asc = { total = 0, working = 0 }
                    }
                end

                status.cardLevels[card.level].total = status.cardLevels[card.level].total + 1
                if card.working then
                    status.cardLevels[card.level].working = status.cardLevels[card.level].working + 1
                end

                if card.card_type == "ASIC" then
                    status.cardLevels[card.level]["btc"].total = status.cardLevels[card.level]["btc"].total + 1
                    status.cardLevels[card.level]["asc"].total = status.cardLevels[card.level]["asc"].total + 1
                    if card.working then
                        status.cardLevels[card.level]["btc"].working = status.cardLevels[card.level]["btc"].working + 1
                        status.cardLevels[card.level]["asc"].working = status.cardLevels[card.level]["asc"].working + 1
                    end
                else
                    local currency = (card.fluidType == 1) and "btc" or "asc"
                    status.cardLevels[card.level][currency].total = status.cardLevels[card.level][currency].total + 1
                    if card.working then
                        status.cardLevels[card.level][currency].working = status.cardLevels[card.level][currency]
                            .working + 1
                    end
                end
            end

            status.earnings.btc = status.earnings.btc + card.btc
            status.earnings.asc = status.earnings.asc + card.asc
        end

        if timeDiffMinutes >= MIN_INTERVAL or snapshot.time == 0 then
            snapshot.time = os.time()
            local t = os.clock()
            if t - _snapshotSaveT > 5.0 then
                _snapshotSaveT = t
                save()
            end
        end

        local currentBtcTotal = 0
        for _, card in ipairs(data.dialogData.videocards) do
            if card.fluidType == 1 or card.card_type == "ASIC" then
                currentBtcTotal = currentBtcTotal + (card.btc_full or card.btc or 0)
            end
        end

        if not snapshot.incomeObs then snapshot.incomeObs = {} end

        if snapshot.time > 0 and timeDiffMinutes >= MIN_INTERVAL then
            local prevBtcTotal = snapshot.prevBtcTotal or 0
            local diff = currentBtcTotal - prevBtcTotal

            if diff > 0 then
                local dailyRate = (diff / timeDiffMinutes) * 60 * 24

                table.insert(snapshot.incomeObs, { rate = dailyRate, minutes = timeDiffMinutes, timestamp = os.time() })
                while #snapshot.incomeObs > 15 do
                    table.remove(snapshot.incomeObs, 1)
                end

                if #snapshot.incomeObs >= 1 then
                    local weightedSum = 0
                    local totalWeight = 0
                    for _, obs in ipairs(snapshot.incomeObs) do
                        local weight = obs.minutes or 1
                        weightedSum  = weightedSum + obs.rate * weight
                        totalWeight  = totalWeight + weight
                    end
                    snapshot.dailyBtcRate = totalWeight > 0 and (weightedSum / totalWeight) or 0
                    utils.debugChat(string.format(
                        "[INCOME] Дом №%d: %.2f BTC/день (наблюд: %d, diff: %.3f за %.1f мин)",
                        houseNumber, snapshot.dailyBtcRate, #snapshot.incomeObs, diff, timeDiffMinutes
                    ))
                end
            elseif diff == 0 then
                utils.debugChat(string.format(
                    "[INCOME] Дом №%d: баланс не изменился (%.3f), пропускаем",
                    houseNumber, currentBtcTotal
                ))
            end
        end

        snapshot.prevBtcTotal = currentBtcTotal
    else
        status.minCoolant = 0
    end

    if not isExcluded then
        if cardsOff > 0 then
            table.insert(status.issues, string.format("Выключено видеокарт: %d/%d", cardsOff, totalCards))
        end
        if cardsLowCoolant > 0 then
            table.insert(status.issues, string.format("Мало жидкости: %d/%d", cardsLowCoolant, totalCards))
        end

        local balanceThreshold = cfg.minBalanceWarning or 5000000
        if houseData and houseData.balance < balanceThreshold then
            table.insert(status.issues, string.format("Низкий баланс: $%s", utils.formatNumber(houseData.balance)))
        end

        if houseData and houseData.tax then
            if houseData.tax >= 90000 then
                table.insert(status.issues, string.format("Высокий налог: $%s", utils.formatNumber(houseData.tax)))
            elseif houseData.tax >= 50000 then
                table.insert(status.issues, string.format("Повышенный налог: $%s", utils.formatNumber(houseData.tax)))
            end
        end
    end

    if isExcluded then
        status.status = "good"
    else
        local hasBadIssue = cardsOff > 0 or cardsLowCoolant > 0 or
            (houseData and houseData.tax and houseData.tax >= 90000)
        local hasWarningIssue = houseData and
            (houseData.balance < (cfg.minBalanceWarning or 5000000) or (houseData.tax and houseData.tax >= 50000))
        if hasBadIssue then
            status.status = "bad"
        elseif hasWarningIssue then
            status.status = "warning"
        else
            status.status = "good"
        end
    end
end

function resetIncomeRates()
    for _, snap in pairs(cfg.cardSnapshots) do
        snap.incomeObs = {}
        snap.dailyBtcRate = nil
        snap.prevBtcTotal = nil
    end
    save()
    utils.addChat("Ставки дохода сброшены. Статистика накопится после 2+ визитов в каждый дом.")
end

function buildTaskTable(taskType, ...)
    local function visitHouseCards(sendResponse, house, onCards)
        progressTracker.setHouseTotal(0)
        data.dialogData.videocards = {}
        dialogActions.selectHouse(sendResponse, house.index - 1)
        local t = 0
        while #data.dialogData.videocards == 0 and t < 3000 do
            wait(50); t = t + 50
        end
        wait(100)
        if #data.dialogData.videocards == 0 then wait(200) end
        onCards(data.dialogData.videocards)
        wait(100)
        dialogActions.closeDialog(sendResponse)
        progressTracker.increment()
    end

    local function collectCardsFromHouse(sendResponse)
        local cardsToCollect = {}
        for _, card in ipairs(data.dialogData.videocards) do
            if card.btc >= 1 or card.asc >= 1 then
                table.insert(cardsToCollect, card)
            end
        end

        if #cardsToCollect == 0 then return 0, 0 end

        local btcCollected, ascCollected = 0, 0
        for idx, card in ipairs(cardsToCollect) do
            progressTracker.increment(true)

            dialogActions.selectCard(sendResponse, card.index - 1)

            if card.btc >= 1 then
                dialogActions.withdrawBTC(sendResponse)
                btcCollected = btcCollected + card.btc
            end

            if card.asc >= 1 and (card.card_type == "ASC" or card.card_type == "ASIC") then
                dialogActions.withdrawASC(sendResponse)
                ascCollected = ascCollected + card.asc
            end

            if data.isRodina then
                utils.pressButton(1024)
                wait(1000)
                while not (sampIsDialogActive() and sampGetCurrentDialogId() == data.dFlashminerId) do wait(50) end
            else
                dialogActions.closeDialog(sendResponse, dialogIdTable.videoCardDialogId)
            end
        end

        return btcCollected, ascCollected
    end
    local function switchCardsInHouse(sendResponse, enableCards)
        local cardsToSwitch = {}
        for _, card in ipairs(data.dialogData.videocards) do
            if enableCards and not card.working then
                if card.coolant > 0 then
                    table.insert(cardsToSwitch, card)
                else
                    utils.debugChat(string.format("Пропускаем карту [%d] — жидкость 0%%", card.index))
                end
            elseif not enableCards and card.working then
                table.insert(cardsToSwitch, card)
            end
        end

        if #cardsToSwitch == 0 then return 0 end

        data.cardSwitchFailed = 0
        for idx, card in ipairs(cardsToSwitch) do
            progressTracker.increment(true)
            dialogActions.selectCard(sendResponse, card.index - 1)
            dialogActions.switchCard(sendResponse)
        end
        wait(250)

        local failed = data.cardSwitchFailed or 0
        return math.max(0, #cardsToSwitch - failed)
    end
    local function createProtectedTask(taskFunction, ...)
        local args = { ... }
        return taskState.ifNotWorking(function()
            local action_count = 0
            lua_thread.create(function()
                taskState.setWorking(true)
                data.taskTypeNow = taskType
                data.stopAction = false
                local startTime = os.clock()
                utils.debugChat(string.format("Задача '%s' запущена...", taskType))
                action_count = (os.clock() - data.globalActionCounter.lastActionTime) > 3.0 and 0 or
                    data.globalActionCounter.count

                local function sendResponse(...)
                    if data.stopAction then return end
                    local function isPaydayTime()
                        if data.skipPayday then return false end

                        if data.paydaySkippedAt > 0 and (os.time() - data.paydaySkippedAt) < 120 then
                            return false
                        end

                        local os_time = os.time()
                        local M = tonumber(os.date("%M", os_time))
                        local S = tonumber(os.date("%S", os_time))

                        return ((M == 59 and S >= 50) or (M == 0 and S <= 20) or
                                (M == 29 and S >= 50) or (M == 30 and S <= 20)) and
                            (taskType ~= 'updateStatuses' and taskType ~= 'scanBasements')
                    end

                    if isPaydayTime() and cfg.pauseOnPayday then
                        data.isWaitingPayday = true
                        data.skipPayday = false
                        utils.debugChat("{ffe133}Время PayDay...")

                        while not data.skipPayday do
                            local os_time = os.time()
                            local M = tonumber(os.date("%M", os_time))
                            local S = tonumber(os.date("%S", os_time))
                            local stillPayday = (M == 59 and S >= 50) or (M == 0 and S <= 20) or
                                (M == 29 and S >= 50) or (M == 30 and S <= 20)

                            if not stillPayday then break end

                            wait(500)
                            if data.stopAction then
                                data.isWaitingPayday = false
                                data.skipPayday = false
                                return
                            end
                        end

                        data.paydaySkippedAt = os.time()
                        data.isWaitingPayday = false
                        data.skipPayday = false
                        utils.debugChat("{99ff99}Продолжаем.")
                        wait(1000)
                    end
                    sampSendDialogResponse(...)
                    action_count = action_count + 1
                    if not data.isRodina and action_count > 0 and action_count % cfg.count_action == 0 then
                        if taskType ~= 'updateStatuses' then
                            wait(cfg.pause_duration)
                        else
                            wait(150)
                        end
                        utils.debugChat(string.format('Пауза на %d действии', action_count))
                    end
                end

                local success, err = pcall(function() taskFunction(sendResponse, unpack(args)) end)

                if not success then
                    utils.addChat("{F78181}Критическая ошибка: " .. tostring(err))
                    print("{F78181}Критическая ошибка: " .. tostring(err))
                    if sampIsDialogActive() then
                        sampCloseCurrentDialogWithButton(0)
                    end
                end
                if data.stopAction and not data.stopBySystem then
                    utils.addChat("{FFE133}Остановлено пользователем.")
                end
                data.stopBySystem = false

                local duration = os.clock() - startTime
                utils.debugChat(string.format("Задача '%s' завершена за %.2f сек.", taskType, duration))
                data.globalActionCounter.count = action_count
                data.globalActionCounter.lastActionTime = os.clock()

                progressTracker.reset()
                wait(100)
                taskState.setWorking(false)
                if taskType == 'updateStatuses' then imgui.addNotification(u8 'Обновлено') end
                data.taskTypeNow = nil
            end)
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
            createProtectedTask(function(sendResponse)
                local cardsToProcess = {}
                for _, card in ipairs(data.dialogData.videocards) do
                    if card.coolant < cfg.useCoolantPercent then
                        table.insert(cardsToProcess, card)
                    end
                end

                if #cardsToProcess == 0 then
                    if not cfg.fixCoolantEnabled then
                        utils.addChat("Во всех видеокартах достаточно охлаждающей жидкости.")
                    end
                    return
                end

                local coolantBottles = 0
                local actuallyFilled = 0

                for _, card in ipairs(cardsToProcess) do
                    if data.stopAction then break end

                    local effectiveSuper = cfg.useSuperCoolant or data.isViceCity
                    local refill_count = effectiveSuper and 1 or ((card.coolant < 50.0) and 2 or 1)
                    if not effectiveSuper and cfg.economyMode and (card.coolant + 50) > 70 then
                        refill_count = 1
                    end

                    for i = 1, refill_count do
                        if data.stopAction then break end
                        dialogActions.selectCard(sendResponse, card.index - 1)
                        dialogActions.refillCoolant(sendResponse, card.fluidType, effectiveSuper,
                            card.card_type == "ASIC")
                    end

                    wait(200)

                    if not data.stopAction then
                        actuallyFilled = actuallyFilled + 1
                        coolantBottles = coolantBottles + refill_count
                        card.coolant = 100
                        dialogActions.closeDialog(sendResponse, dialogIdTable.videoCardDialogId)
                    end
                end

                if actuallyFilled > 0 then
                    logsTool.addCoolant(actuallyFilled, coolantBottles, cfg.useSuperCoolant)
                end
            end)
        end
    elseif taskType == 'switchCards' then
        task.switchCards = function(self, enable)
            createProtectedTask(function(sendResponse)
                local totalSwitched = 0
                for attempt = 1, 2 do
                    local count = switchCardsInHouse(sendResponse, enable)
                    totalSwitched = totalSwitched + count
                    if count == 0 then
                        if attempt == 1 then
                            utils.addChat("Видеокарты и так уже " ..
                                (enable and "включены." or "выключены."))
                        end
                        break
                    end
                    if attempt == 1 then wait(300) end
                end
                if totalSwitched > 0 then
                    logsTool.add('switch', { enabled = enable, count = totalSwitched })
                end
            end)
        end
    elseif taskType == 'takeCrypto' then
        task.takeCrypto = function(self)
            createProtectedTask(function(sendResponse)
                data.withdraw = { asc = 0, btc = 0 }

                for attempt = 1, 2 do
                    local btc, asc = collectCardsFromHouse(sendResponse)
                    if btc == 0 and asc == 0 then
                        if attempt == 1 then
                            utils.addChat("Нет криптовалюты для снятия.")
                        end
                        break
                    end

                    if attempt == 1 then wait(300) end
                end
                wait(300)
                local earnings, hasEarnings = formatEarnings(
                    data.withdraw.btc, data.withdraw.asc,
                    not data.isRodina, "{ffffff} и "
                )
                if hasEarnings then
                    utils.addChat("Выведено: " .. earnings .. "{ffffff}.")
                end
                if data.withdraw.btc > 0 or data.withdraw.asc > 0 then
                    logsTool.add('collect', { btc = data.withdraw.btc, asc = data.withdraw.asc, houses = 1 })
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
            local housesToProcess = {}
            for _, house in ipairs(houses) do
                if houseFilter.shouldProcess(house) then
                    table.insert(housesToProcess, house)
                end
            end
            data.withdraw = { asc = 0, btc = 0 }

            createProtectedTask(function(sendResponse)
                local actualHousesToProcess = {}
                for _, house in ipairs(housesToProcess) do
                    local status = data.houseStatuses[house.house_number]
                    if status and status.lastCheck > 0 then
                        local btc = (status.earnings and status.earnings.btc) or 0
                        local asc = (status.earnings and status.earnings.asc) or 0
                        local minThreshold = cfg.collectOnlyIfMin or 0
                        local hasBtc = btc >= math.max(1, minThreshold)
                        local hasAsc = asc >= 1
                        if hasBtc or hasAsc then
                            table.insert(actualHousesToProcess, house)
                        end
                    else
                        table.insert(actualHousesToProcess, house)
                    end
                end

                progressTracker.setTotal(#actualHousesToProcess)
                local housesCollectedFrom = 0
                for i, house in ipairs(actualHousesToProcess) do
                    if data.stopAction then break end
                    data.currentCollectHouse = u8(string.format("Дом №%d (%d/%d)",
                        house.house_number, i, #actualHousesToProcess))

                    local status = data.houseStatuses[house.house_number]
                    if status and status.lastCheck > 0 then
                        local hasBtc = status.earnings and status.earnings.btc >= 1
                        local hasAsc = status.earnings and status.earnings.asc >= 1
                        if not hasBtc and not hasAsc then
                            progressTracker.increment()
                            goto continue_loop
                        end
                    end

                    local prevBtc = data.withdraw.btc
                    local prevAsc = data.withdraw.asc
                    visitHouseCards(sendResponse, house, function(cards)
                        local cardsToCollect = {}
                        for _, card in ipairs(cards) do
                            if card.btc >= 1 or card.asc >= 1 then table.insert(cardsToCollect, card) end
                        end
                        progressTracker.setHouseTotal(#cardsToCollect)
                        for attempt = 1, 2 do
                            local btc, asc = collectCardsFromHouse(sendResponse)
                            if btc == 0 and asc == 0 then break end
                            if attempt == 1 then wait(500) end
                        end
                    end)
                    if data.withdraw.btc > prevBtc or data.withdraw.asc > prevAsc then
                        housesCollectedFrom = housesCollectedFrom + 1
                    end
                    ::continue_loop::
                end

                wait(250)
                local earnings, hasEarnings = formatEarnings(
                    data.withdraw.btc, data.withdraw.asc,
                    not data.isRodina, "{ffffff} и "
                )
                if hasEarnings then
                    utils.addChat("Всего собрано: " .. earnings .. "{ffffff}.")
                    logsTool.add('collect',
                        { btc = data.withdraw.btc, asc = data.withdraw.asc, houses = housesCollectedFrom })
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

            local housesToProcess = {}
            for _, house in ipairs(houses) do
                if houseFilter.shouldProcess(house) then
                    table.insert(housesToProcess, house)
                end
            end

            createProtectedTask(function(sendResponse, enable_arg)
                local actualHousesToProcess = {}
                for _, house in ipairs(housesToProcess) do
                    local status = data.houseStatuses[house.house_number]
                    local needsProcessing = true

                    if status and status.lastCheck > 0 and status.cardLevels then
                        local total, working = 0, 0
                        for _, lvl in pairs(status.cardLevels) do
                            total   = total + lvl.total
                            working = working + lvl.working
                        end
                        if enable_arg and total > 0 and total == working then
                            needsProcessing = false
                        elseif not enable_arg and working == 0 then
                            needsProcessing = false
                        end
                    end

                    if needsProcessing then
                        table.insert(actualHousesToProcess, house)
                    end
                end

                local snapshotBefore = {}
                for _, house in ipairs(actualHousesToProcess) do
                    local status = data.houseStatuses[house.house_number]
                    if status and status.cardLevels then
                        local total, working = 0, 0
                        for _, lvl in pairs(status.cardLevels) do
                            total   = total + lvl.total
                            working = working + lvl.working
                        end
                        snapshotBefore[house.house_number] = { total = total, working = working }
                    end
                end

                progressTracker.setTotal(#actualHousesToProcess)

                for i, house in ipairs(actualHousesToProcess) do
                    if data.stopAction then break end
                    visitHouseCards(sendResponse, house, function(cards)
                        local cardsToSwitch = 0
                        for _, card in ipairs(cards) do
                            if (enable_arg and not card.working) or (not enable_arg and card.working) then
                                cardsToSwitch = cardsToSwitch + 1
                            end
                        end
                        progressTracker.setHouseTotal(cardsToSwitch)
                        for attempt = 1, 2 do
                            local switchedCount = switchCardsInHouse(sendResponse, enable_arg)
                            if switchedCount == 0 then break end
                            if attempt == 1 then wait(500) end
                        end
                    end)
                end
                wait(300)

                local totalSwitched = 0
                local housesActuallySwitched = 0
                for _, house in ipairs(actualHousesToProcess) do
                    local before = snapshotBefore[house.house_number]
                    local status = data.houseStatuses[house.house_number]
                    if before and status and status.cardLevels then
                        local total, working = 0, 0
                        for _, lvl in pairs(status.cardLevels) do
                            total   = total + lvl.total
                            working = working + lvl.working
                        end
                        local diff = enable_arg
                            and (working - before.working)
                            or (before.working - working)
                        if diff > 0 then
                            totalSwitched          = totalSwitched + diff
                            housesActuallySwitched = housesActuallySwitched + 1
                        end
                    end
                end

                if totalSwitched > 0 then
                    logsTool.add('switch', {
                        enabled = enable,
                        count   = totalSwitched,
                        houses  = housesActuallySwitched
                    })
                end
            end, enable)
        end
    elseif taskType == 'updateStatuses' then
        task.run = function(self)
            local time = os.clock()
            local houses = {}
            for _, h in ipairs(data.dialogData.flashminer) do table.insert(houses, h) end
            if not houses or #houses == 0 then return false end
            local housesToProcess = {}
            for _, house in ipairs(houses) do
                if houseFilter.shouldProcess(house) then
                    table.insert(housesToProcess, house)
                end
            end

            createProtectedTask(function(sendResponse)
                progressTracker.setTotal(#housesToProcess)

                for i, house in ipairs(housesToProcess) do
                    if data.stopAction then break end
                    data.dialogData.videocards = {}

                    dialogActions.selectHouse(sendResponse, house.index - 1)
                    smart_wait(300, time)
                    dialogActions.closeDialog(sendResponse)

                    progressTracker.increment()
                end

                if not data.initialScanCompleted then
                    data.initialScanCompleted = true
                end
            end)
        end
    elseif taskType == 'scanBasements' then
        task.run = function(self, housesToScan)
            local houses = housesToScan or {}
            if not housesToScan then
                for _, h in ipairs(data.dialogData.flashminer) do
                    table.insert(houses, h)
                end
            end

            if not houses or #houses == 0 then return false end

            createProtectedTask(function(sendResponse)
                progressTracker.setTotal(#houses)

                if not housesToScan then
                    cfg.housesWithoutBasement = {}
                    cfg.basementScanned = {}
                end

                for i, house in ipairs(houses) do
                    if data.stopAction then break end
                    data.houseHasNoBasement = false

                    dialogActions.selectHouse(sendResponse, house.index - 1)

                    local start_time = os.clock()
                    while os.clock() - start_time < 0.5 do
                        wait(100)
                        if data.houseHasNoBasement then break end
                    end

                    if data.houseHasNoBasement then
                        cfg.housesWithoutBasement[tostring(house.house_number)] = true
                        sampSendChat("/flashminer")
                        wait(150)
                    else
                        dialogActions.closeDialog(sendResponse)
                    end
                    cfg.basementScanned[tostring(house.house_number)] = true
                    progressTracker.increment()
                end
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
            local housesToProcess = {}
            for _, house in ipairs(houses) do
                if houseFilter.shouldProcess(house) then
                    table.insert(housesToProcess, house)
                end
            end

            createProtectedTask(function(sendResponse)
                data.progressTotal = #housesToProcess
                local summary = {
                    btc_collected = 0,
                    asc_collected = 0,
                    cards_switched_on = 0,
                    money_on_balance = 0,
                    taxes_paid = 0,
                    houses_topped_up = 0,
                    houses_to_top_up = {},
                    houses_with_high_tax = {}
                }
                for _, house in ipairs(housesToProcess) do
                    if house.balance < cfg.targetHouseBalance and (cfg.targetHouseBalance - house.balance) > 10000 then
                        table.insert(summary.houses_to_top_up, house)
                    end
                end

                if not cfg.useSimpleTopUp then
                    for i, house in ipairs(housesToProcess) do
                        if data.stopAction then break end
                        data.progressHouseCurrent = 0
                        data.progressHouseTotal = 0
                        sendResponse(dialogIdTable.houseDialogId, 1, house.index - 1, "")
                        wait(500)

                        local cardsToCollect = {}
                        local cardsToSwitchOn = {}
                        for _, cardData in ipairs(data.dialogData.videocards) do
                            if cfg.fixCollectEnabled and (cardData.btc >= 1 or cardData.asc >= 1) then
                                table.insert(cardsToCollect, cardData)
                            end
                            if cfg.fixSwitchEnabled and not cardData.working and cardData.coolant >= cfg.useCoolantPercent then
                                table.insert(cardsToSwitchOn, cardData)
                            end
                        end
                        data.progressHouseTotal = #cardsToCollect + #cardsToSwitchOn
                        if #cardsToCollect > 0 or #cardsToSwitchOn > 0 then
                            if cfg.fixCollectEnabled then
                                local btcCollected, ascCollected = collectCardsFromHouse(sendResponse)
                                summary.btc_collected = summary.btc_collected + btcCollected
                                summary.asc_collected = summary.asc_collected + ascCollected
                                if btcCollected > 0 or ascCollected > 0 then wait(300) end
                            end
                            if cfg.fixSwitchEnabled then
                                local switchedCount = switchCardsInHouse(sendResponse, true)
                                summary.cards_switched_on = summary.cards_switched_on + switchedCount
                                if switchedCount > 0 then wait(300) end
                            end
                        end

                        sendResponse(dialogIdTable.houseFlashMinerDialogId, 0, 0, "")
                        data.progressCurrent = data.progressCurrent + 1
                    end

                    sampCloseCurrentDialogWithButton(0)
                end
                if #summary.houses_to_top_up > 0 and (cfg.fixTopUpEnabled or cfg.useSimpleTopUp) then
                    sampSendChat("/phone")
                    sendcef('launchedApp|24')
                    sampSendChat("/phone")
                    sendResponse(dialogIdTable.phoneBankMenuId, 1, 10, "")
                    wait(500)


                    for i, house in ipairs(summary.houses_to_top_up) do
                        if data.stopAction or not data.working then break end

                        local total_amount_needed = math.min(cfg.targetHouseBalance, 60000000 - 1) - house.balance

                        if total_amount_needed < 10000 then
                            goto continue_topup
                        end

                        local remaining_to_add = total_amount_needed
                        local house_was_topped = false

                        while remaining_to_add >= 10000 do
                            if data.stopAction or not data.working then break end

                            local amount_this_transaction = math.min(remaining_to_add, 10000000)
                            local leftover = remaining_to_add - amount_this_transaction
                            if leftover > 0 and leftover < 10000 then
                                amount_this_transaction = amount_this_transaction - 10000
                            end

                            if amount_this_transaction < 10000 then
                                break
                            end

                            sendResponse(dialogIdTable.houseListBankId, 1, house.index - 1, "")
                            sendResponse(dialogIdTable.topUpBalanceDialogId, 1, 0, tostring(amount_this_transaction))

                            if data.stopAction then break end

                            summary.money_on_balance = summary.money_on_balance + amount_this_transaction
                            remaining_to_add = remaining_to_add - amount_this_transaction
                            house_was_topped = true
                        end

                        if house_was_topped then
                            summary.houses_topped_up = summary.houses_topped_up + 1
                        end

                        ::continue_topup::
                    end

                    if sampIsDialogActive() then
                        local activeId = sampGetCurrentDialogId()
                        sendResponse(activeId, 0, 0, "")
                    end
                    wait(100)
                end
                sampSendChat("/flashminer")
                wait(300)
                local report = {}
                local earnings, hasEarnings = formatEarnings(summary.btc_collected, summary.asc_collected,
                    not data.isRodina, " и ")
                if hasEarnings then
                    table.insert(report, "Собрано: " .. earnings)
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

                if cfg.useSimpleTopUp then
                    if summary.money_on_balance > 0 then
                        logsTool.add('topup', {
                            topup  = summary.money_on_balance,
                            houses = summary.houses_topped_up
                        })
                    end
                else
                    logsTool.add('fix', {
                        btc    = summary.btc_collected,
                        asc    = summary.asc_collected,
                        topup  = summary.money_on_balance,
                        cards  = summary.cards_switched_on,
                        houses = #housesToProcess
                    })
                end
            end)
        end
    elseif taskType == 'autoPayTaxes' then
        task.run = function(self)
            createProtectedTask(function(sendResponse)
                taxTool.resetCapturedAmount()

                sampSendChat("/phone")
                sendcef('launchedApp|24')
                sampSendChat("/phone")
                wait(500)

                sendResponse(dialogIdTable.phoneBankMenuId, 1, 4, "")
                wait(300)

                sendResponse(dialogIdTable.payAllTaxesDialogId, 1, 0, "")
                wait(500)

                if sampIsDialogActive() then
                    local activeId = sampGetCurrentDialogId()
                    sendResponse(activeId, 0, 0, "")
                end

                cfg.lastTaxPayTime = os.time()
                save()

                local paid = taxTool.getCapturedAmount()
                if paid > 0 then
                    utils.addChat(string.format(
                        "{BEF781}Налоги оплачены: {FFD700}$%s",
                        utils.formatNumber(paid)))
                    logsTool.add('tax', { amount = paid })
                end
            end)
        end
    elseif taskType == 'autoTopUp' then
        task.run = function(self, housesToTopUp)
            if not housesToTopUp or #housesToTopUp == 0 then
                housesToTopUp = {}
                for _, house in ipairs(data.dialogData.flashminer) do
                    if houseFilter.shouldProcess(house) then
                        local threshold = cfg.autoTopUpByThreshold
                            and cfg.autoTopUpThreshold
                            or cfg.targetHouseBalance
                        if house.balance < threshold and (threshold - house.balance) > 10000 then
                            table.insert(housesToTopUp, house)
                        end
                    end
                end
            end

            if #housesToTopUp == 0 then
                utils.debugChat("[CHEAT] Пополнение не требуется.")
                return false
            end

            createProtectedTask(function(sendResponse)
                local totalTopUp = 0
                local housesCount = 0

                progressTracker.setTotal(#housesToTopUp)

                -- Открываем телефон -> банк -> пополнение
                sampSendChat("/phone")
                sendcef('launchedApp|24')
                sampSendChat("/phone")
                wait(500)

                sendResponse(dialogIdTable.phoneBankMenuId, 1, 10, "")
                wait(500)

                for i, house in ipairs(housesToTopUp) do
                    if data.stopAction then break end

                    data.currentCollectHouse = u8(string.format(
                        "Дом №%d (%d/%d)", house.house_number, i, #housesToTopUp))

                    local targetBalance = math.min(
                        cfg.autoTopUpByThreshold and cfg.targetHouseBalance or cfg.targetHouseBalance,
                        60000000 - 1)
                    local amountNeeded = targetBalance - house.balance

                    if amountNeeded < 10000 then
                        progressTracker.increment()
                        goto continue_topup
                    end

                    local remaining = amountNeeded
                    local houseWasTopped = false

                    while remaining >= 10000 do
                        if data.stopAction then break end

                        local amount = math.min(remaining, 10000000)
                        local leftover = remaining - amount
                        if leftover > 0 and leftover < 10000 then
                            amount = amount - 10000
                        end
                        if amount < 10000 then break end

                        sendResponse(dialogIdTable.houseListBankId, 1, house.index - 1, "")
                        sendResponse(dialogIdTable.topUpBalanceDialogId, 1, 0, tostring(amount))

                        totalTopUp = totalTopUp + amount
                        remaining = remaining - amount
                        houseWasTopped = true
                    end

                    if houseWasTopped then housesCount = housesCount + 1 end
                    progressTracker.increment()

                    ::continue_topup::
                end

                if sampIsDialogActive() then
                    local activeId = sampGetCurrentDialogId()
                    sendResponse(activeId, 0, 0, "")
                end
                wait(100)

                cfg.lastAutoTopUpTime = os.time()
                save()

                data.currentCollectHouse = ""

                if totalTopUp > 0 then
                    utils.addChat(string.format(
                        "{BEF781}Баланс пополнен: {FFD700}$%s {808080}(%d домов)",
                        utils.formatNumber(totalTopUp), housesCount))
                    logsTool.add('topup', { topup = totalTopUp, houses = housesCount })
                end
            end)
        end
    end
    return task
end

function withSilentFlashminer(callback)
    if data.working then return false end
    if not flashminerTool.hasIt() then return false end
    local restoreHouseControl = data.showHouseControlWindow[0] == true
    taskState.setSilent(true)
    if not flashminerTool.requestList(5000) then
        taskState.setSilent(false)
        return false
    end

    local result = callback()

    wait(300)
    if sampIsDialogActive() then
        sampCloseCurrentDialogWithButton(0)
        wait(300)
    end
    fixI()
    wait(300)
    data.silentWindowOpen          = false
    data.showHouseControlWindow[0] = restoreHouseControl
    return result ~= false
end

function runSilentTask(taskName, arg)
    if data.working then return false end
    return withSilentFlashminer(function()
        local task = buildTaskTable(taskName)
        task:run(arg)
        wait(500)
        while data.working do wait(200) end
    end)
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    imgui.GetIO().MouseDrawCursor = true
    imgui.GetStyle().MouseCursorScale = 1
    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true
    local iconRanges = imgui.new.ImWchar[3](fa.min_range, fa.max_range, 0)
    imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(fa.get_font_data_base85('solid'), 14, config, iconRanges)
end)

function applyStyle()
    imgui.SwitchContext()
    local style                       = imgui.GetStyle()
    local colors                      = style.Colors
    local Col                         = imgui.Col
    local ImVec4                      = imgui.ImVec4
    local ImVec2                      = imgui.ImVec2

    style.WindowPadding               = ImVec2(12, 12)
    style.FramePadding                = ImVec2(8, 6)
    style.ItemSpacing                 = ImVec2(8, 8)
    style.ItemInnerSpacing            = ImVec2(6, 6)
    style.TouchExtraPadding           = ImVec2(0, 0)
    style.IndentSpacing               = 20.0
    style.ScrollbarSize               = 10.0
    style.GrabMinSize                 = 5.0

    style.WindowBorderSize            = 1
    style.ChildBorderSize             = 1
    style.PopupBorderSize             = 1
    style.FrameBorderSize             = 0
    style.TabBorderSize               = 1
    style.WindowRounding              = 6.0
    style.ChildRounding               = 6.0
    style.FrameRounding               = 4.0
    style.PopupRounding               = 5.0
    style.ScrollbarRounding           = 9.0
    style.GrabRounding                = 3.0
    style.TabRounding                 = 5.0

    style.WindowTitleAlign            = ImVec2(0.5, 0.5)
    style.ButtonTextAlign             = ImVec2(0.5, 0.5)
    style.SelectableTextAlign         = ImVec2(0.5, 0.5)

    colors[Col.Text]                  = ImVec4(0.95, 0.96, 0.98, 1.00)
    colors[Col.TextDisabled]          = ImVec4(0.50, 0.50, 0.50, 1.00)
    colors[Col.WindowBg]              = ImVec4(0.06, 0.07, 0.10, 1.00)
    colors[Col.ChildBg]               = ImVec4(0.09, 0.10, 0.14, 1.00)
    colors[Col.PopupBg]               = ImVec4(0.08, 0.08, 0.08, 0.94)
    colors[Col.Border]                = ImVec4(0.20, 0.22, 0.27, 0.50)
    colors[Col.BorderShadow]          = ImVec4(0, 0, 0, 0)
    colors[Col.FrameBg]               = ImVec4(0.13, 0.14, 0.19, 1.00)
    colors[Col.FrameBgHovered]        = ImVec4(0.18, 0.19, 0.25, 1.00)
    colors[Col.FrameBgActive]         = ImVec4(0.22, 0.23, 0.29, 1.00)
    colors[Col.TitleBg]               = ImVec4(0.06, 0.07, 0.10, 1.00)
    colors[Col.TitleBgActive]         = ImVec4(0.06, 0.07, 0.10, 1.00)
    colors[Col.TitleBgCollapsed]      = ImVec4(0.06, 0.07, 0.10, 1.00)
    colors[Col.MenuBarBg]             = ImVec4(0.06, 0.07, 0.10, 1.00)
    colors[Col.ScrollbarBg]           = ImVec4(0.06, 0.07, 0.10, 1.00)
    colors[Col.ScrollbarGrab]         = ImVec4(0.16, 0.17, 0.21, 1.00)
    colors[Col.ScrollbarGrabHovered]  = ImVec4(0.20, 0.21, 0.26, 1.00)
    colors[Col.ScrollbarGrabActive]   = ImVec4(0.24, 0.25, 0.30, 1.00)
    colors[Col.CheckMark]             = ImVec4(1.00, 1.00, 1.00, 1.00)
    colors[Col.SliderGrab]            = ImVec4(1.00, 1.00, 1.00, 0.30)
    colors[Col.SliderGrabActive]      = ImVec4(1.00, 1.00, 1.00, 0.30)
    colors[Col.Button]                = ImVec4(0.16, 0.17, 0.21, 1.00)
    colors[Col.ButtonHovered]         = ImVec4(0.20, 0.21, 0.26, 1.00)
    colors[Col.ButtonActive]          = ImVec4(0.24, 0.25, 0.30, 1.00)
    colors[Col.Header]                = ImVec4(0.20, 0.22, 0.27, 1.00)
    colors[Col.HeaderHovered]         = ImVec4(0.25, 0.27, 0.32, 1.00)
    colors[Col.HeaderActive]          = ImVec4(0.28, 0.30, 0.35, 1.00)
    colors[Col.Separator]             = ImVec4(0.20, 0.22, 0.27, 0.50)
    colors[Col.SeparatorHovered]      = ImVec4(0.25, 0.27, 0.32, 1.00)
    colors[Col.SeparatorActive]       = ImVec4(0.28, 0.30, 0.35, 1.00)
    colors[Col.ResizeGrip]            = ImVec4(1.00, 1.00, 1.00, 0.25)
    colors[Col.ResizeGripHovered]     = ImVec4(1.00, 1.00, 1.00, 0.67)
    colors[Col.ResizeGripActive]      = ImVec4(1.00, 1.00, 1.00, 0.95)
    colors[Col.Tab]                   = ImVec4(0.16, 0.17, 0.21, 1.00)
    colors[Col.TabHovered]            = ImVec4(0.20, 0.21, 0.26, 1.00)
    colors[Col.TabActive]             = ImVec4(0.24, 0.25, 0.30, 1.00)
    colors[Col.TabUnfocused]          = ImVec4(0.06, 0.07, 0.10, 1.00)
    colors[Col.TabUnfocusedActive]    = ImVec4(0.16, 0.17, 0.21, 1.00)
    colors[Col.PlotLines]             = ImVec4(0.61, 0.61, 0.61, 1.00)
    colors[Col.PlotLinesHovered]      = ImVec4(1.00, 0.43, 0.35, 1.00)
    colors[Col.PlotHistogram]         = ImVec4(1.00, 0.78, 0.00, 1.00)
    colors[Col.PlotHistogramHovered]  = ImVec4(1.00, 0.60, 0.00, 1.00)
    colors[Col.TextSelectedBg]        = ImVec4(1.00, 0.00, 0.00, 0.35)
    colors[Col.DragDropTarget]        = ImVec4(1.00, 1.00, 0.00, 0.90)
    colors[Col.NavHighlight]          = ImVec4(0.26, 0.59, 0.98, 1.00)
    colors[Col.NavWindowingHighlight] = ImVec4(1.00, 1.00, 1.00, 0.70)
    colors[Col.NavWindowingDimBg]     = ImVec4(0.80, 0.80, 0.80, 0.20)
    colors[Col.ModalWindowDimBg]      = ImVec4(0.00, 0.00, 0.00, 0.70)
end

function applyCustomStyle()
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

local _nAlpha, _nAlphaVel, _nLastT, _nSaveT = 0.0, 0.0, 0.0, 0.0

-- окно подсказки
imgui.OnFrame(
    function()
        return data.notifyWindow.show[0] or _nAlpha > 0.005 or isInImproveHintRange()
    end,
    function(self)
        local inImproveRange = isInImproveHintRange()
        local curMode        = data.notifyWindow.mode
        local higherPriority = curMode == 'countdown' or curMode == 'collecting'
            or (curMode == 'reminder' and data.notifyWindow.show[0])
        if inImproveRange and not higherPriority then
            data.notifyWindow.show[0]    = true
            data.notifyWindow.mode       = 'improveHint'
            data.notifyWindow.autoHideAt = 0
            data.notifyWindow.isPreview  = false
        elseif data.notifyWindow.mode == 'improveHint' and not inImproveRange then
            data.notifyWindow.show[0] = false
        end

        if not cfg.notifyAutoCollectEnabled and
            (data.notifyWindow.mode == 'countdown' or data.notifyWindow.mode == 'collecting') then
            data.notifyWindow.show[0] = false
        end
        if data.notifyWindow.autoHideAt > 0 and os.time() >= data.notifyWindow.autoHideAt then
            data.notifyWindow.show[0] = false
            data.notifyWindow.autoHideAt = 0
            data.notifyWindow.isPreview = false
        end

        local now           = os.clock()
        local dt            = _nLastT > 0 and math.min(now - _nLastT, 0.05) or 0.016
        _nLastT             = now
        local tgt           = data.notifyWindow.show[0] and 1.0 or 0.0
        _nAlpha, _nAlphaVel = smoothDamp(_nAlpha, tgt, _nAlphaVel, dt, 0.22)
        if _nAlpha < 0.005 then return end

        applyStyle()
        local sw, sh       = getScreenResolution()

        local isPreview    = data.notifyWindow.isPreview
        local isActionMode = data.notifyWindow.mode == 'countdown'
            or data.notifyWindow.mode == 'collecting'
        local isChatOpen   = sampIsChatInputActive()

        self.HideCursor    = not (isPreview or isChatOpen)

        if isPreview then
            imgui.SetNextWindowPos(
                imgui.ImVec2(cfg.notifyWindowPosX * sw, cfg.notifyWindowPosY * sh),
                imgui.Cond.Appearing
            )
        else
            imgui.SetNextWindowPos(
                imgui.ImVec2(cfg.notifyWindowPosX * sw, cfg.notifyWindowPosY * sh),
                imgui.Cond.Always
            )
        end

        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.06, 0.07, 0.10, 0.96 * _nAlpha))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.22, 0.24, 0.30, 0.90 * _nAlpha))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.95, 0.96, 0.98, _nAlpha))
        imgui.PushStyleColor(imgui.Col.Separator, imgui.ImVec4(0.20, 0.22, 0.27, 0.50 * _nAlpha))
        imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.13, 0.14, 0.19, _nAlpha))

        local flags = imgui.WindowFlags.NoCollapse
            + imgui.WindowFlags.NoTitleBar
            + imgui.WindowFlags.NoScrollbar
            + imgui.WindowFlags.NoResize
            + imgui.WindowFlags.AlwaysAutoResize
            + 4096
            + (isPreview and 0 or 512)
            + (isPreview and 0 or imgui.WindowFlags.NoMove)

        if imgui.Begin("##mntNotify", data.notifyWindow.show, flags) then
            if isPreview then
                local wp = imgui.GetWindowPos()
                local nx, ny = wp.x / sw, wp.y / sh
                if math.abs(nx - cfg.notifyWindowPosX) > 0.003 or
                    math.abs(ny - cfg.notifyWindowPosY) > 0.003 then
                    cfg.notifyWindowPosX, cfg.notifyWindowPosY = nx, ny
                    local t = os.clock()
                    if t - _nSaveT > 1.5 then
                        _nSaveT = t; save()
                    end
                end
            end

            if isActionMode and isChatOpen then
                local wp = imgui.GetWindowPos()
                local ws = imgui.GetWindowSize()
                local mx = imgui.GetIO().MousePos.x
                local my = imgui.GetIO().MousePos.y
                local inWindow = mx >= wp.x and mx <= wp.x + ws.x
                    and my >= wp.y and my <= wp.y + ws.y

                if inWindow and imgui.GetIO().MouseClicked[1] then
                    collectTool.cancelPending()
                    data.notifyWindow.show[0] = false
                end
            end

            local mode     = data.notifyWindow.mode
            local secsLeft = (mode == 'countdown')
                and (data.notifyWindow.countdownTarget - os.time()) or 0

            if mode == 'improveHint' then
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.MICROCHIP)
                imgui.SameLine(0, 6)
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), u8 "Заточка")
            else
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.COINS)
                imgui.SameLine(0, 6)
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), u8 "Mining Tools")
            end
            imgui.Separator()
            imgui.Spacing()

            if mode == 'reminder' then
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.COINS)
                imgui.SameLine(0, 6)
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha),
                    u8(string.format("Накопилось ~%d BTC", math.floor(data.notifyWindow.btcAmount or 0))))
                imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.CIRCLE_EXCLAMATION)
                imgui.SameLine(0, 6)
                imgui.TextColored(imgui.ImVec4(0.6, 0.6, 0.6, _nAlpha), u8 "Рекомендуется собрать криптовалюту.")
            elseif mode == 'countdown' then
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.CLOCK)
                imgui.SameLine(0, 6)
                local cdText = secsLeft <= 0 and u8 "Автосбор начинается!"
                    or u8(string.format("Автосбор через: %s", formatTimeLeft(secsLeft)))
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), cdText)
                imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.ROTATE)
                imgui.SameLine(0, 6)
                imgui.TextColored(imgui.ImVec4(0.6, 0.6, 0.6, _nAlpha),
                    u8(string.format("%d сборов в день", cfg.collectTimesPerDay)))
                imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(0.45, 0.45, 0.45, _nAlpha * 0.8),
                    isChatOpen and u8 "ПКМ — отменить автосбор" or u8 "T + ПКМ — отменить автосбор")
            elseif mode == 'collecting' then
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.ROTATE)
                imgui.SameLine(0, 6)
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), u8 "Автосбор выполняется...")
                imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(1, 1, 1, _nAlpha), fa.HOUSE)
                imgui.SameLine(0, 6)
                local houseText = (data.currentCollectHouse ~= "" and data.currentCollectHouse) or u8 "Подготовка..."
                imgui.TextColored(imgui.ImVec4(0.6, 0.6, 0.6, _nAlpha), houseText)
                imgui.Spacing()
                local prog = data.progressTotal > 0 and (data.progressCurrent / data.progressTotal) or 0
                imgui.PushStyleColor(imgui.Col.PlotHistogram, imgui.ImVec4(0.3, 0.8, 0.3, _nAlpha))
                imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.15, 0.15, 0.15, _nAlpha))
                imgui.ProgressBar(prog, imgui.ImVec2(-1, 14),
                    u8(string.format("%d / %d домов", data.progressCurrent,
                        data.progressTotal > 0 and data.progressTotal or 0)))
                imgui.PopStyleColor(2)
                imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(0.45, 0.45, 0.45, _nAlpha * 0.8),
                    isChatOpen and u8 "ПКМ — отменить автосбор" or u8 "T + ПКМ — отменить автосбор")
            elseif mode == 'improveHint' then
                imgui.TextColored(imgui.ImVec4(0.7, 0.85, 1.0, _nAlpha),
                    u8 "Нажмите Alt, чтобы открыть окно заточки.")
            end

            imgui.Spacing()
            imgui.End()
        end

        imgui.PopStyleColor(5)
    end
)

-- окно заточки
imgui.OnFrame(function() return data.showImproveWindow[0] end, function()
    applyStyle()
    local sw, sh = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2),
        imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSizeConstraints(
        imgui.ImVec2(440, 100),
        imgui.ImVec2(440, sh - 80))
    if imgui.Begin(u8 "Заточка##ImproveWin", data.showImproveWindow,
            imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar
            + imgui.WindowFlags.NoResize + imgui.WindowFlags.AlwaysAutoResize) then
        imgui.customTitleBar(data.showImproveWindow,
            function() end, imgui.GetWindowWidth())
        local imStyle = imgui.GetStyle()
        local winW    = imgui.GetWindowWidth()
        do
            local subTabs = { u8 "Заточка", u8 "Задержка" }
            local stCount = #subTabs
            local stW     = (winW - imStyle.WindowPadding.x * 2
                - imStyle.ItemSpacing.x * (stCount - 1)) / stCount
            for si, sl in ipairs(subTabs) do
                if si > 1 then imgui.SameLine(0, imStyle.ItemSpacing.x) end
                imgui.PushStyleColor(imgui.Col.Button,
                    data.improveSubTab == si - 1
                    and imgui.ImVec4(0.18, 0.28, 0.45, 1)
                    or imgui.ImVec4(0.11, 0.12, 0.16, 1))
                imgui.PushStyleColor(imgui.Col.ButtonHovered,
                    imgui.ImVec4(0.20, 0.30, 0.48, 1))
                imgui.PushStyleColor(imgui.Col.ButtonActive,
                    imgui.ImVec4(0.22, 0.32, 0.50, 1))
                if imgui.Button(sl .. "##impSub", imgui.ImVec2(stW, 30)) then
                    data.improveSubTab = si - 1
                end
                imgui.PopStyleColor(3)
            end
            imgui.Spacing()
        end

        if data.improveSubTab == 0 then
            if ButtonWithHint(
                    u8(data.improve.isOn and "Остановить заточку" or "Запустить заточку"),
                    "Нужно стоять у стойки в подвале.", true, imgui.ImVec2(-1, 30)) then
                if data.improve.isOn then
                    improveTool.stop("Остановлено")
                else
                    improveTool.start()
                end
            end

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            imgui.TextColoredRGB(string.format("{808080}Этап: {FFFFFF}%s", improveTool.getStateText()))
            local s = data.improve.stats
            if (s.sessionId or 0) > 0 then
                imgui.TextColoredRGB(string.format(
                    "{808080}Заточка #%d: {BEF781}%d {808080}удачно / {F78181}%d {808080}неудачно",
                    s.sessionId, s.success or 0, s.fail or 0))
                imgui.TextColoredRGB(string.format(
                    "{808080}Потрачено: {FFD700}$%s {808080}· смазки: {FFFFFF}%d",
                    utils.formatNumber(s.spent or 0), s.oilsUsed or 0))
            end

            if data.improve.cef.probing then
                local total = data.improve.cef.probeTotal or 0
                local done  = data.improve.cef.probeProgress or 0
                local pct   = total > 0 and (done / total) or 0
                imgui.TextColoredRGB(string.format(
                    "{87CEFA}Проверка карт: {FFFFFF}%d / %d", done, total))
                imgui.PushStyleColor(imgui.Col.PlotHistogram,
                    imgui.ImVec4(0.18, 0.45, 0.28, 1))
                imgui.ProgressBar(pct, imgui.ImVec2(-1, 18),
                    u8(string.format("%d%%", math.floor(pct * 100 + 0.5))))
                imgui.PopStyleColor()

                local idx = data.improve.cef.pendingIndex or 0
                if idx > 0 then
                    imgui.TextColoredRGB(string.format(
                        "{808080}Текущая: {FFFFFF}#%d {808080}(slot %d)",
                        idx, data.improve.cef.pendingSlot or 0))
                end
                imgui.Spacing()
            end

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            imgui.TextColoredRGB("{87CEFA}Тип карт:")
            do
                local halfW = (winW - imStyle.WindowPadding.x * 2 - imStyle.ItemSpacing.x) / 2

                imgui.PushStyleColor(imgui.Col.Button,
                    cfg.improveTypeCards == 1
                    and imgui.ImVec4(0.18, 0.28, 0.45, 1)
                    or imgui.ImVec4(0.11, 0.12, 0.16, 1))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.30, 0.48, 1))
                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.22, 0.32, 0.50, 1))
                if imgui.Button(u8 "Обычные##impType", imgui.ImVec2(halfW, 28)) then
                    cfg.improveTypeCards = 1; imcfg.improveTypeCards[0] = 1
                    improveTool.syncVideoCards(); save()
                end
                imgui.PopStyleColor(3)

                imgui.SameLine(0, imStyle.ItemSpacing.x)

                imgui.PushStyleColor(imgui.Col.Button,
                    cfg.improveTypeCards == 2
                    and imgui.ImVec4(0.18, 0.28, 0.45, 1)
                    or imgui.ImVec4(0.11, 0.12, 0.16, 1))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.30, 0.48, 1))
                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.22, 0.32, 0.50, 1))
                if imgui.Button(u8 "Arizona##impType", imgui.ImVec2(-1, 28)) then
                    cfg.improveTypeCards = 2; imcfg.improveTypeCards[0] = 2
                    improveTool.syncVideoCards(); save()
                end
                imgui.PopStyleColor(3)
            end

            imgui.Spacing()

            imgui.TextColoredRGB("{87CEFA}Режим улучшения:")
            do
                local halfW = (winW - imStyle.WindowPadding.x * 2 - imStyle.ItemSpacing.x) / 2

                imgui.PushStyleColor(imgui.Col.Button,
                    cfg.improveMode == 1
                    and imgui.ImVec4(0.18, 0.28, 0.45, 1)
                    or imgui.ImVec4(0.11, 0.12, 0.16, 1))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.30, 0.48, 1))
                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.22, 0.32, 0.50, 1))
                if ButtonWithHint(u8 "Последовательное##impMode",
                        "Сначала улучшаем карты низкого уровня.", true,
                        imgui.ImVec2(halfW, 28)) then
                    cfg.improveMode = 1; imcfg.improveMode[0] = 1; save()
                end
                imgui.PopStyleColor(3)

                imgui.SameLine(0, imStyle.ItemSpacing.x)

                imgui.PushStyleColor(imgui.Col.Button,
                    cfg.improveMode == 2
                    and imgui.ImVec4(0.18, 0.28, 0.45, 1)
                    or imgui.ImVec4(0.11, 0.12, 0.16, 1))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.30, 0.48, 1))
                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.22, 0.32, 0.50, 1))
                if ButtonWithHint(u8 "Поочередное##impMode",
                        "Улучшать сначала 1 карту, до нужного уровня.", true,
                        imgui.ImVec2(-1, 28)) then
                    cfg.improveMode = 2; imcfg.improveMode[0] = 2; save()
                end
                imgui.PopStyleColor(3)
            end

            imgui.Spacing()

            imgui.TextColoredRGB("{87CEFA}Целевой уровень:")
            imgui.PushItemWidth(-1)
            if imgui.SliderInt("##impMaxLvl", imcfg.improveMaxLevel, 2, 10,
                    u8(string.format("%d ур.", imcfg.improveMaxLevel[0]))) then
                cfg.improveMaxLevel = imcfg.improveMaxLevel[0]; save()
            end
            imgui.PopItemWidth()
            imgui.Hint("Не улучшать карты, уже достигшие этого уровня.")

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            if imgui.Checkbox(u8 "Улучшать все карты", imcfg.improveMenuAll) then
                cfg.improveMenuAll = imcfg.improveMenuAll[0]
                if cfg.improveMenuAll then
                    data.improve.selectedSlots = {}
                end
                save()
            end
            imgui.Hint("Если выкл — точатся только выбранные карты (можно несколько).\n" ..
                "ПКМ по карте — пометить как «только хранилище».")

            if cfg.improveMenuAll and not cfg.improveUseStorageUpgrade then
                if imgui.Checkbox(u8 "После — навесить хранилище на все",
                        imcfg.improveStorageAfterAll) then
                    cfg.improveStorageAfterAll = imcfg.improveStorageAfterAll[0]
                    if cfg.improveStorageAfterAll then
                        data.improve.storageQueue = {}
                    end
                    save()
                end
                imgui.Hint(
                    "После прохода улучшения уровней навесить хранилище на все карты.\n" ..
                    "Если выкл — хранилище будет навешено только на карты, помеченные ПКМ.")
            end

            if imgui.Checkbox(u8 "Проверять смазку при старте", imcfg.improveCheckOilsOnStart) then
                cfg.improveCheckOilsOnStart = imcfg.improveCheckOilsOnStart[0]; save()
            end
            imgui.Hint("Через /stats. Если выкл — стартует без проверки.")

            if imgui.Checkbox(u8 "Улучшать хранилище (вместо производительности)",
                    imcfg.improveUseStorageUpgrade) then
                cfg.improveUseStorageUpgrade = imcfg.improveUseStorageUpgrade[0]
                data.improve.useStorageUpgrade = cfg.improveUseStorageUpgrade
                save()
            end
            imgui.Hint("Применять увеличители пропускной способности вместо смазки.")

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            local checkBusy = data.improve.oils.busy or data.improve.cef.probing
            if checkBusy then
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.5, 0.5, 0.5, 1))
                imgui.Selectable(u8 "Идёт проверка...", false,
                    imgui.SelectableFlags.Disabled)
                imgui.PopStyleColor()
            else
                if imgui.Selectable(u8 "Проверить уровни карт", false) then
                    improveTool.checkLevels()
                end
                imgui.Hint("Откроет инвентарь и определит уровни всех видеокарт.")
            end

            imgui.Spacing()
            local cardCount = #data.improve.videoCards
            imgui.TextColoredRGB(string.format(
                "{808080}Найдено карт: {FFFFFF}%d", cardCount))

            if not cfg.improveMenuAll and cardCount > 0 then
                imgui.TextColoredRGB(
                    "{808080}Кликни по карте, чтобы выбрать её для заточки:")
            end

            if cardCount > 0 then
                local fullW = winW - imStyle.WindowPadding.x * 2
                local cardW = fullW
                if cardCount > 1 then
                    cardW = (fullW - imStyle.ItemSpacing.x) / 2
                end

                for i, v in ipairs(data.improve.videoCards) do
                    local lvl    = tonumber(v.level) or 0
                    local slot   = tonumber(v.slot) or 0
                    local mark   = v.storageUpgrade and " [ХР+]" or ""
                    local target = cfg.improveMaxLevel or 2

                    local fits
                    if cfg.improveUseStorageUpgrade then
                        fits = not v.storageUpgrade
                    else
                        fits = lvl < target
                    end

                    local isSelected   = data.improve.selectedSlots[slot] == true
                    local wantsStorage = data.improve.storageQueue
                        and data.improve.storageQueue[slot] == true
                    local visible      = string.format(
                        "    #%d: %d ур.%s (slot %d)", i, lvl, mark, slot)
                    local label        = visible .. "##impCard_" .. i

                    local isLastSolo   = (i == cardCount) and (cardCount % 2 == 1) and (cardCount > 1)
                    local thisCardW    = isLastSolo and fullW or cardW

                    if cardCount > 1 and i % 2 == 0 and not isLastSolo then
                        imgui.SameLine(0, imStyle.ItemSpacing.x)
                    end

                    local pushedText = false
                    if not fits then
                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.5, 0.5, 0.5, 1))
                        pushedText = true
                    end

                    imgui.PushStyleColor(imgui.Col.Header, imgui.ImVec4(0, 0, 0, 0))
                    imgui.PushStyleColor(imgui.Col.HeaderHovered, imgui.ImVec4(0, 0, 0, 0))
                    imgui.PushStyleColor(imgui.Col.HeaderActive, imgui.ImVec4(0, 0, 0, 0))

                    local dl = imgui.GetWindowDrawList()
                    dl:ChannelsSplit(2)
                    dl:ChannelsSetCurrent(1)

                    if not fits then
                        imgui.Selectable(u8(label), false,
                            imgui.SelectableFlags.Disabled,
                            imgui.ImVec2(thisCardW, 0))
                    else
                        if imgui.Selectable(u8(label), false, 0,
                                imgui.ImVec2(thisCardW, 0)) then
                            if not cfg.improveMenuAll then
                                if isSelected then
                                    data.improve.selectedSlots[slot] = nil
                                    if data.improve.storageQueue then
                                        data.improve.storageQueue[slot] = nil
                                    end
                                else
                                    data.improve.selectedSlots[slot] = true
                                end
                            end
                        end
                    end

                    local p1 = imgui.GetItemRectMin()
                    local p2 = imgui.GetItemRectMax()

                    if isSelected then
                        local tw = imgui.CalcTextSize(fa.CHECK).x
                        local tx = p1.x + 6
                        local ty = p1.y + (p2.y - p1.y) / 2 - imgui.GetTextLineHeight() / 2
                        dl:AddText(imgui.ImVec2(tx, ty),
                            imgui.ColorConvertFloat4ToU32(
                                imgui.ImVec4(1, 1, 1, fits and 1 or 0.5)),
                            fa.CHECK)
                    end

                    if isSelected or wantsStorage then
                        dl:ChannelsSetCurrent(0)

                        if isSelected and wantsStorage then
                            local mid = (p1.x + p2.x) / 2
                            dl:AddRectFilled(p1,
                                imgui.ImVec2(mid, p2.y),
                                imgui.ColorConvertFloat4ToU32(
                                    imgui.ImVec4(0.18, 0.28, 0.45, 0.85)))
                            dl:AddRectFilled(
                                imgui.ImVec2(mid, p1.y), p2,
                                imgui.ColorConvertFloat4ToU32(
                                    imgui.ImVec4(0.45, 0.25, 0.55, 0.85)))
                        elseif isSelected then
                            dl:AddRectFilled(p1, p2,
                                imgui.ColorConvertFloat4ToU32(
                                    imgui.ImVec4(0.18, 0.28, 0.45, 0.85)))
                        else
                            dl:AddRectFilled(p1, p2,
                                imgui.ColorConvertFloat4ToU32(
                                    imgui.ImVec4(0.45, 0.25, 0.55, 0.85)))
                        end
                    end

                    dl:ChannelsMerge()

                    if imgui.IsItemHovered() then
                        if not fits then
                            imgui.BeginTooltip()
                            if cfg.improveUseStorageUpgrade then
                                imgui.TextColoredRGB("{F78181}На карте уже навешено хранилище.")
                            else
                                imgui.TextColoredRGB(string.format(
                                    "{F78181}У карты уже целевой уровень (%d из %d).", lvl, target))
                            end
                            imgui.EndTooltip()
                        elseif not cfg.improveUseStorageUpgrade
                            and not (cfg.improveMenuAll and cfg.improveStorageAfterAll) then
                            imgui.BeginTooltip()
                            imgui.TextColoredRGB(
                                "{808080}ПКМ — пометить как «только хранилище».")
                            if wantsStorage then
                                imgui.TextColoredRGB(
                                    "{BEF781}На эту карту будет навешено хранилище.")
                            end
                            imgui.EndTooltip()
                        end
                    end

                    if not v.storageUpgrade and not cfg.improveUseStorageUpgrade
                        and not (cfg.improveMenuAll and cfg.improveStorageAfterAll)
                        and imgui.IsItemHovered()
                        and imgui.IsMouseClicked(1) then
                        data.improve.storageQueue = data.improve.storageQueue or {}
                        if data.improve.storageQueue[slot] then
                            data.improve.storageQueue[slot] = nil
                        else
                            data.improve.storageQueue[slot] = true
                        end
                    end

                    imgui.PopStyleColor(3)
                    if pushedText then imgui.PopStyleColor() end

                    if cardCount > 1 and (i % 2 == 0 or i == cardCount) then
                        imgui.Dummy(imgui.ImVec2(0, 4))
                    end
                end
            end
        elseif data.improveSubTab == 1 then
            imgui.TextColoredRGB("{87CEFA}Задержки и таймауты")
            imgui.Spacing()

            imgui.TextColoredRGB("{808080}Повтор клика по диалогу (мс):")
            imgui.PushItemWidth(-1)
            if imgui.SliderInt("##impRetry", imcfg.improveRetryUseDelay,
                    200, 2500, u8(string.format("%d мс", imcfg.improveRetryUseDelay[0]))) then
                cfg.improveRetryUseDelay = imcfg.improveRetryUseDelay[0]; save()
            end
            imgui.PopItemWidth()
            imgui.Hint("Если диалог не открылся — кликнем повторно через это время.")

            imgui.Spacing()
            imgui.TextColoredRGB("{808080}Таймаут ожидания старта (сек):")
            imgui.PushItemWidth(-1)
            if imgui.SliderInt("##impWaitStart", imcfg.improveWaitStartTimeout,
                    3, 15, u8(string.format("%d с", imcfg.improveWaitStartTimeout[0]))) then
                cfg.improveWaitStartTimeout = imcfg.improveWaitStartTimeout[0]; save()
            end
            imgui.PopItemWidth()
            imgui.Hint("Сколько ждать сообщение «Вы начали процесс улучшения».")

            imgui.Spacing()
            imgui.TextColoredRGB("{808080}Таймаут ожидания результата (сек):")
            imgui.PushItemWidth(-1)
            if imgui.SliderInt("##impWaitResult", imcfg.improveWaitResultTimeout,
                    5, 30, u8(string.format("%d с", imcfg.improveWaitResultTimeout[0]))) then
                cfg.improveWaitResultTimeout = imcfg.improveWaitResultTimeout[0]; save()
            end
            imgui.PopItemWidth()
            imgui.Hint("Сколько ждать сообщение об удаче/провале попытки.")

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            imgui.TextColoredRGB("{808080}Пауза после результата (мс):")
            imgui.PushItemWidth(-1)
            if imgui.SliderInt("##impAfterResult", imcfg.improveWaitResult,
                    50, 1500, u8(string.format("%d мс", imcfg.improveWaitResult[0]))) then
                cfg.improveWaitResult = imcfg.improveWaitResult[0]; save()
            end
            imgui.PopItemWidth()
            imgui.Hint("Пауза перед попыткой следующей карты.")

            imgui.Spacing()
            imgui.TextColoredRGB("{808080}Пауза между картами при проверке уровней (мс):")
            imgui.PushItemWidth(-1)
            if imgui.SliderInt("##impProbe", imcfg.improveWaitTryClick,
                    50, 1000, u8(string.format("%d мс", imcfg.improveWaitTryClick[0]))) then
                cfg.improveWaitTryClick = imcfg.improveWaitTryClick[0]; save()
            end
            imgui.PopItemWidth()

            imgui.Spacing()
            imgui.TextColoredRGB("{808080}Таймаут диалога при проверке (сек):")
            imgui.PushItemWidth(-1)
            if imgui.SliderInt("##impDialogTimeout", imcfg.improveTimeoutDialog,
                    1, 15, u8(string.format("%d с", imcfg.improveTimeoutDialog[0]))) then
                cfg.improveTimeoutDialog = imcfg.improveTimeoutDialog[0]; save()
            end
            imgui.PopItemWidth()

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            if imgui.Button(u8 "Сбросить к значениям по умолчанию", imgui.ImVec2(-1, 28)) then
                cfg.improveRetryUseDelay          = 1200
                cfg.improveWaitStartTimeout       = 12
                cfg.improveWaitResultTimeout      = 20
                cfg.improveWaitResult             = 500
                cfg.improveWaitTryClick           = 500
                cfg.improveTimeoutDialog          = 10
                imcfg.improveRetryUseDelay[0]     = 1200
                imcfg.improveWaitStartTimeout[0]  = 12
                imcfg.improveWaitResultTimeout[0] = 20
                imcfg.improveWaitResult[0]        = 500
                imcfg.improveWaitTryClick[0]      = 500
                imcfg.improveTimeoutDialog[0]     = 10
                save()
            end
        end
    end
    imgui.End()
end)

-- окно настроек
imgui.OnFrame(
    function() return data.showSettingsWindow[0] end,
    function(self)
        applyStyle()
        local sw, sh = getScreenResolution()
        imgui.SetNextWindowSizeConstraints(imgui.ImVec2(420, 50), imgui.ImVec2(420, sh - 40))
        imgui.SetNextWindowPos(
            imgui.ImVec2(sw / 2 + 520, sh / 2),
            imgui.Cond.FirstUseEver,
            imgui.ImVec2(0.5, 0.5)
        )

        if imgui.Begin("##settingsWin", data.showSettingsWindow,
                imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar +
                imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar + 64) then
            local imStyle = imgui.GetStyle()
            local winW = imgui.GetWindowWidth()

            imgui.SetCursorPosY(imStyle.ItemSpacing.y)
            local titleIcon = fa.GEAR
            local titleText = u8 "Настройки"
            local totalTitleW = imgui.CalcTextSize(titleIcon).x + 8 + imgui.CalcTextSize(titleText).x
            imgui.SetCursorPos(imgui.ImVec2((winW - totalTitleW) / 2, imStyle.ItemSpacing.y + 3))
            imgui.Text(titleIcon)
            imgui.SameLine(0, 8)
            imgui.SetCursorPosY(imStyle.ItemSpacing.y + 3)
            imgui.TextColoredRGB("{FFFFFF}Настройки")

            imgui.SetCursorPos(imgui.ImVec2(winW - 50 - imStyle.ItemSpacing.x, imStyle.ItemSpacing.y))
            if imgui.Button(fa.XMARK .. "##settClose", imgui.ImVec2(40, 22)) then
                data.showSettingsWindow[0] = false
            end
            imgui.Hint("Закрыть настройки")
            imgui.Separator()

            local tabs = { u8 "Общее", u8 "Фермы", u8 "Авто", u8 "Прочее" }
            if cfg.debug then
                table.insert(tabs, u8 "Отладка")
            end

            local tabCount = #tabs
            local tabW = (winW - imStyle.WindowPadding.x * 2 - imStyle.ItemSpacing.x * (tabCount - 1)) / tabCount

            if data.settingsTab >= tabCount then
                data.settingsTab = 0
            end

            for i, label in ipairs(tabs) do
                if i > 1 then imgui.SameLine(0, imStyle.ItemSpacing.x) end
                imgui.PushStyleColor(imgui.Col.Button,
                    data.settingsTab == i - 1
                    and imgui.ImVec4(0.15, 0.22, 0.35, 1)
                    or imgui.ImVec4(0.09, 0.10, 0.14, 1))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.25, 0.40, 1))
                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.20, 0.28, 0.45, 1))
                if imgui.Button(label, imgui.ImVec2(tabW, 26)) then
                    data.settingsTab = i - 1
                end
                imgui.PopStyleColor(3)
            end
            imgui.Separator()
            imgui.Spacing()

            imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.07, 0.08, 0.11, 1))
            do
                imgui.Scroller("settings_scroll", 30, 300,
                    imgui.HoveredFlags.RectOnly + imgui.HoveredFlags.ChildWindows)

                -- Вкладка 0: Общее
                if data.settingsTab == 0 then
                    if imgui.Checkbox(u8 "Тихий режим", imcfg.silentMode) then
                        cfg.silentMode = imcfg.silentMode[0]; save()
                    end
                    imgui.Hint("Отключает все сообщения скрипта в чат.")

                    if imgui.Checkbox(u8 "Старый вид (диалог SAMP)", imcfg.useDialogMode) then
                        cfg.useDialogMode = imcfg.useDialogMode[0]; save()
                        if cfg.useDialogMode then
                            sampSendChat('/flashminer')
                            data.showLogsWindow[0] = false
                            data.showSettingsWindow[0] = false
                        end
                    end
                    imgui.Hint("Добавляет пункты в стандартный диалог SAMP вместо отдельного окна.")

                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()

                    if imgui.Checkbox(u8 "Проверять обновления при запуске", imcfg.checkForUpdates) then
                        cfg.checkForUpdates = imcfg.checkForUpdates[0]; save()
                    end
                    imgui.Hint("Автоматически проверять наличие новых версий скрипта при запуске.\n")

                    if updateState.hasUpdate then
                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 0.85, 0.2, 1.0))
                        if imgui.Selectable(fa.ARROW_UP_FROM_BRACKET .. u8(string.format("  Установить обновление %s", updateState.latestVersion or "")), false) then
                            updateState.showPopup[0]   = true
                            data.showSettingsWindow[0] = false
                        end
                        imgui.PopStyleColor()
                        imgui.Hint(
                            "{FFE133}Доступна новая версия скрипта!\n\n" ..
                            "{FFFFFF}Нажмите чтобы открыть окно обновления.\n" ..
                            "{808080}Текущая: " .. script.this.version .. "\n" ..
                            "{808080}Новая: " .. (updateState.latestVersion or "?"))
                    end

                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()

                    if imgui.Selectable(u8 "Просмотр логов", false) then
                        data.showLogsWindow[0] = true
                        data.showSettingsWindow[0] = false
                    end
                    if imgui.Selectable(u8 "Сбросить статистику дохода", false) then
                        data.statsResetConfirm = true
                        data.statsResetTimer   = os.clock()
                    end

                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()

                    if imgui.Selectable(u8 "Перезагрузить скрипт", false) then
                        cfg.isReloaded = true; save(); thisScript():reload()
                    end
                    if imgui.Selectable(u8 "Сбросить все настройки", false) then
                        data.settingsResetConfirm = true
                        data.settingsResetTimer   = os.clock()
                    end
                    imgui.Spacing()
                    imgui.TextDisabled(u8("v" .. script.this.version))

                    -- Вкладка 1: Фермы
                elseif data.settingsTab == 1 then
                    if not cfg.useDialogMode and not data.isRodina then
                        imgui.TextColoredRGB("{87CEFA}Баланс дома:")
                        imgui.PushItemWidth(-1)
                        if imgui.SliderInt("##targetBalance", imcfg.targetHouseBalance, 5000000, 60000000,
                                u8("$" .. utils.formatNumber(imcfg.targetHouseBalance[0]))) then
                            local v = math.floor(imcfg.targetHouseBalance[0] / 100000 + 0.5) * 100000
                            cfg.targetHouseBalance = v; imcfg.targetHouseBalance[0] = v; save()
                        end
                        imgui.PopItemWidth()
                        imgui.Hint("Пополнять дом если баланс упадёт ниже этого значения.")

                        if imgui.Checkbox(u8 "Только пополнение баланса", imcfg.useSimpleTopUp) then
                            cfg.useSimpleTopUp = imcfg.useSimpleTopUp[0]; save()
                        end
                        imgui.Hint("Кнопка обслуживания только пополнит баланс.")

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Охлаждение:")
                        imgui.PushItemWidth(-1)
                        if imgui.SliderInt("##coolantPercentSettings", imcfg.useCoolantPercent, 1, 100, u8 "%d%%") then
                            cfg.useCoolantPercent = imcfg.useCoolantPercent[0]; save()
                        end
                        imgui.PopItemWidth()
                        imgui.Hint("Заливать если уровень ниже этого порога.")

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Автоматизация стойки:")

                        if imgui.Checkbox(u8 "Авто-заливка при открытии стойки", imcfg.fixCoolantEnabled) then
                            cfg.fixCoolantEnabled = imcfg.fixCoolantEnabled[0]; save()
                        end
                        imgui.Hint(
                            "Автоматически заливать жидкость при открытии стойки видеокарт.\nНе работает через Флешку Майнера.")

                        if imgui.Checkbox(u8 "Авто-включение карт после заливки", imcfg.autoEnableCards) then
                            cfg.autoEnableCards = imcfg.autoEnableCards[0]
                            if cfg.autoEnableCards then
                                cfg.autoEnableCardsOnOpen = false; imcfg.autoEnableCardsOnOpen[0] = false
                            end
                            save()
                        end
                        imgui.Hint(
                            "После заливки жидкости автоматически включать выключенные карты.\nНе совместимо с 'Авто-включение при открытии стойки'.")

                        if imgui.Checkbox(u8 "Авто-включение карт при открытии стойки", imcfg.autoEnableCardsOnOpen) then
                            cfg.autoEnableCardsOnOpen = imcfg.autoEnableCardsOnOpen[0]
                            if cfg.autoEnableCardsOnOpen then
                                cfg.autoEnableCards = false; imcfg.autoEnableCards[0] = false
                            end
                            save()
                        end
                        imgui.Hint(
                            "Включать выключенные карты при открытии стойки,\n" ..
                            "независимо от заливки жидкости.\n" ..
                            "Не совместимо с 'Авто-включение после заливки'.\n")

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Предупреждения:")
                        imgui.Text(u8 "Порог баланса (предупреждение):")
                        imgui.PushItemWidth(-1)
                        if imgui.SliderInt("##minBalanceWarning", imcfg.minBalanceWarning, 1000000, 15000000,
                                u8("$" .. utils.formatNumber(imcfg.minBalanceWarning[0]))) then
                            local v = math.floor(imcfg.minBalanceWarning[0] / 500000 + 0.5) * 500000
                            cfg.minBalanceWarning = v; imcfg.minBalanceWarning[0] = v; save()
                        end
                        imgui.PopItemWidth()
                        imgui.Hint("Карточка дома станет жёлтой если баланс ниже этого значения.")

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Сбор крипты:")
                        imgui.Text(u8 "Собирать если накопилось не менее:")
                        imgui.PushItemWidth(-1)
                        if imgui.SliderInt("##collectOnlyIfMin", imcfg.collectOnlyIfMin, 0, 180,
                                imcfg.collectOnlyIfMin[0] == 0
                                and u8 "Любое кол-во"
                                or u8(string.format("от %d BTC", imcfg.collectOnlyIfMin[0]))) then
                            cfg.collectOnlyIfMin = imcfg.collectOnlyIfMin[0]; save()
                        end
                        imgui.PopItemWidth()
                        imgui.Hint(
                            "0 = собирать всегда (от 1 BTC).\nПри сборе пропускать дома где меньше N BTC.\n" ..
                            "Учтите, что если на ферме будет например 5 карт,\n"..
                            "а значение стоит на 180, то этот дом никогда не будет собираться.")

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        if imgui.Selectable(u8 "Проверить подвалы", false) then
                            if not data.working then
                                local task = buildTaskTable('scanBasements')
                                runTaskAndReopenDialog(function() task:run(nil) end)
                                data.showSettingsWindow[0] = false
                            else
                                utils.addChat("{F78181}Дождитесь завершения текущей операции.")
                            end
                        end
                        imgui.Hint("Сканирование домов на наличие подвала.")
                    else
                        imgui.Spacing()
                        imgui.TextColoredRGB("{808080}Недоступно в текущем режиме.")
                    end

                    -- Вкладка 2: Автосбор + Уведомления
                elseif data.settingsTab == 2 then
                    if not cfg.useDialogMode and not data.isRodina then
                        imgui.TextColoredRGB("{FF6B6B}Авто")

                        if imgui.Checkbox(u8 "Включить авто-функции", imcfg.cheatModeEnabled) then
                            cfg.cheatModeEnabled = imcfg.cheatModeEnabled[0]
                            if not cfg.cheatModeEnabled then
                                cfg.autoCollectEnabled = false; imcfg.autoCollectEnabled[0] = false
                                cfg.smartCollectEnabled = false; imcfg.smartCollectEnabled[0] = false
                                cfg.autoPayTaxesEnabled = false; imcfg.autoPayTaxesEnabled[0] = false
                                cfg.autoTopUpEnabled = false; imcfg.autoTopUpEnabled[0] = false
                            end
                            save()
                        end
                        imgui.Hint(
                            "{FF6B6B} ВНИМАНИЕ!\n" ..
                            "Эти функции могут быть запрещены на вашем сервере!\n" ..
                            "Перед использованием уточните у администрации,\n" ..
                            "не нарушает ли это правила сервера.\n\n" ..
                            "Используйте на свой страх и риск.\n" ..
                            "Автор не несёт ответственности за блокировки\n" ..
                            "или иные проблемы, связанные с их использованием.\n\n")

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        do
                            local subTabs = { u8 "Автосбор", u8 "Финансы", u8 "Уведомления" }
                            local subTabCount = #subTabs
                            local subTabW = (winW - imStyle.WindowPadding.x * 2 - imStyle.ItemSpacing.x * (subTabCount - 1)) /
                                subTabCount

                            for si, slabel in ipairs(subTabs) do
                                if si > 1 then imgui.SameLine(0, imStyle.ItemSpacing.x) end
                                imgui.PushStyleColor(imgui.Col.Button,
                                    data.cheatSubTab == si - 1
                                    and imgui.ImVec4(0.18, 0.28, 0.45, 1)
                                    or imgui.ImVec4(0.11, 0.12, 0.16, 1))
                                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.30, 0.48, 1))
                                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.22, 0.32, 0.50, 1))
                                if imgui.Button(slabel .. "##cheatSub", imgui.ImVec2(subTabW, 30)) then
                                    data.cheatSubTab = si - 1
                                end
                                imgui.PopStyleColor(3)
                            end
                            imgui.Spacing()

                            if data.cheatSubTab == 0 then
                                if not cfg.cheatModeEnabled then
                                    imgui.Spacing()
                                    imgui.TextColoredRGB(
                                        "{808080}Недоступно. Включите авто-функции выше.")
                                else
                                    imgui.TextColoredRGB("{87CEFA}Автосбор по расписанию")

                                    if imgui.Checkbox(u8 "Включить автосбор по расписанию", imcfg.autoCollectEnabled) then
                                        cfg.autoCollectEnabled = imcfg.autoCollectEnabled[0]
                                        if cfg.autoCollectEnabled then
                                            cfg.smartCollectEnabled = false; imcfg.smartCollectEnabled[0] = false
                                            cfg.reminderEnabled = false; imcfg.reminderEnabled[0] = false
                                        end
                                        save()
                                    end
                                    imgui.Hint("Собирать крипту через равные промежутки времени.")

                                    if cfg.autoCollectEnabled then
                                        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.10, 0.11, 0.15, 1))
                                        imgui.BeginChild("##autoCSub", imgui.ImVec2(0, 100), true,
                                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                                        imgui.PushItemWidth(-1)
                                        if imgui.SliderInt("##cTimes", imcfg.collectTimesPerDay, 1, 8,
                                                u8(string.format("%d/день (~%s)", imcfg.collectTimesPerDay[0],
                                                    formatTimeLeft(math.floor(86400 / math.max(1, imcfg.collectTimesPerDay[0])))))) then
                                            cfg.collectTimesPerDay = imcfg.collectTimesPerDay[0]
                                            collectTool.resetPendingDelay()
                                            save()
                                        end
                                        imgui.PopItemWidth()
                                        local tL = collectTool.getTimeUntil()
                                        if data.pendingCollectLocked then
                                            local pLeft = data.pendingCollectAt - os.time()
                                            if pLeft > 0 then
                                                imgui.TextColoredRGB(string.format(
                                                    "{FFE133}Рандомная задержка: %s",
                                                    formatTimeLeft(pLeft)))
                                            end
                                        end
                                        if tL > 0 then
                                            imgui.TextColoredRGB(string.format("{808080}До сбора: {FFFFFF}%s",
                                                formatTimeLeft(tL)))
                                        end
                                        if imgui.Selectable(u8 "Сбросить таймер", false) then
                                            cfg.lastCollectTime = os.time()
                                            collectTool.resetPendingDelay()
                                            save()
                                        end
                                        imgui.EndChild()
                                        imgui.PopStyleColor()
                                    end

                                    imgui.Spacing()

                                    imgui.TextColoredRGB("{87CEFA}Умный автосбор")

                                    if imgui.Checkbox(u8 "Включить умный автосбор", imcfg.smartCollectEnabled) then
                                        cfg.smartCollectEnabled = imcfg.smartCollectEnabled[0]
                                        if cfg.smartCollectEnabled then
                                            cfg.autoCollectEnabled = false; imcfg.autoCollectEnabled[0] = false
                                            cfg.reminderEnabled = false; imcfg.reminderEnabled[0] = false
                                        end
                                        save()
                                    end
                                    imgui.Hint("Собирать когда накопится заданное кол-во BTC.")

                                    if cfg.smartCollectEnabled then
                                        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.10, 0.11, 0.15, 1))
                                        imgui.BeginChild("##smartCSub", imgui.ImVec2(0, 90), true,
                                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                                        local hc = math.max(1, #data.dialogData.flashminer)
                                        local sMin, sMax = hc * 20, hc * 20 * 8
                                        if imcfg.smartCollectTarget[0] < sMin then
                                            imcfg.smartCollectTarget[0] = sMin; cfg.smartCollectTarget = sMin
                                        end
                                        imgui.PushItemWidth(-1)
                                        if imgui.SliderInt("##sTgt", imcfg.smartCollectTarget, sMin, sMax,
                                                u8(string.format("при %d BTC", imcfg.smartCollectTarget[0]))) then
                                            cfg.smartCollectTarget = imcfg.smartCollectTarget[0]
                                            collectTool.resetPendingDelay()
                                            save()
                                        end
                                        imgui.PopItemWidth()
                                        local sB, sD, sOk = 0, 0, false
                                        for _, h in ipairs(data.dialogData.flashminer) do
                                            if not houseFilter.shouldSkip(h.house_number) then
                                                local st = data.houseStatuses[h.house_number]
                                                if st and st.lastCheck > 0 then
                                                    sOk = true
                                                    sB = sB + (st.earnings and st.earnings.btc or 0) +
                                                        houseFilter.getDailyIncome(h.house_number) *
                                                        ((os.time() - st.lastCheck) / 86400)
                                                    sD = sD + houseFilter.getDailyIncome(h.house_number)
                                                end
                                            end
                                        end
                                        if sOk and sD > 0 then
                                            local sHL = math.max(0, (cfg.smartCollectTarget - sB) / (sD / 24))
                                            imgui.TextColoredRGB(string.format(
                                                "{808080}Накоплено: {BEF781}%d {808080}/ {FFFFFF}%d BTC",
                                                math.floor(sB), cfg.smartCollectTarget))
                                            if data.pendingCollectLocked then
                                                local pLeft = data.pendingCollectAt - os.time()
                                                if pLeft > 0 then
                                                    imgui.TextColoredRGB(string.format(
                                                        "{FFE133}Рандомная задержка: %s",
                                                        formatTimeLeft(pLeft)))
                                                end
                                            end
                                            imgui.TextColoredRGB(string.format("{808080}Сбор через: {FFFFFF}%s",
                                                sHL <= 0 and "уже пора!" or formatTimeLeft(math.floor(sHL * 3600))))
                                        else
                                            imgui.TextColoredRGB(sOk and "{808080}Нет данных о доходе." or
                                                "{808080}Откройте /flashminer.")
                                        end
                                        imgui.EndChild()
                                        imgui.PopStyleColor()
                                    end

                                    imgui.Spacing()

                                    if cfg.autoCollectEnabled or cfg.smartCollectEnabled then
                                        if imgui.Checkbox(u8 "Включать карты после автосбора", imcfg.autoEnableCardsOnCollect) then
                                            cfg.autoEnableCardsOnCollect = imcfg.autoEnableCardsOnCollect[0]; save()
                                        end
                                        imgui.Hint("Включать выключенные карты сразу после сбора крипты.")
                                    end

                                    imgui.Spacing()
                                    imgui.Separator()
                                    imgui.Spacing()

                                    imgui.TextColoredRGB("{87CEFA}Рандомная задержка")

                                    if imgui.Checkbox(u8 "Добавлять рандомную задержку", imcfg.randomDelayEnabled) then
                                        cfg.randomDelayEnabled = imcfg.randomDelayEnabled[0]
                                        if not cfg.randomDelayEnabled then
                                            data.pendingCollectLocked = false
                                            data.pendingCollectAt = 0
                                        end
                                        save()
                                    end
                                    imgui.Hint(
                                        "Добавляет случайную задержку перед автосбором.")

                                    if cfg.randomDelayEnabled then
                                        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.10, 0.11, 0.15, 1))
                                        imgui.BeginChild("##rndDelaySub", imgui.ImVec2(0, 80), true,
                                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                                        imgui.PushItemWidth(-1)
                                        if imgui.SliderInt("##rndMin", imcfg.randomDelayMin, 1, imcfg.randomDelayMax[0],
                                                u8(string.format("от %d мин.", imcfg.randomDelayMin[0]))) then
                                            cfg.randomDelayMin = imcfg.randomDelayMin[0]
                                            if cfg.randomDelayMin > cfg.randomDelayMax then
                                                cfg.randomDelayMax = cfg.randomDelayMin
                                                imcfg.randomDelayMax[0] = cfg.randomDelayMax
                                            end
                                            collectTool.resetPendingDelay()
                                            save()
                                        end
                                        if imgui.SliderInt("##rndMax", imcfg.randomDelayMax, imcfg.randomDelayMin[0], 180,
                                                u8(string.format("до %d мин.", imcfg.randomDelayMax[0]))) then
                                            cfg.randomDelayMax = imcfg.randomDelayMax[0]
                                            if cfg.randomDelayMax < cfg.randomDelayMin then
                                                cfg.randomDelayMin = cfg.randomDelayMax
                                                imcfg.randomDelayMin[0] = cfg.randomDelayMin
                                            end
                                            collectTool.resetPendingDelay()
                                            save()
                                        end
                                        imgui.PopItemWidth()
                                        if data.pendingCollectLocked then
                                            local pLeft = data.pendingCollectAt - os.time()
                                            if pLeft > 0 then
                                                imgui.TextColoredRGB(string.format("{FFE133}Задержка: %s",
                                                    formatTimeLeft(pLeft)))
                                            end
                                        end
                                        imgui.EndChild()
                                        imgui.PopStyleColor()
                                    end

                                    imgui.Spacing()
                                    imgui.Separator()
                                    imgui.Spacing()

                                    imgui.TextColoredRGB("{87CEFA}Фоновое обновление статусов")

                                    if imgui.Checkbox(u8 "Периодически обновлять данные домов", imcfg.autoRefreshEnabled) then
                                        cfg.autoRefreshEnabled = imcfg.autoRefreshEnabled[0]; save()
                                    end
                                    imgui.Hint(
                                        "Автоматически обновлять статусы домов в фоне.\n" ..
                                        "Необходимо для корректной работы умного автосбора\n" ..
                                        "и автосбора без ручного открытия /flashminer.\n\n" ..
                                        "{808080}Вызывает /flashminer и обновляет данные.")

                                    if cfg.autoRefreshEnabled then
                                        local refreshChildH = 100
                                        if cfg.refreshPostponeOnDialog then refreshChildH = 140 end

                                        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.10, 0.11, 0.15, 1))
                                        imgui.BeginChild("##refreshSub", imgui.ImVec2(0, refreshChildH), true,
                                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                                        imgui.PushItemWidth(-1)
                                        if imgui.SliderInt("##refreshInt", imcfg.autoRefreshInterval, 10, 120,
                                                u8(string.format("каждые %d мин.", imcfg.autoRefreshInterval[0]))) then
                                            cfg.autoRefreshInterval = imcfg.autoRefreshInterval[0]; save()
                                        end

                                        local refLeft = (cfg.lastAutoRefreshTime + cfg.autoRefreshInterval * 60) -
                                            os.time()
                                        imgui.TextColoredRGB(refLeft > 0
                                            and string.format("{808080}До обновления: {FFFFFF}%s",
                                                formatTimeLeft(refLeft))
                                            or "{BEF781}При следующей проверке!")

                                        imgui.PopItemWidth()

                                        if imgui.Checkbox(u8 "Не прерывать открытый диалог",
                                                imcfg.refreshPostponeOnDialog) then
                                            cfg.refreshPostponeOnDialog = imcfg.refreshPostponeOnDialog[0]; save()
                                        end
                                        imgui.Hint(
                                            "Если у вас открыт любой диалог в момент обновления —\n" ..
                                            "отложить обновление, чтобы не сбить ваше взаимодействие.\n")

                                        if cfg.refreshPostponeOnDialog then
                                            imgui.PushItemWidth(-1)
                                            if imgui.SliderInt("##refreshPostpone", imcfg.refreshPostponeMinutes, 1, 5,
                                                    u8(string.format("отложить на %d мин.", imcfg.refreshPostponeMinutes[0]))) then
                                                cfg.refreshPostponeMinutes = imcfg.refreshPostponeMinutes[0]; save()
                                            end
                                            imgui.PopItemWidth()
                                        end

                                        local postponed = autoRefreshTool.getPostponedUntil()
                                        if postponed > os.time() then
                                            imgui.TextColoredRGB(string.format(
                                                "{FFE133}Отложено: {FFFFFF}%s",
                                                formatTimeLeft(postponed - os.time())))
                                        end

                                        imgui.EndChild()
                                        imgui.PopStyleColor()
                                    end
                                end -- end else cheatModeEnabled (subtab 0)
                            elseif data.cheatSubTab == 1 then
                                if not cfg.cheatModeEnabled then
                                    imgui.Spacing()
                                    imgui.TextColoredRGB(
                                        "{808080}Недоступно. Включите авто-функции выше.")
                                else
                                    imgui.TextColoredRGB("{87CEFA}Автооплата налогов")

                                    if imgui.Checkbox(u8 "Включить автооплату налогов", imcfg.autoPayTaxesEnabled) then
                                        cfg.autoPayTaxesEnabled = imcfg.autoPayTaxesEnabled[0]; save()
                                    end
                                    imgui.Hint(
                                        "Автоматическая оплата всех налогов.\n" ..
                                        "{FFE133}Требуется ADD VIP.")

                                    if cfg.autoPayTaxesEnabled then
                                        local taxChildH = 85
                                        if cfg.autoPayTaxesByTimer then taxChildH = 135 end

                                        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.10, 0.11, 0.15, 1))
                                        imgui.BeginChild("##taxSub", imgui.ImVec2(0, taxChildH), true,
                                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

                                        if imgui.Checkbox(u8 "Вместе с автосбором", imcfg.autoPayTaxesWithCollect) then
                                            cfg.autoPayTaxesWithCollect = imcfg.autoPayTaxesWithCollect[0]
                                            if cfg.autoPayTaxesWithCollect then
                                                cfg.autoPayTaxesByTimer = false; imcfg.autoPayTaxesByTimer[0] = false
                                            end
                                            save()
                                        end
                                        imgui.Hint("Оплачивать налоги после каждого автосбора крипты.")

                                        if imgui.Checkbox(u8 "По таймеру", imcfg.autoPayTaxesByTimer) then
                                            cfg.autoPayTaxesByTimer = imcfg.autoPayTaxesByTimer[0]
                                            if cfg.autoPayTaxesByTimer then
                                                cfg.autoPayTaxesWithCollect = false; imcfg.autoPayTaxesWithCollect[0] = false
                                            end
                                            save()
                                        end
                                        imgui.Hint("Оплачивать налоги через заданный интервал.")

                                        if cfg.autoPayTaxesByTimer then
                                            imgui.PushItemWidth(-1)
                                            if imgui.SliderInt("##taxInt", imcfg.autoPayTaxesInterval, 1, 48,
                                                    u8(string.format("каждые %d ч.", imcfg.autoPayTaxesInterval[0]))) then
                                                cfg.autoPayTaxesInterval = imcfg.autoPayTaxesInterval[0]; save()
                                            end
                                            imgui.PopItemWidth()
                                            local taxLeft = (cfg.lastTaxPayTime + cfg.autoPayTaxesInterval * 3600) -
                                                os.time()
                                            imgui.TextColoredRGB(taxLeft > 0
                                                and string.format("{808080}До оплаты: {FFFFFF}%s",
                                                    formatTimeLeft(taxLeft))
                                                or "{BEF781}Оплата при следующей проверке!")
                                        end

                                        imgui.EndChild()
                                        imgui.PopStyleColor()
                                    end

                                    imgui.Spacing()
                                    imgui.Separator()
                                    imgui.Spacing()

                                    imgui.TextColoredRGB("{87CEFA}Автопополнение баланса")

                                    if imgui.Checkbox(u8 "Включить автопополнение", imcfg.autoTopUpEnabled) then
                                        cfg.autoTopUpEnabled = imcfg.autoTopUpEnabled[0]; save()
                                    end
                                    imgui.Hint(
                                        "Пополнять баланс домов до целевого значения.\n" ..
                                        "{808080}Целевой баланс — на вкладке 'Фермы'.")

                                    if cfg.autoTopUpEnabled then
                                        local topUpChildH = 150
                                        if cfg.autoTopUpByThreshold then topUpChildH = topUpChildH + 28 end
                                        if cfg.autoTopUpByTimer then topUpChildH = topUpChildH + 48 end

                                        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.10, 0.11, 0.15, 1))
                                        imgui.BeginChild("##topUpSub", imgui.ImVec2(0, topUpChildH), true,
                                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

                                        imgui.TextColoredRGB(string.format("{808080}Цель: {FFD700}$%s",
                                            utils.formatNumber(cfg.targetHouseBalance)))
                                        imgui.Spacing()

                                        if imgui.Checkbox(u8 "Вместе с автосбором", imcfg.autoTopUpWithCollect) then
                                            cfg.autoTopUpWithCollect = imcfg.autoTopUpWithCollect[0]
                                            if cfg.autoTopUpWithCollect then
                                                cfg.autoTopUpByTimer = false; imcfg.autoTopUpByTimer[0] = false
                                                cfg.autoTopUpByThreshold = false; imcfg.autoTopUpByThreshold[0] = false
                                            end
                                            save()
                                        end
                                        imgui.Hint("Пополнять после каждого автосбора крипты.")

                                        if imgui.Checkbox(u8 "При низком балансе", imcfg.autoTopUpByThreshold) then
                                            cfg.autoTopUpByThreshold = imcfg.autoTopUpByThreshold[0]
                                            if cfg.autoTopUpByThreshold then
                                                cfg.autoTopUpWithCollect = false; imcfg.autoTopUpWithCollect[0] = false
                                                cfg.autoTopUpByTimer = false; imcfg.autoTopUpByTimer[0] = false
                                            end
                                            save()
                                        end
                                        imgui.Hint("Пополнять когда баланс любого дома упадёт ниже порога.")

                                        if cfg.autoTopUpByThreshold then
                                            imgui.PushItemWidth(-1)
                                            if imgui.SliderInt("##topUpThr", imcfg.autoTopUpThreshold, 500000, 20000000,
                                                    u8("$" .. utils.formatNumber(imcfg.autoTopUpThreshold[0]))) then
                                                local v = math.floor(imcfg.autoTopUpThreshold[0] / 100000 + 0.5) * 100000
                                                cfg.autoTopUpThreshold = v; imcfg.autoTopUpThreshold[0] = v; save()
                                            end
                                            imgui.PopItemWidth()
                                        end

                                        if imgui.Checkbox(u8 "По таймеру", imcfg.autoTopUpByTimer) then
                                            cfg.autoTopUpByTimer = imcfg.autoTopUpByTimer[0]
                                            if cfg.autoTopUpByTimer then
                                                cfg.autoTopUpWithCollect = false; imcfg.autoTopUpWithCollect[0] = false
                                                cfg.autoTopUpByThreshold = false; imcfg.autoTopUpByThreshold[0] = false
                                            end
                                            save()
                                        end
                                        imgui.Hint("Пополнять баланс через заданный интервал.")

                                        if cfg.autoTopUpByTimer then
                                            imgui.PushItemWidth(-1)
                                            if imgui.SliderInt("##topUpInt", imcfg.autoTopUpTimerInterval, 1, 48,
                                                    u8(string.format("каждые %d ч.", imcfg.autoTopUpTimerInterval[0]))) then
                                                cfg.autoTopUpTimerInterval = imcfg.autoTopUpTimerInterval[0]; save()
                                            end
                                            imgui.PopItemWidth()
                                            local tuLeft = (cfg.lastAutoTopUpTime + cfg.autoTopUpTimerInterval * 3600) -
                                                os.time()
                                            imgui.TextColoredRGB(tuLeft > 0
                                                and string.format("{808080}До пополнения: {FFFFFF}%s",
                                                    formatTimeLeft(tuLeft))
                                                or "{BEF781}При следующей проверке!")
                                        end

                                        imgui.EndChild()
                                        imgui.PopStyleColor()
                                    end
                                end -- end else cheatModeEnabled (subtab 1)
                            elseif data.cheatSubTab == 2 then
                                imgui.TextColoredRGB("{87CEFA}Напоминания")

                                local blockReminder = cfg.cheatModeEnabled
                                    and (cfg.autoCollectEnabled or cfg.smartCollectEnabled)

                                if blockReminder then
                                    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.5, 0.5, 0.5, 1))
                                    imgui.PushStyleColor(imgui.Col.CheckMark, imgui.ImVec4(0.5, 0.5, 0.5, 1))
                                    imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.10, 0.10, 0.10, 1))
                                    imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(0.10, 0.10, 0.10, 1))
                                    local dummy = imgui.new.bool(false)
                                    imgui.Checkbox(u8 "Напоминание о BTC", dummy)
                                    imgui.PopStyleColor(4)
                                    imgui.Hint(
                                        "Недоступно пока включён автосбор\nили умный автосбор.")
                                else
                                    if imgui.Checkbox(u8 "Напоминание о BTC", imcfg.reminderEnabled) then
                                        cfg.reminderEnabled = imcfg.reminderEnabled[0]; save()
                                    end
                                    imgui.Hint(
                                        "Показывать окно при достижении порога BTC.")
                                end

                                if cfg.reminderEnabled and not blockReminder then
                                    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.10, 0.11, 0.15, 1))
                                    imgui.BeginChild("##remSub", imgui.ImVec2(0, 140), true,
                                        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                                    local estBtc, hasData = estimateTotalBTC()
                                    if hasData then
                                        local fr = math.min(estBtc / math.max(cfg.btcThreshold, 1), 1.0)
                                        local c = fr >= 1.0 and "{BEF781}" or (fr >= 0.7 and "{FFE133}" or "{FF6B6B}")
                                        imgui.TextColoredRGB(string.format(
                                            "{808080}Сейчас: %s%d {808080}/ {FFFFFF}%d BTC",
                                            c, math.floor(estBtc), cfg.btcThreshold))
                                    end
                                    imgui.PushItemWidth(-1)
                                    if imgui.SliderInt("##btcThr", imcfg.btcThreshold, 10, 2000,
                                            u8(string.format("порог: %d BTC", imcfg.btcThreshold[0]))) then
                                        cfg.btcThreshold = imcfg.btcThreshold[0]; save()
                                    end
                                    if imgui.SliderInt("##remInt", imcfg.reminderInterval, 1, 60,
                                            u8(string.format("каждые %d мин.", imcfg.reminderInterval[0]))) then
                                        cfg.reminderInterval = imcfg.reminderInterval[0]; save()
                                    end
                                    if imgui.SliderInt("##nDur", imcfg.notifyShowDuration, 3, 30,
                                            u8(string.format("показывать %d сек.", imcfg.notifyShowDuration[0]))) then
                                        cfg.notifyShowDuration = imcfg.notifyShowDuration[0]; save()
                                    end
                                    imgui.Hint("Как долго показывать всплывающее\nуведомление.")
                                    imgui.PopItemWidth()
                                    imgui.EndChild()
                                    imgui.PopStyleColor()
                                end

                                if cfg.cheatModeEnabled then
                                    imgui.Spacing()
                                    imgui.Separator()
                                    imgui.Spacing()

                                    imgui.TextColoredRGB("{87CEFA}Окно уведомлений:")
                                    if imgui.Checkbox(u8 "Уведомления автосбора", imcfg.notifyAutoCollectEnabled) then
                                        cfg.notifyAutoCollectEnabled = imcfg.notifyAutoCollectEnabled[0]; save()
                                    end
                                    imgui.Hint(
                                        "Показывать окно уведомлений для автосбора\nи умного автосбора (обратный отсчёт, статус сбора).")

                                    imgui.PushItemWidth(-1)
                                    if imgui.SliderInt("##nBefore", imcfg.notifyBeforeSec, 30, 600,
                                            u8(string.format("за %d сек.", imcfg.notifyBeforeSec[0]))) then
                                        cfg.notifyBeforeSec = imcfg.notifyBeforeSec[0]; save()
                                    end
                                    imgui.Hint("За сколько секунд до автосбора показывать\nокно с обратным отсчётом.")

                                    imgui.PopItemWidth()
                                    imgui.Spacing()
                                    imgui.Separator()
                                    imgui.TextColoredRGB("{87CEFA}Предпросмотр")
                                    if imgui.Selectable(u8 "Предпросмотр окна", false) then
                                        data.notifyWindow.btcAmount  = 150
                                        data.notifyWindow.mode       = 'reminder'
                                        data.notifyWindow.autoHideAt = os.time() + cfg.notifyShowDuration
                                        data.notifyWindow.isPreview  = true
                                        data.notifyWindow.show[0]    = true
                                    end
                                    imgui.Hint(
                                        "Показать пример окна уведомления.\nПеретащите его мышью — позиция\nавтоматически сохранится.\nСпустя несколько секунд окно пропадёт.")
                                end
                            end
                        end
                    else
                        imgui.Spacing()
                        imgui.TextColoredRGB("{808080}Недоступно в текущем режиме.")
                    end
                elseif data.settingsTab == 3 then
                    if imgui.Checkbox(u8 "Пауза на PayDay", imcfg.pauseOnPayday) then
                        cfg.pauseOnPayday = imcfg.pauseOnPayday[0]; save()
                    end
                    imgui.Hint("Делать паузу во время PayDay.")

                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()

                    imgui.TextColoredRGB("{87CEFA}Ожидание подключения:")

                    if imgui.Checkbox(u8 "Ждать подключения к серверу", imcfg.waitForConnection) then
                        cfg.waitForConnection = imcfg.waitForConnection[0]; save()
                    end
                    imgui.Hint(
                        "Если вы не подключены к серверу — все автодействия\n" ..
                        "приостанавливаются до момента подключения.\n\n" ..
                        "После подключения ждём указанное ниже время,\n" ..
                        "прежде чем возобновить автодействия.")

                    if cfg.waitForConnection then
                        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.10, 0.11, 0.15, 1))
                        imgui.BeginChild("##connSub", imgui.ImVec2(0, 70), true,
                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                        imgui.PushItemWidth(-1)
                        if imgui.SliderInt("##delayAfterConnect", imcfg.delayAfterConnectMin, 5, 20,
                                u8(string.format("задержка %d мин. после подключения",
                                    imcfg.delayAfterConnectMin[0]))) then
                            cfg.delayAfterConnectMin = imcfg.delayAfterConnectMin[0]; save()
                        end
                        imgui.PopItemWidth()

                        if data.connectionState.connected then
                            local waitLeft = data.connectionState.readyAfterConnect - os.time()
                            if waitLeft > 0 then
                                imgui.TextColoredRGB(string.format(
                                    "{FFE133}Активация через: {FFFFFF}%s", formatTimeLeft(waitLeft)))
                            else
                                imgui.TextColoredRGB("{BEF781}Статус: подключён")
                            end
                        else
                            imgui.TextColoredRGB("{FF6B6B}Статус: не в игре")
                        end

                        imgui.EndChild()
                        imgui.PopStyleColor()
                    end

                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()

                    imgui.TextColoredRGB("{87CEFA}Скорость диалогов:")
                    imgui.PushItemWidth(-1)
                    if imgui.SliderInt("##pause", imcfg.pause_duration, 150, 300, u8 "%d мс") then
                        cfg.pause_duration = imcfg.pause_duration[0]; save()
                    end
                    imgui.Hint("Пауза между диалогами.")
                    if imgui.SliderInt("##count", imcfg.count_action, 1, 20,
                            u8(string.format("пауза каждые %d", imcfg.count_action[0]))) then
                        cfg.count_action = imcfg.count_action[0]; save()
                    end
                    imgui.Hint("Количество взаимодействий с диалогами до паузы.")
                    imgui.PopItemWidth()

                    -- Вкладка 4: Отладка
                elseif data.settingsTab == 4 and cfg.debug then
                    imgui.TextColoredRGB("{FFE133}Инструменты отладки")
                    imgui.Spacing()

                    local dbgTabs = { u8 "Таймеры", u8 "Состояние", u8 "Действия" }
                    local dbgCount = #dbgTabs
                    local dbgW = (winW - imStyle.WindowPadding.x * 2 - imStyle.ItemSpacing.x * (dbgCount - 1)) / dbgCount
                    for di, dl in ipairs(dbgTabs) do
                        if di > 1 then imgui.SameLine(0, imStyle.ItemSpacing.x) end
                        imgui.PushStyleColor(imgui.Col.Button,
                            data.debugSubTab == di - 1
                            and imgui.ImVec4(0.18, 0.28, 0.45, 1)
                            or imgui.ImVec4(0.11, 0.12, 0.16, 1))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.30, 0.48, 1))
                        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.22, 0.32, 0.50, 1))
                        if imgui.Button(dl .. "##dbgSub", imgui.ImVec2(dbgW, 30)) then
                            data.debugSubTab = di - 1
                        end
                        imgui.PopStyleColor(3)
                    end
                    imgui.Spacing()

                    if data.debugSubTab == 0 then
                        imgui.TextColoredRGB("{87CEFA}Автосбор по расписанию:")
                        for _, sec in ipairs({ 15, 30 }) do
                            if imgui.Selectable(u8(string.format("Сработает через %d сек.", sec)), false) then
                                cfg.lastCollectTime = os.time() - collectTool.getInterval() + sec; save()
                                utils.addChat(string.format("{FFE133}DEBUG: автосбор через %d сек.", sec))
                            end
                        end
                        if imgui.Selectable(u8 "Сбросить таймер (следующий — по расписанию)", false) then
                            cfg.lastCollectTime = os.time()
                            collectTool.resetPendingDelay()
                            save()
                        end
                        if imgui.Selectable(u8 "Запустить сбор немедленно", false) then
                            cfg.lastCollectTime = 0; save()
                        end

                        imgui.Spacing()
                        imgui.TextColoredRGB("{87CEFA}Умный автосбор:")
                        for _, btc in ipairs({ 10, 50, 100 }) do
                            if imgui.Selectable(u8(string.format("Установить цель: %d BTC", btc)), false) then
                                cfg.smartCollectTarget = btc; imcfg.smartCollectTarget[0] = btc
                                cfg.lastCollectTime = 0; save()
                            end
                        end

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Фоновое обновление:")
                        do
                            local refLeft = (cfg.lastAutoRefreshTime + cfg.autoRefreshInterval * 60) - os.time()
                            imgui.TextColoredRGB(string.format("{808080}До обновления: {FFFFFF}%s",
                                refLeft > 0 and formatTimeLeft(refLeft) or "сейчас"))
                            imgui.TextColoredRGB(string.format("{808080}Последнее: {FFFFFF}%s",
                                cfg.lastAutoRefreshTime > 0 and os.date('%H:%M:%S', cfg.lastAutoRefreshTime) or "никогда"))
                        end
                        if imgui.Selectable(u8 "Запустить фоновое обновление сейчас", false) then
                            if not data.working then
                                lua_thread.create(function() autoRefreshTool.runSilent() end)
                            end
                        end
                        for _, sec in ipairs({ 10, 30 }) do
                            if imgui.Selectable(u8(string.format("Обновление через %d сек.", sec)), false) then
                                cfg.lastAutoRefreshTime = os.time() - cfg.autoRefreshInterval * 60 + sec; save()
                            end
                        end

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Рандомная задержка:")
                        imgui.TextColoredRGB(string.format("{808080}Locked: {FFFFFF}%s",
                            tostring(data.pendingCollectLocked)))
                        if data.pendingCollectLocked then
                            local pLeft = data.pendingCollectAt - os.time()
                            imgui.TextColoredRGB(string.format("{808080}Осталось: %s%s",
                                pLeft > 0 and "{FFFFFF}" or "{BEF781}",
                                pLeft > 0 and formatTimeLeft(pLeft) or "сейчас!"))
                        end
                        if imgui.Selectable(u8 "Задержка 15 сек.", false) then
                            data.pendingCollectAt = os.time() + 15; data.pendingCollectLocked = true
                        end
                        if imgui.Selectable(u8 "Задержка 60 сек.", false) then
                            data.pendingCollectAt = os.time() + 60; data.pendingCollectLocked = true
                        end
                        if imgui.Selectable(u8 "Снять задержку (немедленно)", false) then
                            data.pendingCollectAt = os.time() - 1
                            if not data.pendingCollectLocked then data.pendingCollectLocked = true end
                        end
                        if imgui.Selectable(u8 "Отменить задержку", false) then
                            data.pendingCollectLocked = false; data.pendingCollectAt = 0
                        end

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}PayDay:")
                        if imgui.Selectable(u8(string.format("Имитация: %s",
                                data.isWaitingPayday and "остановить" or "запустить")), false) then
                            data.isWaitingPayday = not data.isWaitingPayday; data.skipPayday = false
                        end

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Тест уведомлений:")
                        if imgui.Selectable(u8 "reminder", false) then
                            data.notifyWindow.btcAmount = 250; data.notifyWindow.mode = 'reminder'
                            data.notifyWindow.autoHideAt = os.time() + cfg.notifyShowDuration
                            data.notifyWindow.isPreview = true
                            data.notifyWindow.show[0] = true
                        end
                        if imgui.Selectable(u8 "countdown (30с)", false) then
                            if cfg.notifyAutoCollectEnabled then
                                data.notifyWindow.countdownTarget = os.time() + 30
                                data.notifyWindow.mode = 'countdown'; data.notifyWindow.autoHideAt = 0
                                data.notifyWindow.show[0] = true
                            end
                        end
                        if imgui.Selectable(u8 "collecting", false) then
                            if cfg.notifyAutoCollectEnabled then
                                data.notifyWindow.mode = 'collecting'; data.notifyWindow.autoHideAt = 0
                                data.notifyWindow.show[0] = true
                            end
                        end
                        if imgui.Selectable(u8 "Скрыть", false) then data.notifyWindow.show[0] = false end
                    elseif data.debugSubTab == 1 then
                        imgui.TextColoredRGB("{87CEFA}Текущее состояние:")
                        imgui.TextColoredRGB(string.format("{808080}Задача: {FFFFFF}%s",
                            data.taskTypeNow ~= '' and data.taskTypeNow or "нет"))
                        imgui.TextColoredRGB(string.format("{808080}working: {FFFFFF}%s", tostring(data.working)))
                        imgui.TextColoredRGB(string.format("{808080}isFlashminer: {FFFFFF}%s",
                            tostring(data.isFlashminer)))
                        imgui.TextColoredRGB(string.format("{808080}isRodina: {FFFFFF}%s", tostring(data.isRodina)))
                        imgui.TextColoredRGB(string.format("{808080}Домов: {FFFFFF}%d", #data.dialogData.flashminer))
                        imgui.TextColoredRGB(string.format("{808080}Карт: {FFFFFF}%d", #data.dialogData.videocards))
                        imgui.TextColoredRGB(string.format("{808080}Прогресс: {FFFFFF}%d/%d  %d/%d",
                            data.progressCurrent, data.progressTotal,
                            data.progressHouseCurrent, data.progressHouseTotal))

                        imgui.TextColoredRGB(string.format("{808080}pendingLocked: {FFFFFF}%s",
                            tostring(data.pendingCollectLocked)))
                        if data.pendingCollectLocked then
                            imgui.TextColoredRGB(string.format("{808080}pendingAt: {FFFFFF}%s (%s)",
                                os.date('%H:%M:%S', data.pendingCollectAt),
                                formatTimeLeft(math.max(0, data.pendingCollectAt - os.time()))))
                        end
                        imgui.TextColoredRGB(string.format("{808080}notifyAuto: {FFFFFF}%s",
                            tostring(cfg.notifyAutoCollectEnabled)))
                        imgui.TextColoredRGB(string.format("{808080}autoRefresh: {FFFFFF}%s (%dм)",
                            tostring(cfg.autoRefreshEnabled), cfg.autoRefreshInterval))
                        imgui.TextColoredRGB(string.format("{808080}randomDelay: {FFFFFF}%s (%d-%d)",
                            tostring(cfg.randomDelayEnabled), cfg.randomDelayMin, cfg.randomDelayMax))
                        imgui.TextColoredRGB(string.format("{808080}notifyMode: {FFFFFF}%s",
                            data.notifyWindow.mode ~= '' and data.notifyWindow.mode or "нет"))
                        imgui.TextColoredRGB(string.format("{808080}silent: {FFFFFF}%s", tostring(data.silentWindowOpen)))
                        imgui.TextColoredRGB(string.format("{808080}connected: {FFFFFF}%s",
                            tostring(data.connectionState.connected)))
                        if data.connectionState.readyAfterConnect > os.time() then
                            imgui.TextColoredRGB(string.format("{808080}ready in: {FFE133}%s",
                                formatTimeLeft(data.connectionState.readyAfterConnect - os.time())))
                        end
                        local postponed = autoRefreshTool.getPostponedUntil()
                        if postponed > os.time() then
                            imgui.TextColoredRGB(string.format("{808080}refresh postponed: {FFE133}%s",
                                formatTimeLeft(postponed - os.time())))
                        end
                        imgui.TextColoredRGB(string.format("{808080}scanDone: {FFFFFF}%s",
                            tostring(data.initialScanCompleted)))
                        do
                            local _tl = collectTool.getTimeUntil()
                            imgui.TextColoredRGB(string.format("{808080}До автосбора: {FFFFFF}%s",
                                _tl <= 0 and "уже пора!" or formatTimeLeft(_tl)))
                        end

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Игрок:")
                        local px, py, pz = getCharCoordinates(PLAYER_PED)
                        imgui.TextColoredRGB(string.format(
                            "{808080}Координаты: {FFFFFF}%.2f, %.2f, %.2f", px, py, pz))
                        local interior = getActiveInterior()
                        imgui.TextColoredRGB(string.format(
                            "{808080}Интерьер: {FFFFFF}%d", interior or 0))

                        imgui.Spacing()
                        imgui.TextColoredRGB("{87CEFA}Заточка:")
                        imgui.TextColoredRGB(string.format(
                            "{808080}isOn: {FFFFFF}%s {808080}step: {FFFFFF}%d",
                            tostring(data.improve.isOn), data.improve.step))
                        imgui.TextColoredRGB(string.format(
                            "{808080}Карт в кэше: {FFFFFF}%d {808080}probed: {FFFFFF}%s {808080}probing: {FFFFFF}%s",
                            #data.improve.cef.cards,
                            tostring(data.improve.cef.probed),
                            tostring(data.improve.cef.probing)))
                        imgui.TextColoredRGB(string.format(
                            "{808080}oils.busy: {FFFFFF}%s {808080}busyAt: {FFFFFF}%.1f с назад",
                            tostring(data.improve.oils.busy),
                            data.improve.oils.busyAt > 0
                            and (os.clock() - data.improve.oils.busyAt) or 0))
                        imgui.TextColoredRGB(string.format(
                            "{808080}suppressDialogs: {FFFFFF}%s",
                            tostring(data.suppressDialogs)))

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Диагностика:")
                        do
                            local hasHouses = #data.dialogData.flashminer > 0
                            local hasStatuses, hasSnapshots, staleCount = false, false, 0
                            local now2 = os.time()
                            for _, h in ipairs(data.dialogData.flashminer) do
                                local st = data.houseStatuses[h.house_number]
                                if st and st.lastCheck > 0 then
                                    hasStatuses = true
                                    if (now2 - st.lastCheck) > 3600 then staleCount = staleCount + 1 end
                                end
                                local snap = cfg.cardSnapshots[tostring(h.house_number)]
                                if snap and snap.dailyBtcRate and snap.dailyBtcRate > 0 then hasSnapshots = true end
                            end
                            imgui.TextColoredRGB(string.format("{808080}Домов: %s%d",
                                hasHouses and "{BEF781}" or "{FF3333}", #data.dialogData.flashminer))
                            imgui.TextColoredRGB(string.format("{808080}Статусы: %s",
                                hasStatuses and "{BEF781}да" or "{FF3333}нет"))
                            imgui.TextColoredRGB(string.format("{808080}Снапшоты: %s",
                                hasSnapshots and "{BEF781}да" or "{FFE133}нет"))
                            if staleCount > 0 then
                                imgui.TextColoredRGB(string.format("{FFE133}Устаревших (>1ч): %d", staleCount))
                            end
                            imgui.TextColoredRGB(string.format("{808080}Готов к авто: %s",
                                (hasHouses and hasStatuses) and "{BEF781}да" or "{FF3333}нет"))
                            imgui.TextColoredRGB(string.format("{808080}Готов к умному: %s",
                                (hasHouses and hasStatuses and hasSnapshots) and "{BEF781}да" or "{FF3333}нет"))
                        end

                        imgui.Spacing()
                        if imgui.Selectable(u8 "Показать окно обновления скрипта", false) then
                            updateState.showPopup[0] = true
                        end

                        imgui.Spacing()
                        imgui.TextColoredRGB("{87CEFA}Снапшоты:")
                        if #data.dialogData.flashminer > 0 then
                            for _, h in ipairs(data.dialogData.flashminer) do
                                local snap = cfg.cardSnapshots[tostring(h.house_number)]
                                local st = data.houseStatuses[h.house_number]
                                local rate = (snap and snap.dailyBtcRate) and string.format("%.3f", snap.dailyBtcRate) or
                                    "-"
                                local obs = (snap and snap.incomeObs) and #snap.incomeObs or 0
                                local age = (st and st.lastCheck > 0) and
                                    string.format("%dм", math.floor((os.time() - st.lastCheck) / 60)) or "-"
                                imgui.TextColoredRGB(string.format(
                                    "{808080}№%d: {FFFFFF}%s {808080}(%d) {808080}%s",
                                    h.house_number, rate, obs, age))
                            end
                        else
                            imgui.TextColoredRGB("{808080}Нет домов.")
                        end
                    elseif data.debugSubTab == 2 then
                        imgui.TextColoredRGB("{F78181}Аварийные действия:")
                        if imgui.Selectable(u8 "Сбросить working + stopAction", false) then
                            taskState.setWorking(false); data.stopAction = false; data.taskTypeNow = nil
                            data.isWaitingPayday = false; data.skipPayday = false
                            progressTracker.reset()
                        end
                        if imgui.Selectable(u8 "Закрыть диалог", false) then
                            if sampIsDialogActive() then sampCloseCurrentDialogWithButton(0) end
                        end
                        if imgui.Selectable(u8 "Сбросить статусы домов", false) then
                            data.houseStatuses = {}; data.initialScanCompleted = false
                        end
                        if imgui.Selectable(u8 "Сбросить снапшоты", false) then
                            cfg.cardSnapshots = {}; save()
                        end
                        if imgui.Selectable(u8 "Сбросить pending", false) then
                            data.pendingCollectLocked = false; data.pendingCollectAt = 0
                        end
                        if imgui.Selectable(u8 "Сбросить таймер обновления", false) then
                            cfg.lastAutoRefreshTime = 0; save()
                        end

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Действия с домами:")
                        if imgui.Selectable(u8 "Зайти в выбранный дом", false) then
                            if #data.dialogData.flashminer > 0 and not data.working then
                                local house = data.dialogData.flashminer[data.selectedHouseIndex or 1]
                                lua_thread.create(function()
                                    taskState.setWorking(true); data.taskTypeNow = 'updateStatuses'
                                    sampSendDialogResponse(data.dFlashminerId, 1, house.index - 1, "")
                                    wait(500)
                                    sampSendDialogResponse(dialogIdTable.houseFlashMinerDialogId, 0, 0, "")
                                    wait(200); taskState.setWorking(false); data.taskTypeNow = nil
                                end)
                            end
                        end
                        if imgui.Selectable(u8 "Сбросить выбранный дом (заново скан)", false) then
                            if #data.dialogData.flashminer > 0 then
                                local house = data.dialogData.flashminer[data.selectedHouseIndex or 1]
                                if house then
                                    local key                              = tostring(house.house_number)
                                    cfg.basementScanned[key]               = nil
                                    cfg.housesWithoutBasement[key]         = nil
                                    cfg.cardSnapshots[key]                 = nil
                                    cfg.excludedHouses[key]                = nil
                                    data.houseStatuses[house.house_number] = nil
                                    cfg.lastHouseListHash                  = ''
                                    data.initialScanCompleted              = false
                                    save()
                                    utils.addChat(string.format(
                                        "{FFE133}DEBUG: дом №%s сброшен — отсканируется при следующем /flashminer.",
                                        key))
                                end
                            end
                        end
                        imgui.Hint(
                            "Удаляет статус/снапшот/флаги подвала для выбранного дома.\n" ..
                            "При следующем открытии /flashminer сработает скан подвала.")
                        if imgui.Selectable(u8 "Лог видеокарт", false) then
                            for i, card in ipairs(data.dialogData.videocards) do
                                utils.addChat(string.format("{808080}[%d] lvl=%d %s work=%s btc=%.2f cool=%.1f%%",
                                    i, card.level, card.card_type or "?", tostring(card.working),
                                    card.btc_full, card.coolant))
                            end
                        end
                        if imgui.Selectable(u8 "Лог исключённых", false) then
                            for houseNum in pairs(cfg.excludedHouses) do
                                utils.addChat(string.format("{808080}  №%s", houseNum))
                            end
                        end
                        if imgui.Selectable(u8 "Лог без подвала", false) then
                            for houseNum in pairs(cfg.housesWithoutBasement) do
                                utils.addChat(string.format("{808080}  №%s", houseNum))
                            end
                        end

                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Переключения:")
                        if imgui.Selectable(u8(string.format("silentMode: %s", cfg.silentMode and "выкл" or "вкл")), false) then
                            cfg.silentMode = not cfg.silentMode; imcfg.silentMode[0] = cfg.silentMode; save()
                        end
                        if imgui.Selectable(u8(string.format("pauseOnPayday: %s", cfg.pauseOnPayday and "выкл" or "вкл")), false) then
                            cfg.pauseOnPayday = not cfg.pauseOnPayday; imcfg.pauseOnPayday[0] = cfg.pauseOnPayday; save()
                        end
                        if imgui.Selectable(u8(string.format("isViceCity: %s", data.isViceCity and "выкл" or "вкл")), false) then
                            data.isViceCity = not data.isViceCity
                        end
                        if imgui.Selectable(u8(string.format("notifyAuto: %s", cfg.notifyAutoCollectEnabled and "выкл" or "вкл")), false) then
                            cfg.notifyAutoCollectEnabled = not cfg.notifyAutoCollectEnabled
                            imcfg.notifyAutoCollectEnabled[0] = cfg.notifyAutoCollectEnabled; save()
                        end
                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()

                        imgui.TextColoredRGB("{87CEFA}Заточка:")
                        if imgui.Selectable(u8 "Открыть/закрыть окно заточки", false) then
                            data.showImproveWindow[0] = not data.showImproveWindow[0]
                        end
                        if imgui.Selectable(u8 "Сбросить oils.busy", false) then
                            data.improve.oils.busy   = false
                            data.improve.oils.busyAt = 0
                            utils.addChat("{FFE133}DEBUG: oils.busy сброшен.")
                        end
                        if imgui.Selectable(u8 "Сбросить probing/probed", false) then
                            data.improve.cef.probing   = false
                            data.improve.cef.probed    = false
                            data.improve.cef.probeDone = false
                            utils.addChat("{FFE133}DEBUG: probing/probed сброшены.")
                        end
                        if imgui.Selectable(u8 "Принудительно остановить заточку", false) then
                            improveTool.stop("DEBUG")
                        end
                    end
                end
            end
            imgui.PopStyleColor()

            imgui.End()
        end
        if data.statsResetConfirm then
            renderResetConfirm(
                "statsResetConfirm",
                data.statsResetTimer,
                "Сбросить статистику дохода?",
                "Накопленные данные о доходах будут стёрты безвозвратно.",
                function()
                    resetIncomeRates()
                    data.statsResetConfirm = false
                end,
                function() data.statsResetConfirm = false end)
        end

        if data.settingsResetConfirm then
            renderResetConfirm(
                "settingsResetConfirm",
                data.settingsResetTimer,
                "Сбросить все настройки?",
                "Все ползунки и галочки вернутся к значениям по умолчанию.",
                function()
                    resetDefaultCfg()
                    data.settingsResetConfirm = false
                end,
                function() data.settingsResetConfirm = false end)
        end
    end
)


-- окно обновления
imgui.OnFrame(
    function() return updateState.showPopup[0] end,
    function(self)
        applyStyle()
        local sw, sh = getScreenResolution()
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2),
            imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(560, 0), imgui.Cond.Always)
        imgui.SetNextWindowFocus()

        if imgui.Begin("##updateWin", updateState.showPopup,
                imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar +
                imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove +
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.AlwaysAutoResize +
                imgui.WindowFlags.NoScrollWithMouse) then
            local winW  = imgui.GetWindowWidth()
            local style = imgui.GetStyle()

            imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.13, 0.16, 0.22, 1))
            imgui.BeginChild("##updHeader", imgui.ImVec2(-1, 50), true,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

            local headerW = imgui.GetWindowWidth()
            local titleIcon = fa.ARROW_UP_FROM_BRACKET
            local titleText = u8 "Доступно обновление"

            local rowW = imgui.CalcTextSize(titleIcon).x
                + 12
                + imgui.CalcTextSize(titleText).x
            imgui.SetCursorPos(imgui.ImVec2((headerW - rowW) / 2, 14))
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 0.78, 0.20, 1.0))
            imgui.Text(titleIcon)
            imgui.PopStyleColor()
            imgui.SameLine(0, 12)
            imgui.TextColoredRGB("{FFFFFF}Доступно обновление")

            imgui.EndChild()
            imgui.PopStyleColor()

            imgui.Spacing()

            local cur     = tostring(script.this.version or "?")
            local new     = tostring(updateState.latestVersion or "?")

            local sLabelL = u8 "Текущая"
            local sLabelR = u8 "Новая"
            local arrow   = fa.ARROW_RIGHT
            local wLabelL = imgui.CalcTextSize(sLabelL).x
            local wLabelR = imgui.CalcTextSize(sLabelR).x
            local wArrow  = imgui.CalcTextSize(arrow).x
            local wCur    = imgui.CalcTextSize(cur).x
            local wNew    = imgui.CalcTextSize(new).x
            local rowW    = wLabelL + 8 + wCur + 18 + wArrow + 18 + wLabelR + 8 + wNew

            imgui.SetCursorPosX((winW - rowW) / 2)
            imgui.TextColoredRGB("{808080}" .. "Текущая")
            imgui.SameLine(0, 8)
            imgui.TextColoredRGB("{B0B0B0}" .. cur)
            imgui.SameLine(0, 18)
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 0.78, 0.20, 1.0))
            imgui.Text(arrow)
            imgui.PopStyleColor()
            imgui.SameLine(0, 18)
            imgui.TextColoredRGB("{BEF781}" .. "Новая")
            imgui.SameLine(0, 8)
            imgui.TextColoredRGB("{FFFFFF}" .. new)

            imgui.Spacing()
            imgui.Spacing()

            if updateState.changelog ~= "" then
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 0.65, 0.20, 1.0))
                imgui.Text(fa.CLOCK_ROTATE_LEFT)
                imgui.PopStyleColor()
                imgui.SameLine(0, 6)
                imgui.TextColoredRGB("{FFA500}Что нового")
                imgui.SameLine(0, 8)
                imgui.TextColoredRGB("{606060}— список изменений в новой версии")
                imgui.Spacing()

                imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.09, 0.10, 0.14, 1))
                imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.20, 0.22, 0.28, 1))
                imgui.BeginChild("##updateChangelog", imgui.ImVec2(0, 150), true,
                    imgui.WindowFlags.NoScrollWithMouse)
                imgui.Scroller("update_changelog", 20, 300,
                    imgui.HoveredFlags.RectOnly + imgui.HoveredFlags.ChildWindows)
                imgui.TextColoredRGB(updateState.changelog)
                imgui.EndChild()
                imgui.PopStyleColor(2)

                imgui.Spacing()
            end

            local halfW = (winW - style.WindowPadding.x * 2 - style.ItemSpacing.x) / 2

            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18, 0.55, 0.22, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.25, 0.70, 0.28, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.12, 0.40, 0.15, 1))
            if imgui.Button(fa.DOWNLOAD .. u8 "  Обновить сейчас", imgui.ImVec2(halfW, 36)) then
                downloadAndUpdate()
            end
            imgui.PopStyleColor(3)
            imgui.Hint("Скачать и установить новую версию автоматически.\nСкрипт будет перезагружен.")

            imgui.SameLine()

            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18, 0.18, 0.22, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.26, 0.26, 0.30, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.13, 0.13, 0.16, 1))
            if imgui.Button(fa.CLOCK .. u8 "  Напомнить позже", imgui.ImVec2(halfW, 36)) then
                updateState.showPopup[0] = false
                updateState.declined     = true
            end
            imgui.PopStyleColor(3)
            imgui.Hint("Закрыть окно. Обновление можно будет установить позже из настроек.")

            imgui.Spacing()
            imgui.End()
        end
    end
)
-- окно логов
local _logsSaveT     = 0
local _logsActiveTab = 0
local _logsPrevTab   = 0

imgui.OnFrame(
    function() return data.showLogsWindow[0] end,
    function(self)
        applyStyle()
        local sw, sh = getScreenResolution()
        local desiredH = (_logsActiveTab == 2) and 800 or 645
        if _logsActiveTab ~= _logsPrevTab then
            imgui.SetNextWindowSize(imgui.ImVec2(720, desiredH), imgui.Cond.Always)
            _logsPrevTab = _logsActiveTab
        else
            imgui.SetNextWindowSize(imgui.ImVec2(720, desiredH), imgui.Cond.FirstUseEver)
        end
        imgui.SetNextWindowPos(
            imgui.ImVec2(cfg.logsWindowPosX * sw, cfg.logsWindowPosY * sh),
            imgui.Cond.FirstUseEver
        )

        local function renderLogEntry(entry, childPrefix, h)
            local eIcon, eLabel, eDetail = logsTool.format(entry)
            imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.09, 0.10, 0.14, 1))
            imgui.BeginChild(childPrefix, imgui.ImVec2(0, h), true,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
            local ew   = imgui.GetWindowWidth()
            local posY = (h - imgui.GetTextLineHeight()) / 2
            imgui.SetCursorPos(imgui.ImVec2(8, posY))
            imgui.Text(fa.CLOCK)
            imgui.SameLine(0, 4)
            imgui.TextColoredRGB("{808080}" .. entry.time)
            imgui.SameLine(0, 8)
            imgui.Text(eIcon)
            imgui.SameLine(0, 4)
            imgui.TextColoredRGB("{FFFFFF}" .. eLabel)
            if eDetail ~= "" then
                local dw = imgui.CalcTextSize(u8(eDetail)).x
                if ew - dw - 10 > imgui.GetCursorPosX() + 5 then
                    imgui.SetCursorPos(imgui.ImVec2(ew - dw - 10, posY))
                    imgui.TextColoredRGB("{87CEFA}" .. eDetail)
                end
            end
            imgui.EndChild()
            imgui.PopStyleColor()
        end

        local function renderEmptyLogs()
            local availH = imgui.GetContentRegionAvail().y
            local lineH  = imgui.GetTextLineHeight()
            imgui.SetCursorPosY(imgui.GetCursorPosY() + availH / 2 - lineH * 2)
            local cW = imgui.GetWindowWidth()
            local iW = imgui.CalcTextSize(fa.BOX_OPEN).x
            imgui.SetCursorPosX((cW - iW) / 2)
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.25, 0.27, 0.32, 1))
            imgui.Text(fa.BOX_OPEN)
            imgui.PopStyleColor()
            imgui.Spacing()
            local lines = {
                { "{CCCCCC}", "Действий ещё не записано" },
                { "{808080}", "История появится после первого использования" },
            }
            for _, l in ipairs(lines) do
                imgui.SetCursorPosX(cW / 2 - imgui.CalcTextSize(u8(l[2])).x / 2)
                imgui.TextColoredRGB(l[1] .. l[2])
            end
        end

        if imgui.Begin("##logsWin", data.showLogsWindow,
                imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize +
                imgui.WindowFlags.NoTitleBar) then
            local wp = imgui.GetWindowPos()
            local nx, ny = wp.x / sw, wp.y / sh
            if math.abs(nx - cfg.logsWindowPosX) > 0.003 or math.abs(ny - cfg.logsWindowPosY) > 0.003 then
                cfg.logsWindowPosX, cfg.logsWindowPosY = nx, ny
                local t = os.clock()
                if t - _logsSaveT > 1.5 then
                    _logsSaveT = t; save()
                end
            end

            local imStyle = imgui.GetStyle()
            local winW = imgui.GetWindowWidth()

            imgui.SetCursorPosY(imStyle.ItemSpacing.y)
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.35, 0.10, 0.10, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.55, 0.15, 0.15, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.25, 0.07, 0.07, 1))
            if imgui.Button(fa.TRASH .. "##logsReset", imgui.ImVec2(40, 22)) then
                data.logsResetConfirm = true
                data.logsResetTimer   = os.clock()
                data.logsResetMode    = (_logsActiveTab == 2) and "improve" or "all"
            end
            imgui.PopStyleColor(3)
            imgui.Hint(_logsActiveTab == 2
                and "Очистить логи заточки"
                or "Очистить все логи действий")

            local titleIcon = fa.CLOCK_ROTATE_LEFT
            local titleText = u8 "Логи"
            local iconW2 = imgui.CalcTextSize(titleIcon).x
            local textW2 = imgui.CalcTextSize(titleText).x
            local totalW2 = iconW2 + 8 + textW2
            imgui.SetCursorPos(imgui.ImVec2((winW - totalW2) / 2, imStyle.ItemSpacing.y + 3))
            imgui.Text(titleIcon)
            imgui.SameLine(0, 8)
            imgui.SetCursorPosY(imStyle.ItemSpacing.y + 3)
            imgui.TextColoredRGB("{FFFFFF}Логи")

            imgui.SetCursorPos(imgui.ImVec2(winW - 50 - imStyle.ItemSpacing.x, imStyle.ItemSpacing.y))
            if imgui.Button(fa.XMARK .. "##logsClose", imgui.ImVec2(40, 22)) then
                data.showLogsWindow[0] = false
            end
            imgui.Hint("Закрыть окно логов")
            imgui.Separator()

            local dates = {}
            for d in pairs(logsTool.getAllByDate()) do table.insert(dates, d) end
            table.sort(dates, function(a, b)
                local function key(s)
                    local d2, m2, y2 = s:match("(%d+)%.(%d+)%.(%d+)")
                    return string.format("%s%s%s", y2, m2, d2)
                end
                return key(a) > key(b)
            end)

            local cache         = logsTool.getCacheSummary()
            local totalSessions = cache.sessions
            local dailySums     = {}
            for _, dateStr in ipairs(dates) do
                local db, da, collectCount = 0, 0, 0
                for _, e in ipairs(logsTool.getEntriesByDate(dateStr)) do
                    db = db + (e.btc or 0)
                    da = da + (e.asc or 0)
                    local act = e.action or 'collect'
                    if act == 'collect' or act == 'fix' then collectCount = collectCount + 1 end
                end
                dailySums[dateStr] = {
                    btc = db,
                    asc = da,
                    count = #logsTool.getEntriesByDate(dateStr),
                    collectCount =
                        collectCount
                }
            end

            local tabW = (winW - imgui.GetStyle().WindowPadding.x * 2 - imgui.GetStyle().ItemSpacing.x * 2) / 3
            imgui.PushStyleColor(imgui.Col.Button,
                _logsActiveTab == 0 and imgui.ImVec4(0.15, 0.22, 0.35, 1) or imgui.ImVec4(0.09, 0.10, 0.14, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.25, 0.40, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.20, 0.28, 0.45, 1))
            if imgui.Button(u8 "Общее", imgui.ImVec2(tabW, 28)) then _logsActiveTab = 0 end
            imgui.PopStyleColor(3)
            imgui.SameLine()
            imgui.PushStyleColor(imgui.Col.Button,
                _logsActiveTab == 1 and imgui.ImVec4(0.15, 0.22, 0.35, 1) or imgui.ImVec4(0.09, 0.10, 0.14, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.25, 0.40, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.20, 0.28, 0.45, 1))
            if imgui.Button(u8 "По дням", imgui.ImVec2(tabW, 28)) then _logsActiveTab = 1 end
            imgui.PopStyleColor(3)
            imgui.SameLine()
            imgui.PushStyleColor(imgui.Col.Button,
                _logsActiveTab == 2 and imgui.ImVec4(0.15, 0.22, 0.35, 1) or imgui.ImVec4(0.09, 0.10, 0.14, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.25, 0.40, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.20, 0.28, 0.45, 1))
            if imgui.Button(u8 "Заточка", imgui.ImVec2(tabW, 28)) then _logsActiveTab = 2 end
            imgui.PopStyleColor(3)
            imgui.Separator()
            if _logsActiveTab == 0 then
                imgui.Spacing()
                local colW = math.floor((winW - imgui.GetStyle().WindowPadding.x * 2 - imgui.GetStyle().ItemSpacing.x) *
                    0.38)

                -- Левая колонка: общая статистика
                imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.07, 0.08, 0.11, 1))
                if imgui.BeginChild("##logsRightCol", imgui.ImVec2(colW, 0), true,
                        imgui.WindowFlags.NoScrollWithMouse) then
                    local periodLabels = { u8 "Всё время", u8 "Сегодня", u8 "Неделя", u8 "Месяц" }
                    imgui.PushItemWidth(-1)
                    if imgui.BeginCombo("##logsPeriod", periodLabels[data.logsPeriodFilter + 1]) then
                        for pi = 1, #periodLabels do
                            local pSel = data.logsPeriodFilter == pi - 1
                            if imgui.Selectable(periodLabels[pi], pSel) then
                                data.logsPeriodFilter = pi - 1
                            end
                        end
                        imgui.EndCombo()
                    end
                    imgui.PopItemWidth()
                    imgui.Spacing()
                    imgui.Separator()

                    local stats = logsTool.getStats(data.logsPeriodFilter)

                    local function StatRow(icon, label, value, color, hint)
                        imgui.BeginGroup()
                        imgui.Text(icon)
                        imgui.SameLine(0, 6)
                        imgui.TextColoredRGB("{808080}" .. label)
                        imgui.SameLine(0, 4)
                        imgui.TextColoredRGB((color or "{FFFFFF}") .. value)
                        imgui.EndGroup()
                        if hint then imgui.Hint(hint) end
                    end

                    imgui.TextColoredRGB("{87CEFA}Криптовалюта:")
                    StatRow(fa.COINS, "Получено BTC:", tostring(stats.btc), "{BEF781}",
                        "Суммарное количество BTC собранного со всех ферм")
                    StatRow(fa.COINS, "Получено ASC:", tostring(stats.asc), "{FFA500}",
                        "Суммарное количество ASC собранного со всех ферм")
                    StatRow(fa.ROTATE, "Сессий сбора:", tostring(stats.collectSessions), "{FFFFFF}",
                        "Количество запусков сбора криптовалюты")
                    imgui.Spacing()

                    imgui.TextColoredRGB("{87CEFA}Видеокарты:")
                    StatRow(fa.POWER_OFF, "Включено карт:", tostring(stats.switchOn), "{BEF781}",
                        "Суммарное количество включённых видеокарт за всё время")
                    StatRow(fa.PLUG, "Выключено карт:", tostring(stats.switchOff), "{F78181}",
                        "Суммарное количество выключённых видеокарт за всё время")
                    imgui.Spacing()

                    imgui.TextColoredRGB("{87CEFA}Охлаждение:")
                    StatRow(fa.DROPLET, "Карт залито:", tostring(stats.coolantCards), "{FFFFFF}",
                        "Количество видеокарт которым заливалась жидкость")

                    StatRow(fa.DROPLET, "Обычной:", stats.coolantBottles .. " шт.", "{87CEFA}",
                        "Количество флаконов обычной охлаждающей жидкости")

                    StatRow(fa.DROPLET, "Супер:", stats.coolantSuper .. " шт.", "{FFE133}",
                        "Количество флаконов супер охлаждающей жидкости")
                    imgui.Spacing()

                    imgui.TextColoredRGB("{87CEFA}Обслуживание:")

                    StatRow(fa.DOLLAR_SIGN, "Ферм пополнено на:", "$" .. utils.formatNumber(stats.topup), "{FFD700}",
                        "Общая сумма пополнений баланса домов")
                    imgui.Spacing()

                    imgui.TextColoredRGB("{87CEFA}Всего:")
                    StatRow(fa.CALENDAR_DAYS, "Дней активности:", string.format("%d", #dates), "{FFFFFF}",
                        "Количество дней в которые были зафиксированы действия")
                    StatRow(fa.CLOCK_ROTATE_LEFT, "Записей:", string.format("%d", totalSessions), "{FFFFFF}",
                        "Общее количество записей в логах")

                    imgui.EndChild()
                end
                imgui.PopStyleColor()

                imgui.SameLine()

                -- Правая колонка: лог по дням
                imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.07, 0.08, 0.11, 1))
                if imgui.BeginChild("##logsLeftCol", imgui.ImVec2(0, 0), true, imgui.WindowFlags.NoScrollWithMouse) then
                    if #dates == 0 then
                        renderEmptyLogs()
                    else
                        imgui.Scroller("logs_main", 30, 400,
                            imgui.HoveredFlags.RectOnly + imgui.HoveredFlags.ChildWindows)
                        for _, dateStr in ipairs(dates) do
                            local ds = dailySums[dateStr]
                            imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.11, 0.13, 0.18, 1))
                            imgui.BeginChild("dayhead_" .. dateStr, imgui.ImVec2(0, 28), true,
                                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                            imgui.SetCursorPos(imgui.ImVec2(8, (28 - imgui.GetTextLineHeight()) / 2))
                            imgui.Text(fa.CALENDAR_DAYS)
                            imgui.SameLine(0, 6)
                            imgui.TextColoredRGB("{FFA500}" .. dateStr)
                            imgui.SameLine(0, 10)
                            imgui.TextColoredRGB(string.format("{808080}%d зап.", ds.count))
                            imgui.EndChild()
                            imgui.PopStyleColor()

                            local dayEntries = logsTool.getEntriesByDate(dateStr)
                            for j = #dayEntries, 1, -1 do
                                renderLogEntry(dayEntries[j], "allentry_" .. dateStr .. "_" .. j, 30)
                            end
                            imgui.Spacing()
                        end
                    end
                    imgui.EndChild()
                end
                imgui.PopStyleColor()
            elseif _logsActiveTab == 1 then
                imgui.Spacing()
                if #dates == 0 then
                    renderEmptyLogs()
                else
                    -- Левая панель: список дат
                    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.09, 0.10, 0.14, 1))
                    if imgui.BeginChild("##daysLeft", imgui.ImVec2(140, 0), true,
                            imgui.WindowFlags.NoScrollWithMouse) then
                        imgui.Scroller("logs_days_left", 38, 300,
                            imgui.HoveredFlags.RectOnly + imgui.HoveredFlags.ChildWindows)
                        for i, dateStr in ipairs(dates) do
                            local isSelected = (data.logsTab[0] == i - 1)
                            local ds = dailySums[dateStr]

                            imgui.PushStyleColor(imgui.Col.Header,
                                imgui.ImVec4(0.15, 0.22, 0.35, 1))
                            imgui.PushStyleColor(imgui.Col.HeaderHovered,
                                imgui.ImVec4(0.18, 0.27, 0.42, 1))

                            if imgui.Selectable("##sel_" .. dateStr, isSelected,
                                    0, imgui.ImVec2(0, 30)) then
                                data.logsTab[0] = i - 1
                            end
                            imgui.PopStyleColor(2)

                            local cp = imgui.GetItemRectMin()
                            local dl2 = imgui.GetWindowDrawList()
                            if isSelected then
                                dl2:AddRectFilled(
                                    cp,
                                    imgui.ImVec2(cp.x + 3, cp.y + 38),
                                    imgui.ColorConvertFloat4ToU32(
                                        imgui.ImVec4(0.2, 0.6, 1.0, 1.0))
                                )
                            end

                            imgui.SetCursorScreenPos(
                                imgui.ImVec2(cp.x + 8, cp.y + 4))
                            imgui.TextColoredRGB(
                                (isSelected and "{FFFFFF}" or "{FFA500}") .. dateStr)
                            imgui.SetCursorScreenPos(
                                imgui.ImVec2(cp.x + 8, cp.y + 22))
                            imgui.TextColoredRGB(
                                string.format("{808080}%d BTC · %d зап.",
                                    ds.btc, ds.count))
                        end
                        imgui.EndChild()
                    end
                    imgui.PopStyleColor()

                    imgui.SameLine(0, 8)

                    -- Правая панель: записи выбранного дня
                    local selDate = dates[data.logsTab[0] + 1]
                    local selEntries = selDate and logsTool.getEntriesByDate(selDate) or {}
                    if selDate and #selEntries > 0 then
                        local ds = dailySums[selDate]
                        if imgui.BeginChild("##daysRight", imgui.ImVec2(0, 0), false) then
                            -- Шапка дня
                            imgui.PushStyleColor(imgui.Col.ChildBg,
                                imgui.ImVec4(0.09, 0.10, 0.14, 1))
                            imgui.BeginChild("##dayHeader", imgui.ImVec2(0, 44), true,
                                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                            imgui.SetCursorPos(imgui.ImVec2(10, 6))
                            imgui.Text(fa.CALENDAR_DAYS)
                            imgui.SameLine(0, 6)
                            imgui.TextColoredRGB("{FFA500}" .. selDate)
                            imgui.SetCursorPos(imgui.ImVec2(10, 24))
                            imgui.TextColoredRGB(string.format(
                                "{BEF781}%d BTC  {808080}·  {FFFFFF}%d сборов  {808080}·  {FFFFFF}%d записей",
                                ds.btc, ds.collectCount, ds.count))
                            imgui.EndChild()
                            imgui.PopStyleColor()

                            imgui.Spacing()

                            -- Список записей
                            if imgui.BeginChild("##dayEntries", imgui.ImVec2(0, 0), false, imgui.WindowFlags.NoScrollWithMouse) then
                                imgui.Scroller("logs_day_entries", 34, 400,
                                    imgui.HoveredFlags.RectOnly + imgui.HoveredFlags.ChildWindows)
                                for j = #selEntries, 1, -1 do
                                    renderLogEntry(selEntries[j], "entry_" .. selDate .. "_" .. j, 34)
                                end
                                imgui.EndChild()
                            end
                            imgui.EndChild()
                        end
                    end
                end
            elseif _logsActiveTab == 2 then
                imgui.Spacing()
                -- Фильтр периода
                local periodLabels = { u8 "Всё время", u8 "Сегодня", u8 "Неделя", u8 "Месяц" }
                imgui.PushItemWidth(-1)
                if imgui.BeginCombo("##improvePeriod", periodLabels[data.logsPeriodFilter + 1]) then
                    for pi = 1, #periodLabels do
                        local pSel = data.logsPeriodFilter == pi - 1
                        if imgui.Selectable(periodLabels[pi], pSel) then
                            data.logsPeriodFilter = pi - 1
                        end
                    end
                    imgui.EndCombo()
                end
                imgui.PopItemWidth()
                imgui.Spacing()

                local stats    = logsTool.getStats(data.logsPeriodFilter)
                local imStyle2 = imgui.GetStyle()
                local hasData  = (stats.improveSessions or 0) > 0 or (stats.improveAttempts or 0) > 0

                if not hasData then
                    local availH = imgui.GetContentRegionAvail().y
                    local availW = imgui.GetContentRegionAvail().x
                    imgui.SetCursorPosY(imgui.GetCursorPosY() + availH / 2 - 36)
                    local iconW = imgui.CalcTextSize(fa.MICROCHIP).x
                    imgui.SetCursorPosX((availW - iconW) / 2)
                    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.25, 0.27, 0.32, 1))
                    imgui.Text(fa.MICROCHIP)
                    imgui.PopStyleColor()
                    imgui.Spacing()
                    local txt1 = u8("За этот период нет записей заточки")
                    local txt2 = u8("Статистика появится после первой заточки")
                    imgui.SetCursorPosX((availW - imgui.CalcTextSize(txt1).x) / 2)
                    imgui.TextColoredRGB("{CCCCCC}За этот период нет записей заточки")
                    imgui.SetCursorPosX((availW - imgui.CalcTextSize(txt2).x) / 2)
                    imgui.TextColoredRGB("{808080}Статистика появится после первой заточки")
                else
                    local availTopW = imgui.GetContentRegionAvail().x
                    local W         = (availTopW - imStyle2.ItemSpacing.x * 3) / 4

                    local function Title(id, icon, label, value, valColor, hint)
                        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.11, 0.13, 0.18, 1))
                        imgui.BeginChild("##tit_" .. id, imgui.ImVec2(W, 55), true,
                            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                        local cW    = imgui.GetWindowWidth()
                        local iconW = imgui.CalcTextSize(icon).x
                        local lblW  = imgui.CalcTextSize(u8(label)).x
                        local rowW  = iconW + 6 + lblW
                        imgui.SetCursorPos(imgui.ImVec2((cW - rowW) / 2, 8))
                        imgui.Text(icon)
                        imgui.SameLine(0, 6)
                        imgui.TextColoredRGB("{808080}" .. label)
                        local valTxt  = u8(value)
                        local valSize = imgui.CalcTextSize(valTxt)
                        imgui.SetCursorPos(imgui.ImVec2((cW - valSize.x) / 2, 36))
                        imgui.TextColoredRGB((valColor or "{FFFFFF}") .. value)
                        imgui.EndChild()
                        imgui.PopStyleColor()
                        if hint then imgui.Hint(hint) end
                    end

                    local function buildLevelBreakdown(unitFn)
                        local lines = {}
                        local hasData = false
                        for lvl = 1, 9 do
                            local atk = (stats.improveAttemptsByLevel or {})[lvl] or 0
                            local suc = (stats.improveByLevel or {})[lvl + 1] or 0
                            if atk > 0 then
                                hasData = true
                                if suc > 0 then
                                    local avg = atk / suc
                                    table.insert(lines, string.format(
                                        "С %d на %d: ~%s (за ~%d попыток)",
                                        lvl, lvl + 1, unitFn(avg, lvl), math.floor(avg + 0.5)))
                                else
                                    table.insert(lines, string.format(
                                        "С %d на %d: %d попыток, успехов нет",
                                        lvl, lvl + 1, atk))
                                end
                            end
                        end
                        if not hasData then
                            return "Накопится после первых попыток"
                        end
                        return table.concat(lines, "\n")
                    end

                    local stoAtk   = stats.improveStorageAttempts or 0
                    local stoSuc   = stats.improveStorageSuccess or 0
                    local stoFail  = stats.improveStorageFail or 0
                    local perfAtk  = (stats.improveAttempts or 0) - stoAtk
                    local perfSuc  = (stats.improveSuccess or 0) - stoSuc
                    local perfFail = (stats.improveFail or 0) - stoFail
                    local perfPct  = perfAtk > 0 and perfSuc / perfAtk * 100 or 0
                    local stoPct   = stoAtk > 0 and stoSuc / stoAtk * 100 or 0

                    local succHint = "Процент успешных попыток заточки видеокарт"
                    if stoAtk > 0 then
                        succHint = succHint .. string.format(
                            "\n\nУлучшение хранилища: %.1f%% (%d из %d)",
                            stoPct, stoSuc, stoAtk)
                    end

                    Title("spent", fa.DOLLAR_SIGN, "Потрачено",
                        "$" .. utils.formatNumber(stats.improveSpent or 0), "{FFD700}",
                        "Суммарная стоимость попыток заточки за выбранный период")
                    imgui.SameLine()
                    Title("oils", fa.DROPLET, "Смазок",
                        tostring(stats.improveOils or 0) .. " шт.", "{87CEFA}",
                        "Сколько штук смазки было потрачено")
                    imgui.SameLine()
                    Title("succ", fa.PERCENT, "Успеха",
                        perfAtk > 0 and string.format("%.1f%%", perfPct) or "—",
                        "{BEF781}",
                        succHint)
                    imgui.SameLine()
                    Title("sess", fa.ROTATE, "Заточки",
                        tostring(stats.improveSessions or 0), "{FFFFFF}",
                        "Количество запущенных заточек")
                    imgui.Spacing()

                    local function CenterRow(items)
                        local totalW = 0
                        for i, it in ipairs(items) do
                            local w = 0
                            if it.icon then w = w + imgui.CalcTextSize(it.icon).x + 6 end
                            w = w + imgui.CalcTextSize(u8(it.label or '')).x
                            if it.value then
                                w = w + 4 + imgui.CalcTextSize(u8(it.value or '')).x
                            end
                            totalW = totalW + w
                            if i < #items then totalW = totalW + 28 end
                        end
                        local availW = imgui.GetContentRegionAvail().x
                        imgui.SetCursorPosX(math.max(0, (availW - totalW) / 2))
                        for i, it in ipairs(items) do
                            if i > 1 then imgui.SameLine(0, 28) end
                            imgui.BeginGroup()
                            if it.icon then
                                imgui.Text(it.icon)
                                imgui.SameLine(0, 6)
                            end
                            imgui.TextColoredRGB("{B0B0B0}" .. (it.label or ''))
                            if it.value then
                                imgui.SameLine(0, 4)
                                imgui.TextColoredRGB((it.valueColor or "{FFFFFF}") .. (it.value or ''))
                            end
                            imgui.EndGroup()
                            if it.hint then imgui.Hint(it.hint) end
                        end
                    end

                    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.07, 0.08, 0.11, 1))
                    imgui.BeginChild("##improveAttempts", imgui.ImVec2(0, 70), true,
                        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                    do
                        local title = u8("Попытки")
                        imgui.SetCursorPosX((imgui.GetContentRegionAvail().x - imgui.CalcTextSize(title).x) / 2)
                        imgui.TextColoredRGB("{87CEFA}Попытки")
                    end
                    imgui.Spacing()
                    CenterRow({
                        {
                            icon = fa.CHECK,
                            label = "Успешных:",
                            value = tostring(stats.improveSuccess or 0),
                            valueColor = "{BEF781}",
                            hint = "Сколько попыток закончились повышением уровня карты"
                        },
                        {
                            icon = fa.XMARK,
                            label = "Провальных:",
                            value = tostring(stats.improveFail or 0),
                            valueColor = "{F78181}",
                            hint = "Сколько попыток закончились неудачей (карта не поднялась в уровне)"
                        },
                        {
                            icon = fa.LAYER_GROUP,
                            label = "Всего:",
                            value = tostring(stats.improveAttempts or 0),
                            valueColor = "{FFFFFF}",
                            hint = "Общее количество попыток за выбранный период (успешных + провальных)"
                        },
                    })
                    imgui.EndChild()
                    imgui.PopStyleColor()
                    imgui.Spacing()

                    local attempts       = perfAtk
                    local success        = perfSuc
                    local spent          = stats.improveSpent or 0
                    local oils           = stats.improveOils or 0

                    local avgPerAttempt  = attempts > 0 and (spent / attempts) or 0
                    local avgPerSuccess  = success > 0 and (spent / success) or 0
                    local avgOilsAttempt = attempts > 0 and (oils / attempts) or 0
                    local avgOilsSuccess = success > 0 and (oils / success) or 0

                    local availW2        = imgui.GetContentRegionAvail().x
                    local colW2          = (availW2 - imStyle2.ItemSpacing.x) / 2

                    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.07, 0.08, 0.11, 1))
                    imgui.BeginChild("##improveDerivedL", imgui.ImVec2(colW2, 96), true,
                        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                    do
                        local title = u8("Среднее по деньгам")
                        imgui.SetCursorPosX((imgui.GetContentRegionAvail().x - imgui.CalcTextSize(title).x) / 2)
                        imgui.TextColoredRGB("{87CEFA}Среднее по деньгам")
                    end
                    imgui.Spacing()
                    CenterRow({
                        {
                            icon       = fa.DOLLAR_SIGN,
                            label      = "на попытку:",
                            value      = attempts > 0 and ("$" .. utils.formatNumber(math.floor(avgPerAttempt))) or "—",
                            valueColor = "{FFD700}",
                            hint       = "Сколько денег в среднем уходит на одну попытку заточки"
                        },
                    })
                    CenterRow({
                        {
                            icon       = fa.CHECK,
                            label      = "на одно успешное:",
                            value      = success > 0 and ("$" .. utils.formatNumber(math.floor(avgPerSuccess))) or "—",
                            valueColor = "{BEF781}",
                            hint       = "Сколько денег уходит на одну успешную заточку.\n\n"
                                .. buildLevelBreakdown(function(avg, lvl)
                                    return "$" .. utils.formatNumber(
                                        math.floor(avg * (gpuImprovePriceByLevel[lvl] or 0)))
                                end)
                        },
                    })
                    imgui.EndChild()
                    imgui.PopStyleColor()

                    imgui.SameLine()

                    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.07, 0.08, 0.11, 1))
                    imgui.BeginChild("##improveDerivedR", imgui.ImVec2(0, 96), true,
                        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                    do
                        local title = u8("Смазка")
                        imgui.SetCursorPosX((imgui.GetContentRegionAvail().x - imgui.CalcTextSize(title).x) / 2)
                        imgui.TextColoredRGB("{87CEFA}Смазка")
                    end
                    imgui.Spacing()
                    CenterRow({
                        {
                            icon       = fa.DROPLET,
                            label      = "на попытку:",
                            value      = attempts > 0 and string.format("%.2f шт.", avgOilsAttempt) or "—",
                            valueColor = "{87CEFA}",
                            hint       = "Сколько штук смазки в среднем уходит на одну попытку заточки"
                        },
                    })
                    CenterRow({
                        {
                            icon       = fa.CHECK,
                            label      = "на одно успешное:",
                            value      = success > 0 and string.format("%.2f шт.", avgOilsSuccess) or "—",
                            valueColor = "{87CEFA}",
                            hint       = "Сколько штук смазки уходит на одну успешную заточку.\n\n"
                                .. buildLevelBreakdown(function(avg, lvl)
                                    return string.format("%d шт.", math.floor(avg * 2 + 0.5))
                                end)
                        },
                    })
                    imgui.EndChild()
                    imgui.PopStyleColor()
                    imgui.Spacing()

                    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.07, 0.08, 0.11, 1))
                    imgui.BeginChild("##improveCards", imgui.ImVec2(0, 0), true,
                        imgui.WindowFlags.NoScrollWithMouse)
                    imgui.Scroller("improve_cards", 28, 240,
                        imgui.HoveredFlags.RectOnly + imgui.HoveredFlags.ChildWindows)

                    imgui.TextColoredRGB("{87CEFA}Список карт")
                    if imgui.IsItemHovered() then
                        imgui.SetTooltip(u8("Сводка по каждой заточенной карте за выбранный период"))
                    end
                    imgui.Spacing()

                    local cardsList = stats.improveCards
                    if type(cardsList) == 'table' and #cardsList > 0 then
                        local function renderCardRow(c, rowId)
                            local sLvl       = c.startLevel or 0
                            local eLvl       = c.endLevel or sLvl
                            local atk        = c.attempts or 0
                            local sp         = c.spent or 0
                            local oi         = c.oils or 0
                            local suc        = c.success or 0
                            local isSto      = c.isStorage == true
                            local progressed = eLvl > sLvl

                            imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.10, 0.12, 0.16, 1))
                            imgui.BeginChild("##cardrow_" .. rowId, imgui.ImVec2(0, 28), true,
                                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

                            if isSto then
                                local sLeft       = string.format(
                                    "{B0B0B0}#%d   {808080}ур.  {BEF781}%d   {C788FF}[ХР+]",
                                    c.slot or 0, sLvl)
                                local sRight      = string.format(
                                    "{FFFFFF}%d поп.    {BEF781}%d усп.",
                                    atk, suc)
                                local sLeftClean  = sLeft:gsub("{%x%x%x%x%x%x}", "")
                                local sRightClean = sRight:gsub("{%x%x%x%x%x%x}", "")
                                local totalW      = imgui.CalcTextSize(fa.LAYER_GROUP).x + 6
                                    + imgui.CalcTextSize(u8(sLeftClean)).x + 12
                                    + imgui.CalcTextSize(u8(sRightClean)).x
                                local startX      = math.max(8, (imgui.GetContentRegionAvail().x - totalW) / 2)

                                imgui.SetCursorPos(imgui.ImVec2(startX, (28 - imgui.GetTextLineHeight()) / 2))
                                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.78, 0.53, 1.0, 1))
                                imgui.Text(fa.LAYER_GROUP)
                                imgui.PopStyleColor()
                                imgui.SameLine(0, 6)
                                imgui.TextColoredRGB(sLeft)
                                imgui.SameLine(0, 12)
                                imgui.TextColoredRGB(sRight)
                            else
                                local arrowColor  = progressed and "{BEF781}" or "{808080}"
                                local arrowVec    = progressed and imgui.ImVec4(0.745, 0.945, 0.506, 1)
                                    or imgui.ImVec4(0.502, 0.502, 0.502, 1)
                                local sLeft       = string.format("{B0B0B0}#%d   {808080}ур.  %s%d",
                                    c.slot or 0, arrowColor, sLvl)
                                local sRight      = string.format(
                                    "%s%d    {FFFFFF}%d поп.    {BEF781}%d усп.    {FFD700}$%s    {87CEFA}%d см.",
                                    arrowColor, eLvl, atk, suc, utils.formatNumber(sp), oi)
                                local sLeftClean  = sLeft:gsub("{%x%x%x%x%x%x}", "")
                                local sRightClean = sRight:gsub("{%x%x%x%x%x%x}", "")
                                local totalW      = imgui.CalcTextSize(fa.MICROCHIP).x + 6
                                    + imgui.CalcTextSize(u8(sLeftClean)).x + 6
                                    + imgui.CalcTextSize(fa.ARROW_RIGHT).x + 6
                                    + imgui.CalcTextSize(u8(sRightClean)).x
                                local startX      = math.max(8, (imgui.GetContentRegionAvail().x - totalW) / 2)

                                imgui.SetCursorPos(imgui.ImVec2(startX, (28 - imgui.GetTextLineHeight()) / 2))
                                imgui.Text(fa.MICROCHIP)
                                imgui.SameLine(0, 6)
                                imgui.TextColoredRGB(sLeft)
                                imgui.SameLine(0, 6)
                                imgui.PushStyleColor(imgui.Col.Text, arrowVec)
                                imgui.Text(fa.ARROW_RIGHT)
                                imgui.PopStyleColor()
                                imgui.SameLine(0, 6)
                                imgui.TextColoredRGB(sRight)
                            end

                            imgui.EndChild()
                            imgui.PopStyleColor()

                            if isSto then
                                imgui.Hint(string.format(
                                    "Карта #%d (улучшение хранилища)\nУровень карты: %d (не меняется)\nПопыток: %d (успешных: %d)",
                                    c.slot or 0, sLvl, atk, suc))
                            else
                                imgui.Hint(string.format(
                                    "Карта #%d\nУровень: с %d до %d (Повышение на %d)\nПопыток: %d (успешных: %d)\nПотрачено: $%s\nСмазок: %d шт.",
                                    c.slot or 0, sLvl, eLvl, eLvl - sLvl, atk, suc,
                                    utils.formatNumber(sp), oi))
                            end
                        end

                        local sessions = {}
                        for _, c in ipairs(cardsList) do
                            local key = c.sessionId or ((c.date or '') .. '|' .. (c.time or ''))
                            if not sessions[key] then
                                sessions[key] = {
                                    key       = key,
                                    date      = c.date or '',
                                    time      = c.time or '',
                                    startedAt = c.startedAt,
                                    cards     = {},
                                }
                            end
                            table.insert(sessions[key].cards, c)
                        end
                        local sessKeys = {}
                        for k, _ in pairs(sessions) do table.insert(sessKeys, k) end
                        table.sort(sessKeys, function(a, b)
                            local sa, sb = sessions[a], sessions[b]
                            if sa.date ~= sb.date then
                                local function dkey(s)
                                    local d, m, y = s:match("(%d+)%.(%d+)%.(%d+)")
                                    return tonumber(string.format("%04d%02d%02d",
                                        tonumber(y) or 0, tonumber(m) or 0, tonumber(d) or 0)) or 0
                                end
                                return dkey(sa.date) > dkey(sb.date)
                            end
                            local sat, sbt = sa.startedAt or 0, sb.startedAt or 0
                            if sat > 0 and sbt > 0 then return sat > sbt end
                            return (sa.time or '') > (sb.time or '')
                        end)

                        local showDateInHeader = data.logsPeriodFilter ~= 1
                        local rowIdx = 0
                        for _, sk in ipairs(sessKeys) do
                            local sess              = sessions[sk]

                            local sumSpent, sumOils = 0, 0
                            local hasPerf, hasSto   = false, false
                            for _, c in ipairs(sess.cards) do
                                sumSpent = sumSpent + (c.spent or 0)
                                sumOils  = sumOils + (c.oils or 0)
                                if c.isStorage then hasSto = true else hasPerf = true end
                            end

                            local startStr = sess.startedAt and os.date('%H:%M', sess.startedAt) or sess.time

                            imgui.Spacing()
                            imgui.Text(fa.CLOCK)
                            imgui.SameLine(0, 6)
                            if showDateInHeader and sess.date ~= '' then
                                imgui.TextColoredRGB("{FFA500}" .. sess.date)
                                imgui.SameLine(0, 6)
                                imgui.TextColoredRGB("{B0B0B0}" .. startStr)
                            else
                                local headerLbl = (hasSto and not hasPerf) and "Хранилище" or "Заточка"
                                imgui.TextColoredRGB("{FFA500}" .. headerLbl)
                                imgui.SameLine(0, 6)
                                imgui.TextColoredRGB("{B0B0B0}" .. startStr)
                            end
                            imgui.SameLine(0, 12)
                            if hasSto and not hasPerf then
                                imgui.TextColoredRGB(string.format(
                                    "{808080}%d карт  ·  {C788FF}хранилище",
                                    #sess.cards))
                            elseif hasSto and hasPerf then
                                imgui.TextColoredRGB(string.format(
                                    "{808080}%d карт  ·  {FFD700}$%s  ·  {87CEFA}%d см.  ·  {C788FF}+хранилище",
                                    #sess.cards, utils.formatNumber(sumSpent), sumOils))
                            else
                                imgui.TextColoredRGB(string.format(
                                    "{808080}%d карт  ·  {FFD700}$%s  ·  {87CEFA}%d см.",
                                    #sess.cards, utils.formatNumber(sumSpent), sumOils))
                            end
                            imgui.Spacing()

                            table.sort(sess.cards, function(a, b)
                                local ea = a.endLevel or 0
                                local eb = b.endLevel or 0
                                if ea ~= eb then return ea > eb end
                                local ga = ea - (a.startLevel or 0)
                                local gb = eb - (b.startLevel or 0)
                                if ga ~= gb then return ga > gb end
                                return (a.spent or 0) > (b.spent or 0)
                            end)
                            for _, c in ipairs(sess.cards) do
                                rowIdx = rowIdx + 1
                                renderCardRow(c, rowIdx)
                            end
                        end
                    else
                        local availH = imgui.GetContentRegionAvail().y
                        local availW = imgui.GetContentRegionAvail().x
                        imgui.SetCursorPosY(imgui.GetCursorPosY() + math.max(0, availH / 2 - 40))
                        local iconW = imgui.CalcTextSize(fa.BOX_OPEN).x
                        imgui.SetCursorPosX((availW - iconW) / 2)
                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.25, 0.27, 0.32, 1))
                        imgui.Text(fa.BOX_OPEN)
                        imgui.PopStyleColor()
                        imgui.Spacing()
                        local txt1 = u8("Нет данных по картам")
                        local txt2 = u8("Запусти заточку — карты появятся здесь")
                        imgui.SetCursorPosX((availW - imgui.CalcTextSize(txt1).x) / 2)
                        imgui.TextColoredRGB("{CCCCCC}Нет данных по картам")
                        imgui.SetCursorPosX((availW - imgui.CalcTextSize(txt2).x) / 2)
                        imgui.TextColoredRGB("{808080}Запусти заточкиу— карты появятся здесь")
                    end
                    imgui.EndChild()
                    imgui.PopStyleColor()
                end
            end
            if data.logsResetConfirm then
                local isImprove = data.logsResetMode == "improve"
                renderResetConfirm(
                    "logsResetConfirm",
                    data.logsResetTimer,
                    isImprove and "Удалить логи заточки?" or "Удалить все логи действий?",
                    "Это действие необратимо.",
                    function()
                        if isImprove then
                            logsTool.clearImprove()
                            utils.addChat("{F78181}Логи заточки очищены.")
                        else
                            logsTool.clear()
                            utils.addChat("{F78181}Логи очищены.")
                        end
                        data.logsResetConfirm = false
                    end,
                    function() data.logsResetConfirm = false end)
            end
            imgui.End()
        end
    end
)

-- при заходе на ферму
imgui.OnFrame(function() return data.main[0] end, function(self)
    applyCustomStyle()
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
        if ButtonWithHint(fa.ARROW_LEFT .. "##left", "Переключиться на предыдущую ферму.",
                not data.working, buttonSize) then
            flashminerTool.navigate(-1)
        end

        imgui.SameLine(0, imgui.GetStyle().ItemSpacing.x + 5)

        if ButtonWithHint(fa.ARROW_RIGHT .. "##right", "Переключиться на следующую ферму.",
                not data.working, buttonSize) then
            flashminerTool.navigate(1)
        end
    else
        ButtonWithHint(fa.ARROW_LEFT .. "##left_disabled", "Доступно только в Флешке Майнера.",
            false, buttonSize)
        imgui.SameLine(0, imgui.GetStyle().ItemSpacing.x + 5)
        ButtonWithHint(fa.ARROW_RIGHT .. "##right_disabled", "Доступно только в Флешке Майнера.",
            false, buttonSize)
    end
end

function __i__bottomPanel()
    imgui.BeginChild('##bottom_panel_child', imgui.ImVec2(0, 0), false, imgui.WindowFlags.NoScrollbar)

    local style = imgui.GetStyle()
    local textLineHeight = imgui.GetTextLineHeight()
    local sliderHeight = textLineHeight + style.FramePadding.y * 2
    local staticContentHeight = (textLineHeight * 2) + sliderHeight + (style.ItemSpacing.y * 2)

    local availableHeight = imgui.GetContentRegionAvail().y
    local dynamicHeight = availableHeight - staticContentHeight
    local elementHeight = (dynamicHeight - (style.ItemSpacing.y * 3)) / 4 - 1

    if elementHeight < 20 then elementHeight = 20 end

    -- Ряд 1: Кнопка "Снять криптовалюту"
    local canWithdraw = data.forImgui.earnings.btc >= 1 or data.forImgui.earnings.asc >= 1
    local withdrawHint = canWithdraw and "Снять всю доступную криптовалюту" or "Нет криптовалюты для снятия"
    if data.working then withdrawHint = "Дождитесь завершения текущей операции" end

    if ButtonWithHint(u8 "Снять криптовалюту", withdrawHint,
            canWithdraw and not data.working, imgui.ImVec2(-1, elementHeight)) then
        coolantTool.resetSupplyFlag()
        local task = buildTaskTable('takeCrypto')
        task:takeCrypto()
    end

    -- Ряд 2: Кнопки "Включить/Выключить"
    local halfButtonWidth = (imgui.GetContentRegionAvail().x - style.ItemSpacing.x) / 2

    local switchOnHint = data.working and "Дождитесь завершения текущей операции" or "Включить все видеокарты"
    if ButtonWithHint(u8 "Включить видеокарты", switchOnHint, not data.working,
            imgui.ImVec2(halfButtonWidth, elementHeight)) then
        local task = buildTaskTable('switchCards')
        task:switchCards(true)
    end

    imgui.SameLine()

    local switchOffHint = data.working and "Дождитесь завершения текущей операции" or "Выключить все видеокарты"
    if ButtonWithHint(u8 "Выключить видеокарты", switchOffHint, not data.working,
            imgui.ImVec2(halfButtonWidth, elementHeight)) then
        local task = buildTaskTable('switchCards')
        task:switchCards(false)
    end

    -- Ряд 3: Кнопка "Залить жидкость"
    local canRefill = not data.isFlashminer and not data.working
    local coolantHint
    if data.isFlashminer then
        coolantHint = "Недоступно в флешке майнера"
    elseif data.working then
        coolantHint = "Дождитесь завершения текущей операции"
    else
        coolantHint = "Залить охлаждающую жидкость во все видеокарты"
    end


    if ButtonWithHint(u8 "Залить жидкость", coolantHint, canRefill, imgui.ImVec2(-1, elementHeight)) then
        local task = buildTaskTable('coolant')
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
    imgui.Hint("Использовать Супер Охлаждающую Жидкость вместо обычной.\n(Для  BTC карт и Asic Miner)")
    imgui.SameLine()
    if imgui.Checkbox(u8 "Режим Экономии##econom", imcfg.economyMode) then
        cfg.economyMode = imcfg.economyMode[0]; save()
    end
    imgui.Hint(
        "Включает экономию охлаждающей жидкости.\nРаботает только с обычными жидкостями и вне Вайс-Сити (и не для суперохлаждающих).\nКак это работает: если посли заливки одной жидкости уровень охлаждения достигает 70 и выше, то вторая жидкость не расходуется.\nБез этого режима скрипт всегда заполняет охлаждение до 100%.")

    imgui.SetCursorPosY(cursorY_after)

    imgui.Text(u8 "Порог срабатывания заливки:")
    imgui.TextDisabled(u8 "Если процент охлаждающей жидкости < настроенной ниже, то заливаем.")
    imgui.PushItemWidth(-1)
    if imgui.SliderInt("##coolantPercent", imcfg.useCoolantPercent, 1, 100) then
        cfg.useCoolantPercent = imcfg.useCoolantPercent[0]; save()
    end
    imgui.PopItemWidth()

    imgui.EndChild()
end

-- при флешке майнера
local function filterAndSortHouses(houses)
    local searchText = ffi.string(searchBuffer):lower()
    local filtered = {}

    local availableLevels = {}
    local levelsSet = {}
    for _, house in ipairs(houses) do
        local status = data.houseStatuses[house.house_number]
        if status and status.cardLevels then
            for lvl in pairs(status.cardLevels) do
                if not levelsSet[lvl] then
                    levelsSet[lvl] = true
                    table.insert(availableLevels, lvl)
                end
            end
        end
    end
    table.sort(availableLevels)

    local availableCities = {}
    local citiesSet = {}
    for _, house in ipairs(houses) do
        local city = (house.city and house.city ~= "") and house.city or "Неизвестно"
        if not citiesSet[city] then
            citiesSet[city] = true
            table.insert(availableCities, city)
        end
    end
    table.sort(availableCities)

    for _, house in ipairs(houses) do
        local status = data.houseStatuses[house.house_number]
        local isKnownNoBasement = houseFilter.hasNoBasement(house.house_number)
        local isExcluded = houseFilter.isExcluded(house.house_number)

        if not imcfg.showExcludedHouses[0] and isExcluded then
            goto continue
        end

        local matchSearch = searchText == "" or
            tostring(house.house_number):find(searchText, 1, true) or
            (house.city and house.city:lower():find(searchText, 1, true))
        if not matchSearch then goto continue end

        if currentStatusFilter[0] > 0 then
            local statusType = houseStatusHelper:determineStatus(house, status,
                cfg.excludedHouses[tostring(house.house_number)] or false, isKnownNoBasement)
            if currentStatusFilter[0] == 1 and statusType ~= 'good' then goto continue end
            if currentStatusFilter[0] == 2 and statusType ~= 'warning' then goto continue end
            if currentStatusFilter[0] == 3 and statusType ~= 'bad' then goto continue end
            if currentStatusFilter[0] == 4 and not isKnownNoBasement then goto continue end
        end

        local hasAnySelected = next(selectedCardLevels) ~= nil
        if hasAnySelected then
            local matchesAny = false
            for lvl, sel in pairs(selectedCardLevels) do
                if sel and status and status.cardLevels and status.cardLevels[lvl] then
                    matchesAny = true; break
                end
            end
            if not matchesAny then goto continue end
        end

        if next(selectedCities) ~= nil then
            local houseCity = (house.city and house.city ~= "") and house.city or "Неизвестно"
            local isCityToggled = selectedCities[houseCity] == true
            if data.cityFilterInvert then
                if not isCityToggled then goto continue end
            else
                if isCityToggled then goto continue end
            end
        end

        table.insert(filtered, house)
        ::continue::
    end

    -- Сортировка
    local sortIdx = imcfg.currentSort[0]
    if sortIdx == 0 then
        table.sort(filtered, function(a, b)
            if a.house_number == b.house_number then return false end
            if cfg.sortAscending then return a.house_number < b.house_number end
            return a.house_number > b.house_number
        end)
    elseif sortIdx == 1 then
        table.sort(filtered, function(a, b)
            local va, vb = a.balance or 0, b.balance or 0
            if va == vb then return a.house_number < b.house_number end
            if cfg.sortAscending then return va < vb end
            return va > vb
        end)
    elseif sortIdx == 2 then
        -- Циклы
        table.sort(filtered, function(a, b)
            local va, vb = a.cycles or 0, b.cycles or 0
            if va == vb then return a.house_number < b.house_number end
            if cfg.sortAscending then return va < vb end
            return va > vb
        end)
    elseif sortIdx == 3 then
        -- Жидкость
        table.sort(filtered, function(a, b)
            local sA = data.houseStatuses[a.house_number]
            local sB = data.houseStatuses[b.house_number]
            local va = (sA and sA.minCoolant) or 101
            local vb = (sB and sB.minCoolant) or 101
            if va == vb then return a.house_number < b.house_number end
            if cfg.sortAscending then return va < vb end
            return va > vb
        end)
    elseif sortIdx == 4 then
        -- Видеокарты
        table.sort(filtered, function(a, b)
            local sA = data.houseStatuses[a.house_number]
            local sB = data.houseStatuses[b.house_number]
            local countA, countB = 0, 0
            local hasSelected = next(selectedCardLevels) ~= nil
            if hasSelected then
                for lvl, sel in pairs(selectedCardLevels) do
                    if sel then
                        countA = countA +
                            ((sA and sA.cardLevels and sA.cardLevels[lvl] and sA.cardLevels[lvl].total) or 0)
                        countB = countB +
                            ((sB and sB.cardLevels and sB.cardLevels[lvl] and sB.cardLevels[lvl].total) or 0)
                    end
                end
            else
                if sA and sA.cardLevels then for _, v in pairs(sA.cardLevels) do countA = countA + v.total end end
                if sB and sB.cardLevels then for _, v in pairs(sB.cardLevels) do countB = countB + v.total end end
            end
            if countA == countB then return a.house_number < b.house_number end
            if cfg.sortAscending then return countA < countB end
            return countA > countB
        end)
    elseif sortIdx == 5 then
        -- Город
        table.sort(filtered, function(a, b)
            local va, vb = a.city or "", b.city or ""
            if va == vb then return a.house_number < b.house_number end
            if cfg.sortAscending then return va < vb end
            return va > vb
        end)
    end

    return filtered, availableLevels, availableCities
end

-- флешка майнера
imgui.OnFrame(function() return data.showHouseControlWindow[0] end, function(player)
    applyStyle()
    local sw, sh = getScreenResolution()
    imgui.SetNextWindowSize(imgui.ImVec2(1000, 680), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))

    if imgui.Begin(u8 "Mining Tools##MainWin", data.showHouseControlWindow,
            imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize) then
        imgui.customTitleBar(data.showHouseControlWindow, resetDefaultCfg, imgui.GetWindowWidth())

        local filteredHouses, availableLevels, availableCities = filterAndSortHouses(data.dialogData.flashminer)
        data.filteredHouses = filteredHouses
        -- Подсчет статистики
        local totalHouses = #data.dialogData.flashminer
        local housesGood, housesWarning, housesBad = 0, 0, 0
        local totalBalance, totalBTC, totalASC = 0, 0, 0
        local badHousesIssues = {}
        local warningHousesIssues = {}
        local totalCoolantsAll = 0

        for _, house in ipairs(data.dialogData.flashminer) do
            local status = data.houseStatuses[house.house_number]
            totalBalance = totalBalance + (house.balance or 0)

            if status then
                totalCoolantsAll = totalCoolantsAll + (status.coolantsNeeded or 0)
            end

            if not (status and status.lastCheck > 0) then goto continue end

            local earnings = status.earnings or {}
            totalBTC = totalBTC + (earnings.btc or 0)
            totalASC = totalASC + (earnings.asc or 0)

            local counters = { good = housesGood, warning = housesWarning, bad = housesBad }
            local issuesTables = { warning = warningHousesIssues, bad = badHousesIssues }

            if counters[status.status] then
                counters[status.status] = counters[status.status] + 1

                if issuesTables[status.status] and status.issues and #status.issues > 0 then
                    issuesTables[status.status][house.house_number] = status.issues
                end
            end

            housesGood, housesWarning, housesBad = counters.good, counters.warning, counters.bad

            ::continue::
        end

        local nearestMaintenanceHours = nil
        local nearestMaintenanceHouse = nil
        for _, house in ipairs(data.dialogData.flashminer) do
            if houseFilter.shouldProcess(house) then
                local status = data.houseStatuses[house.house_number]
                if status and status.lastCheck > 0 and status.minCoolant and status.minCoolant <= 100 then
                    local hours = utils.calculateRemainingHours(status.minCoolant)
                    if not nearestMaintenanceHours or hours < nearestMaintenanceHours then
                        nearestMaintenanceHours = hours
                        nearestMaintenanceHouse = house.house_number
                    end
                end
            end
        end

        -- Расчет общего дохода
        local allBtc, allAsc = 0, 0
        for _, h in ipairs(data.dialogData.flashminer) do
            local b, a = houseFilter.getDailyIncome(h.house_number)
            allBtc = allBtc + b
            allAsc = allAsc + a
        end

        -- Плитки статистики
        local availWidth = imgui.GetContentRegionAvail().x
        local statCardWidth = (availWidth - 24) / 4

        local function DrawStatTile(childId, icon, label, value, valColor, hintText)
            imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.09, 0.10, 0.14, 1.00))
            imgui.BeginChild("stat_" .. childId, imgui.ImVec2(statCardWidth, 36), true)

            local iconSize = imgui.CalcTextSize(icon)
            local labelParsed = label:gsub("{.-}", "")
            local labelSize = imgui.CalcTextSize(u8(labelParsed))
            local valueParsed = value:gsub("{.-}", "")
            local valueSize = imgui.CalcTextSize(u8(valueParsed))
            local totalWidth = iconSize.x + labelSize.x + valueSize.x + 10

            local startX = (statCardWidth - totalWidth) / 2

            imgui.SetCursorPos(imgui.ImVec2(startX, 10))

            imgui.BeginGroup()
            imgui.Text(icon)
            imgui.SameLine()
            imgui.TextColoredRGB(label)
            imgui.SameLine()
            imgui.TextColoredRGB(valColor .. value)
            imgui.EndGroup()

            if hintText then
                imgui.Hint(hintText)
            end

            imgui.EndChild()
            imgui.PopStyleColor()
        end


        -- Колонка 1: Общая информация
        DrawStatTile("houses", fa.HOUSE, "{87CEFA}Всего домов:", tostring(totalHouses), "{FFFFFF}",
            "Общее количество домов")
        imgui.SameLine()

        -- Колонка 2: Криптовалюта
        local cryptoText = formatEarnings(totalBTC, totalASC, not data.isRodina)
        local totalHint = string.format(
            "{FFFFFF}Общее количество криптовалюты для снятия.\n\n{BEF781}Общий доход всех ферм:\n{FFFFFF}%.3f BTC / день",
            allBtc)
        if allAsc > 0 then totalHint = totalHint .. string.format("\n{FFA500}%.3f ASC / день", allAsc) end

        DrawStatTile("crypto", fa.COINS, "{BEF781}Доступно:", cryptoText, "{FFFFFF}", totalHint)
        imgui.SameLine()

        -- Колонка 3: Общий баланс
        DrawStatTile("balance", fa.DOLLAR_SIGN, "{FFD700}Баланс:", "$" .. utils.formatNumber(totalBalance),
            "{FFFFFF}",
            "Общий баланс всех домов")
        imgui.SameLine()

        -- Колонка 4: Статусы домов
        local parts = {}
        if housesGood > 0 then table.insert(parts, string.format("{4DE94C}%d", housesGood)) end
        if housesWarning > 0 then table.insert(parts, string.format("{FFE133}%d", housesWarning)) end
        if housesBad > 0 then table.insert(parts, string.format("{FF3333}%d", housesBad)) end

        local statusText = #parts > 0 and table.concat(parts, " {FFFFFF}/ ") or "{808080}Не проверено"

        local hintLines = {
            "{FFFFFF}Сводка по состоянию домов:",
            "--------------------",
        }

        local function appendIssues(title, issuesMap)
            table.insert(hintLines, title)
            for houseNum, issues in pairs(issuesMap) do
                table.insert(hintLines, "  {FFA500}Дом №" .. houseNum .. ":")
                for _, issue in ipairs(issues) do
                    table.insert(hintLines, "    • " .. issue)
                end
            end
            table.insert(hintLines, "")
        end

        local hasIssues = false
        if next(badHousesIssues) ~= nil then
            hasIssues = true
            appendIssues(fa.CIRCLE_EXCLAMATION .. " {FF3333}Критические проблемы:", badHousesIssues)
        end
        if next(warningHousesIssues) ~= nil then
            hasIssues = true
            appendIssues(fa.TRIANGLE_EXCLAMATION .. " {FFE133}Требуют внимания:", warningHousesIssues)
        end
        if not hasIssues then
            table.insert(hintLines, fa.CIRCLE_CHECK .. " {4DE94C}Проблем не обнаружено.")
            table.insert(hintLines, "")
        end

        table.insert(hintLines, "--------------------")
        table.insert(hintLines, string.format(
            "{87CEFA}Всего требуется охлаждаек: {FFFFFF}%d шт.", totalCoolantsAll))

        if nearestMaintenanceHouse and nearestMaintenanceHours then
            table.insert(hintLines, "")
            table.insert(hintLines, string.format(
                "{FFA500}Ближайшее обслуживание:\n{FFFFFF}~%dч — Дом №%d",
                math.floor(nearestMaintenanceHours), nearestMaintenanceHouse))
        end

        local statusHint = table.concat(hintLines, "\n")

        DrawStatTile("status", fa.CHART_PIE, "{87CEFA}Состояние:", statusText, "{FFFFFF}", statusHint)


        local cache            = logsTool.getCacheSummary()
        local logTotalBtc      = cache.collectBtc
        local logTotalAsc      = cache.collectAsc
        local logTotalSessions = cache.sessions

        imgui.Spacing()

        local barH = 30
        local isLogsHovered = false

        imgui.PushStyleColor(imgui.Col.ChildBg,
            data.showLogsWindow[0]
            and imgui.ImVec4(0.12, 0.18, 0.28, 1.00)
            or imgui.ImVec4(0.09, 0.10, 0.14, 1.00))
        imgui.BeginChild("##logsSummaryBar", imgui.ImVec2(0, barH), true,
            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

        local ww = imgui.GetWindowWidth()

        imgui.SetCursorPos(imgui.ImVec2(12, (barH - imgui.GetTextLineHeight()) / 2))
        imgui.BeginGroup()
        imgui.Text(fa.CLOCK_ROTATE_LEFT)
        imgui.SameLine(0, 6)

        local summaryStr
        if logTotalSessions == 0 then
            summaryStr = u8 "Нет записей"
        else
            summaryStr = u8(string.format("Собрано за всё время: %d BTC", logTotalBtc))
            if logTotalAsc > 0 then
                summaryStr = summaryStr .. u8(string.format("  /  %d ASC", logTotalAsc))
            end
            summaryStr = summaryStr .. u8(string.format("   ·   %d записей", logTotalSessions))
        end
        imgui.Text(summaryStr)
        imgui.EndGroup()

        local arrowIcon = data.showLogsWindow[0] and fa.CHEVRON_UP or fa.CHEVRON_DOWN
        local arrowW = imgui.CalcTextSize(arrowIcon).x
        imgui.SetCursorPos(imgui.ImVec2(ww - arrowW - 14, (barH - imgui.GetTextLineHeight()) / 2))
        imgui.TextDisabled(arrowIcon)

        imgui.SetCursorPos(imgui.ImVec2(0, 0))
        if imgui.InvisibleButton("##logsBarBtn", imgui.ImVec2(ww, barH)) then
            data.showLogsWindow[0] = not data.showLogsWindow[0]
        end
        isLogsHovered = imgui.IsItemHovered()
        if isLogsHovered then
            imgui.SetTooltip(u8(data.showLogsWindow[0] and "Закрыть историю" or "Открыть историю"))
        end

        imgui.EndChild()
        imgui.PopStyleColor()
        imgui.Spacing()

        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.09, 0.10, 0.14, 1.00))
        imgui.BeginChild("##action_panel", imgui.ImVec2(0, 60), true)
        imgui.showNotifications(2)

        local btnWidth = (availWidth - 55) / 5
        local btnHeight = 35

        local function DrawActionBtn(label, icon, colorVec, taskName, arg)
            imgui.PushStyleColor(imgui.Col.Button, colorVec)
            imgui.PushStyleColor(imgui.Col.ButtonHovered,
                imgui.ImVec4(colorVec.x * 1.2, colorVec.y * 1.2, colorVec.z * 1.2, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,
                imgui.ImVec4(colorVec.x * 0.8, colorVec.y * 0.8, colorVec.z * 0.8, 1.0))

            local pressed = imgui.Button(icon .. " " .. u8(label), imgui.ImVec2(btnWidth, btnHeight))
            imgui.PopStyleColor(3)

            if pressed then
                if data.selectedHouseIndex and data.dialogData.flashminer[data.selectedHouseIndex] then
                    data.lastSelectedHouse = data.dialogData.flashminer[data.selectedHouseIndex].house_number
                end

                local task = buildTaskTable(taskName)
                runTaskAndReopenDialog(function() task:run(arg) end)
            end

            return pressed
        end

        DrawActionBtn("Собрать", fa.DOLLAR_SIGN, imgui.ImVec4(0.3, 0.8, 0.3, 1), "collectFromAllHouses")
        imgui.Hint("Собрать криптовалюту со всех домов")

        imgui.SameLine()
        DrawActionBtn("Включить", fa.POWER_OFF, imgui.ImVec4(0.2, 0.6, 1, 1), "massSwitchCards", true)
        imgui.Hint("Включить все видеокарты во всех домах")

        imgui.SameLine()
        DrawActionBtn("Выключить", fa.PLUG, imgui.ImVec4(1, 0.3, 0.3, 1), "massSwitchCards", false)
        imgui.Hint("Выключить все видеокарты во всех домах")

        imgui.SameLine()
        DrawActionBtn("Обновить", fa.ROTATE, imgui.ImVec4(0.8, 0.6, 0.2, 1), "updateStatuses")
        imgui.Hint("Обновить статусы всех домов.\nНе проверяет наличие подвалов.")

        imgui.SameLine()
        local fixLabel, fixIcon, fixColor, fixHint
        if cfg.useSimpleTopUp then
            fixLabel = "Пополнить баланс"
            fixIcon  = fa.DOLLAR_SIGN
            fixColor = imgui.ImVec4(0.4, 0.7, 0.4, 1)
            fixHint  = "Пополнить баланс ферм до целевого значения"
        elseif not cfg.fixTopUpEnabled then
            fixLabel = "Авто-обслуживание"
            fixIcon  = fa.WAND_MAGIC_SPARKLES
            fixColor = imgui.ImVec4(0.6, 0.4, 0.9, 1)
            fixHint  = "Собрать крипту\nВключить видеокарты\n{808080}(пополнение баланса выключено)"
        else
            fixLabel = "Авто-обслуживание"
            fixIcon  = fa.WAND_MAGIC_SPARKLES
            fixColor = imgui.ImVec4(0.6, 0.4, 0.9, 1)
            fixHint  = "Пополнить баланс ферм\nСобрать криптовалюту\nВключить видеокарты"
        end
        DrawActionBtn(fixLabel, fixIcon, fixColor, "fixAllProblems")
        imgui.Hint(fixHint)

        imgui.EndChild()
        imgui.PopStyleColor()

        imgui.Spacing()

        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.08, 0.09, 0.12, 1.00))
        imgui.BeginChild("##searchBar", imgui.ImVec2(availWidth, 45), true)
        imgui.SetCursorPos(imgui.ImVec2(8, 7))

        -- Поиск
        imgui.PushItemWidth(250)
        imgui.InputTextWithHint("##search", u8 "Поиск по дому / городу", searchBuffer, 256)
        imgui.PopItemWidth()

        imgui.SameLine()
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 5)

        -- Фильтр Статуса
        imgui.PushItemWidth(130)
        if imgui.BeginCombo("##status", statusItems[currentStatusFilter[0] + 1]) then
            for i = 1, #statusItems do
                local isSelected = (currentStatusFilter[0] == i - 1)
                if imgui.Selectable(statusItems[i], isSelected) then
                    currentStatusFilter[0] = i - 1
                end
            end
            imgui.EndCombo()
        end
        imgui.PopItemWidth()

        imgui.SameLine()
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 5)

        -- Сортировка
        imgui.PushItemWidth(150)
        if imgui.BeginCombo("##sort", sortItems[imcfg.currentSort[0] + 1]) then
            for i = 1, #sortItems do
                local isSelected = (imcfg.currentSort[0] == i - 1)

                if i == 5 then
                    -- По видеокартам
                    local startPos = imgui.GetCursorPos()
                    local itemW = imgui.GetContentRegionAvail().x
                    local screenPos = imgui.GetCursorScreenPos()

                    imgui.Selectable("##sort5", isSelected, 0, imgui.ImVec2(itemW, 0))
                    if imgui.IsItemClicked() then
                        imcfg.currentSort[0] = 4
                        cfg.currentSort = 4
                        save()
                    end
                    if imgui.IsItemHovered() then
                        data.levelFilterItemRect = {
                            x1 = screenPos.x,
                            y1 = screenPos.y,
                            x2 = screenPos.x + itemW,
                            y2 = screenPos.y + imgui.GetTextLineHeightWithSpacing()
                        }
                        imgui.OpenPopup("##levelFilterPopup")
                        data.levelFilterOpenTime = os.clock()
                    end
                    imgui.SetCursorPos(startPos)
                    imgui.BeginGroup()
                    imgui.Text(sortItems[i])
                    imgui.SameLine()
                    imgui.Text(fa.CARET_RIGHT)
                    imgui.EndGroup()
                elseif i == 6 then
                    -- По городу
                    local startPos = imgui.GetCursorPos()
                    local itemW = imgui.GetContentRegionAvail().x
                    local screenPos = imgui.GetCursorScreenPos()

                    imgui.Selectable("##sort6", isSelected, 0, imgui.ImVec2(itemW, 0))
                    if imgui.IsItemClicked() then
                        imcfg.currentSort[0] = 5
                        cfg.currentSort = 5
                        save()
                    end
                    if imgui.IsItemHovered() then
                        data.cityFilterItemRect = {
                            x1 = screenPos.x,
                            y1 = screenPos.y,
                            x2 = screenPos.x + itemW,
                            y2 = screenPos.y + imgui.GetTextLineHeightWithSpacing()
                        }
                        imgui.OpenPopup("##cityFilterPopup")
                        data.cityFilterOpenTime = os.clock()
                    end
                    imgui.SetCursorPos(startPos)
                    imgui.BeginGroup()
                    imgui.Text(sortItems[i])
                    imgui.SameLine()
                    imgui.Text(fa.CARET_RIGHT)
                    imgui.EndGroup()
                else
                    if imgui.Selectable(sortItems[i], isSelected) then
                        imcfg.currentSort[0] = i - 1
                        cfg.currentSort = i - 1
                        save()
                    end
                end
            end

            imgui.SetNextWindowPos(
                imgui.ImVec2(
                    imgui.GetWindowPos().x + imgui.GetWindowSize().x + 2,
                    imgui.GetWindowPos().y + 85
                ),
                imgui.Cond.Always
            )
            if imgui.BeginPopup("##levelFilterPopup") then
                local winPos = imgui.GetWindowPos()
                local winSize = imgui.GetWindowSize()
                local mousePos = imgui.GetIO().MousePos

                local timeSinceOpen = (os.clock() - data.levelFilterOpenTime) * 1000
                if timeSinceOpen > 200 and winSize.x > 10 then
                    local isOverPopup = mousePos.x >= winPos.x - 30
                        and mousePos.x <= winPos.x + winSize.x + 5
                        and mousePos.y >= winPos.y - 5
                        and mousePos.y <= winPos.y + winSize.y + 5

                    local isOverComboItem = data.levelFilterItemRect ~= nil
                        and mousePos.x >= data.levelFilterItemRect.x1
                        and mousePos.x <= data.levelFilterItemRect.x2
                        and mousePos.y >= data.levelFilterItemRect.y1
                        and mousePos.y <= data.levelFilterItemRect.y2

                    if not isOverPopup and not isOverComboItem then
                        imgui.CloseCurrentPopup()
                    end
                end

                local hasAnySelected = next(selectedCardLevels) ~= nil
                if hasAnySelected then
                    if imgui.Selectable(u8("Сбросить всё"), false) then
                        selectedCardLevels = {}
                    end
                else
                    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0, 0, 0, 0))
                    imgui.Selectable(u8("Сбросить всё"), false,
                        imgui.SelectableFlags.Disabled)
                    imgui.PopStyleColor()
                end
                imgui.Separator()

                local _, availableLevels2 = filterAndSortHouses(data.dialogData.flashminer)

                if #availableLevels2 == 0 then
                    imgui.TextDisabled(u8("Нет данных. Обновите статусы."))
                else
                    for _, lvl in ipairs(availableLevels2) do
                        local isLvlSelected = selectedCardLevels[lvl] == true

                        local count = 0
                        for _, h in ipairs(data.dialogData.flashminer) do
                            local s = data.houseStatuses[h.house_number]
                            if s and s.cardLevels and s.cardLevels[lvl] then count = count + 1 end
                        end

                        imgui.PushStyleColor(imgui.Col.HeaderHovered, imgui.ImVec4(0.2, 0.4, 0.8, 0.4))
                        imgui.PushStyleColor(imgui.Col.Header,
                            isLvlSelected and imgui.ImVec4(0.2, 0.5, 0.9, 0.3) or imgui.ImVec4(0, 0, 0, 0))

                        local startPos2 = imgui.GetCursorPos()
                        local itemWidth = imgui.GetContentRegionAvail().x

                        if imgui.Selectable("##lvl_" .. lvl, isLvlSelected,
                                imgui.SelectableFlags.DontClosePopups,
                                imgui.ImVec2(itemWidth, 0)) then
                            if isLvlSelected then
                                selectedCardLevels[lvl] = nil
                            else
                                selectedCardLevels[lvl] = true
                            end
                        end
                        imgui.PopStyleColor(2)

                        imgui.SetCursorPos(startPos2)
                        imgui.BeginGroup()
                        if isLvlSelected then
                            imgui.Text(fa.CHECK)
                            imgui.SameLine(0, 5)
                        else
                            local iconW = imgui.CalcTextSize(fa.CHECK).x
                            imgui.SetCursorPosX(imgui.GetCursorPosX() + iconW + 5)
                        end
                        imgui.Text(u8(string.format("Уровень %d", lvl)))
                        imgui.SameLine(0, 5)
                        imgui.TextDisabled(string.format("(%d)", count))
                        imgui.EndGroup()
                    end
                end

                imgui.EndPopup()
            end
            imgui.SetNextWindowPos(
                imgui.ImVec2(
                    imgui.GetWindowPos().x + imgui.GetWindowSize().x + 2,
                    imgui.GetWindowPos().y + 85
                ),
                imgui.Cond.Always
            )
            if imgui.BeginPopup("##cityFilterPopup") then
                local winPos = imgui.GetWindowPos()
                local winSize = imgui.GetWindowSize()
                local mousePos = imgui.GetIO().MousePos

                local timeSinceOpen = (os.clock() - data.cityFilterOpenTime) * 1000
                if timeSinceOpen > 200 and winSize.x > 10 then
                    local isOverPopup = mousePos.x >= winPos.x - 30
                        and mousePos.x <= winPos.x + winSize.x + 5
                        and mousePos.y >= winPos.y - 5
                        and mousePos.y <= winPos.y + winSize.y + 5

                    local isOverComboItem = data.cityFilterItemRect ~= nil
                        and mousePos.x >= data.cityFilterItemRect.x1
                        and mousePos.x <= data.cityFilterItemRect.x2
                        and mousePos.y >= data.cityFilterItemRect.y1
                        and mousePos.y <= data.cityFilterItemRect.y2

                    if not isOverPopup and not isOverComboItem then
                        imgui.CloseCurrentPopup()
                    end
                end

                -- Переключатель режима
                local modeLabel = data.cityFilterInvert
                    and u8 "Только выбранные"
                    or u8 "Все кроме выбранных"
                if imgui.Selectable(modeLabel .. "##cityModeToggle", false,
                        imgui.SelectableFlags.DontClosePopups) then
                    data.cityFilterInvert = not data.cityFilterInvert
                end
                imgui.Hint(data.cityFilterInvert
                    and "Показывать ТОЛЬКО отмеченные города.\nНажмите для переключения."
                    or "Скрывать отмеченные города.\nНажмите для переключения.")
                imgui.Separator()

                local hasAnyCitySel = next(selectedCities) ~= nil
                if hasAnyCitySel then
                    if imgui.Selectable(u8 "Сбросить всё", false) then
                        selectedCities = {}
                    end
                else
                    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0, 0, 0, 0))
                    imgui.Selectable(u8 "Сбросить всё", false, imgui.SelectableFlags.Disabled)
                    imgui.PopStyleColor()
                end
                imgui.Separator()

                local _, _, availableCities2 = filterAndSortHouses(data.dialogData.flashminer)

                if not availableCities2 or #availableCities2 == 0 then
                    imgui.TextDisabled(u8 "Нет данных. Откройте /flashminer.")
                else
                    for _, city in ipairs(availableCities2) do
                        local isCitySel = selectedCities[city] == true

                        local cityCount = 0
                        for _, h in ipairs(data.dialogData.flashminer) do
                            local c = (h.city and h.city ~= "") and h.city or "Неизвестно"
                            if c == city then cityCount = cityCount + 1 end
                        end

                        imgui.PushStyleColor(imgui.Col.HeaderHovered, imgui.ImVec4(0.2, 0.4, 0.8, 0.4))
                        imgui.PushStyleColor(imgui.Col.Header,
                            isCitySel and imgui.ImVec4(0.2, 0.5, 0.9, 0.3) or imgui.ImVec4(0, 0, 0, 0))

                        local startPosC = imgui.GetCursorPos()
                        local itemWC = imgui.GetContentRegionAvail().x

                        if imgui.Selectable("##city_" .. city, isCitySel,
                                imgui.SelectableFlags.DontClosePopups,
                                imgui.ImVec2(itemWC, 0)) then
                            if isCitySel then
                                selectedCities[city] = nil
                            else
                                selectedCities[city] = true
                            end
                        end
                        imgui.PopStyleColor(2)

                        imgui.SetCursorPos(startPosC)
                        imgui.BeginGroup()
                        if isCitySel then
                            imgui.Text(fa.CHECK)
                            imgui.SameLine(0, 5)
                        else
                            local iconWC = imgui.CalcTextSize(fa.CHECK).x
                            imgui.SetCursorPosX(imgui.GetCursorPosX() + iconWC + 5)
                        end
                        imgui.Text(u8(city))
                        imgui.SameLine(0, 5)
                        imgui.TextDisabled(string.format("(%d)", cityCount))
                        imgui.EndGroup()
                    end
                end

                imgui.EndPopup()
            end

            imgui.EndCombo()
        end
        imgui.PopItemWidth()

        imgui.SameLine()
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 5)
        local sortIcon = cfg.sortAscending and fa.ARROW_UP_SHORT_WIDE or fa.ARROW_DOWN_WIDE_SHORT
        if imgui.Button(sortIcon .. "##sortDirection", imgui.ImVec2(35, 0)) then
            cfg.sortAscending = not cfg.sortAscending
            save()
        end
        imgui.Hint(cfg.sortAscending and "Сортировка: по возрастанию\nНажмите для сортировки по убыванию" or
            "Сортировка: по убыванию\nНажмите для сортировки по возрастанию")

        imgui.SameLine()
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 5)

        imgui.SameLine()
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 10)

        if imgui.Checkbox(u8 "Показывать пропускаемые", imcfg.showExcludedHouses) then
            cfg.showExcludedHouses = imcfg.showExcludedHouses[0]
            save()
        end
        imgui.Hint("Показать или скрыть дома, которые помечены как 'Пропускать'")

        imgui.EndChild()
        imgui.PopStyleColor()

        imgui.Text(u8(string.format("Список домов (%d из %d)", #filteredHouses, totalHouses)))
        imgui.Spacing()
        if data.working then
            __i__progressPanel()
        else
            if imgui.BeginChild("##scrollArea", imgui.ImVec2(0, 0), false, imgui.WindowFlags.NoScrollWithMouse) then
                local itemHeight = 130
                imgui.Scroller("house_list", itemHeight, 400,
                    imgui.HoveredFlags.RectOnly + imgui.HoveredFlags.ChildWindows)

                if data.scrollToSelection then
                    local targetIndex = nil
                    for i, house in ipairs(filteredHouses) do
                        if data.selectedHouseIndex then
                            local selectedHouse = data.dialogData.flashminer[data.selectedHouseIndex]
                            if selectedHouse and house.house_number == selectedHouse.house_number then
                                targetIndex = i
                                break
                            end
                        end
                    end

                    if targetIndex then
                        local columns = 2
                        local rowIndex = math.ceil(targetIndex / columns)
                        local targetScroll = (rowIndex - 1) * itemHeight
                        local scrollMax = imgui.GetScrollMaxY()

                        if targetScroll < 0 then targetScroll = 0 end
                        if targetScroll > scrollMax then targetScroll = scrollMax end

                        imgui.ScrollToPosition("house_list", targetScroll, 400)
                    end

                    data.scrollToSelection = false
                end

                local columns = 2
                local spacing = 10
                local regionW = imgui.GetContentRegionAvail().x
                local cardW = (regionW - spacing * (columns - 1)) / columns
                local cardH = 120

                for i, house in ipairs(filteredHouses) do
                    local status = data.houseStatuses[house.house_number]
                    local isKnownNoBasement = houseFilter.hasNoBasement(house.house_number)
                    local isExcluded = houseFilter.isExcluded(house.house_number)

                    local statusType
                    if isExcluded then
                        statusType = 'excluded'
                    else
                        statusType = houseStatusHelper:determineStatus(house, status, isExcluded, isKnownNoBasement)
                    end

                    local statusColor
                    local statusIcon
                    if isKnownNoBasement then
                        statusColor = imgui.ImVec4(0.5, 0.5, 0.5, 1.0)
                        statusIcon = fa.XMARK
                    elseif statusType == 'excluded' then
                        statusColor = imgui.ImVec4(0.38, 0.42, 0.60, 1.0)
                        statusIcon = fa.BAN
                    else
                        statusColor = houseStatusHelper:getColor(statusType)
                        statusIcon = houseStatusHelper:getIcon(statusType)
                    end

                    local tooltipText = houseStatusHelper:buildTooltip(status, house, isKnownNoBasement)
                    local stripeColor = statusColor

                    local statusText = ""
                    if isKnownNoBasement then
                        statusText = "{808080}Нет подвала"
                    elseif isExcluded then
                        statusText = "{808080}Пропускается"
                    elseif statusType == 'good' then
                        statusText = "{4DE94C}Работает"
                    elseif statusType == 'warning' then
                        statusText = "{FFE133}Внимание"
                    elseif statusType == 'bad' then
                        statusText = "{FF3333}Проблема"
                    else
                        statusText = "{808080}Не проверено"
                    end

                    if (i - 1) % columns ~= 0 then imgui.SameLine(0, spacing) end

                    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.12, 0.13, 0.17, 1.00))
                    imgui.BeginChild("house_card_" .. i, imgui.ImVec2(cardW, cardH), false)
                    local barW = 140
                    local rightColX = cardW - barW - 10
                    local p = imgui.GetCursorScreenPos()
                    local dl = imgui.GetWindowDrawList()

                    local maxGlowWidth = 30
                    local glowSteps = 25

                    for step = glowSteps, 1, -1 do
                        local progress = step / glowSteps
                        local width = 4 + (maxGlowWidth * progress)
                        local alpha = 0.25 * (1 - progress) * progress * 2

                        local layerColor = imgui.ImVec4(
                            stripeColor.x,
                            stripeColor.y,
                            stripeColor.z,
                            alpha
                        )

                        dl:AddRectFilled(
                            imgui.ImVec2(p.x, p.y),
                            imgui.ImVec2(p.x + width, p.y + cardH),
                            imgui.ColorConvertFloat4ToU32(layerColor),
                            6.0,
                            5
                        )
                    end
                    dl:AddRectFilled(
                        imgui.ImVec2(p.x, p.y),
                        imgui.ImVec2(p.x + 4, p.y + cardH),
                        imgui.ColorConvertFloat4ToU32(stripeColor),
                        6.0,
                        5
                    )

                    -- Контент карточки
                    imgui.SetCursorPos(imgui.ImVec2(16, 8))

                    -- Строка 1: Дом и Город
                    imgui.BeginGroup()
                    imgui.Text(fa.HOUSE)
                    imgui.SameLine()
                    imgui.TextColoredRGB(string.format("{FFFFFF}Дом {FFA500}№%d {FFFFFF}- %s", house.house_number,
                        house.city or "Неизвестно"))
                    imgui.EndGroup()
                    imgui.Hint("ПКМ для дополнительных действий")

                    imgui.SameLine()
                    -- Циклы справа
                    if not isKnownNoBasement and house.cycles then
                        imgui.BeginGroup()
                        local cyclesColor = house.cycles > 100 and "{4DE94C}" or "{FFE133}"
                        local cyclesStr = string.format("%s%d {808080}цикл.", cyclesColor, house.cycles)
                        imgui.SetCursorPosX(rightColX)
                        imgui.Text(fa.ROTATE)
                        imgui.SameLine(0, 3)
                        imgui.TextColoredRGB(cyclesStr)
                        imgui.EndGroup()
                        imgui.Hint("Количество оплаченных циклов")
                    end

                    -- Строка 2: Статус и Баланс

                    imgui.SetCursorPos(imgui.ImVec2(16, 32))
                    imgui.BeginGroup()
                    imgui.Text(statusIcon)
                    imgui.SameLine()
                    imgui.TextColoredRGB(statusText)
                    imgui.EndGroup()
                    imgui.Hint(tooltipText)

                    imgui.SameLine()
                    local balStr = string.format("{FFFFFF}$%s", utils.formatNumber(house.balance or 0))
                    imgui.SetCursorPosX(rightColX)
                    imgui.BeginGroup()
                    imgui.TextColored(imgui.ImVec4(1.0, 0.84, 0.0, 1.0), fa.DOLLAR_SIGN)
                    imgui.SameLine(0, 3)
                    imgui.TextColoredRGB(balStr)
                    imgui.EndGroup()
                    imgui.Hint(string.format("Баланс дома: $%s / $%s",
                        utils.formatNumber(house.balance or 0),
                        utils.formatNumber(house.max_balance or 0)))

                    -- Строка 3: Криптовалюта и Налог

                    imgui.SetCursorPos(imgui.ImVec2(16, 52))
                    imgui.BeginGroup()
                    imgui.TextColored(imgui.ImVec4(0.75, 0.97, 0.51, 1.0), fa.COINS)
                    imgui.SameLine()
                    imgui.Text(u8 "Крипта:")
                    imgui.SameLine()

                    if not isKnownNoBasement then
                        if status and status.lastCheck > 0 and status.earnings then
                            local earnings = formatEarnings(
                                status.earnings.btc >= 1 and status.earnings.btc or 0,
                                status.earnings.asc >= 1 and status.earnings.asc or 0,
                                not data.isRodina
                            )
                            if earnings == "{808080}0" then
                                earnings = "{808080}Нет"
                            end
                            imgui.TextColoredRGB(earnings)

                            local dBtc, dAsc = houseFilter.getDailyIncome(house.house_number)
                            if dBtc > 0 or dAsc > 0 then
                                local incomeStr = string.format("{BEF781}Доход в день:\n{FFFFFF}%.3f BTC", dBtc)
                                if dAsc > 0 then incomeStr = incomeStr .. string.format(" / %.3f ASC", dAsc) end
                                imgui.EndGroup()
                                imgui.Hint(incomeStr)
                            else
                                imgui.EndGroup()
                                imgui.Hint(
                                    "{808080}Доход в день: считаем...\n(Зайдите в этот дом еще раз через 10 минут)")
                            end
                        else
                            imgui.TextColoredRGB("{808080}Не проверено")
                            imgui.EndGroup()
                        end
                    else
                        imgui.TextColoredRGB("{808080}Нет данных")
                        imgui.EndGroup()
                    end


                    -- Налог
                    imgui.SameLine()
                    imgui.SetCursorPosX(rightColX)
                    imgui.BeginGroup()

                    imgui.Text(fa.FILE_INVOICE_DOLLAR)
                    imgui.SameLine()
                    imgui.Text(u8 "Налог:")
                    imgui.SameLine()
                    if house.tax then
                        local taxColor = house.tax >= 90000 and "{FF3333}" or
                            (house.tax >= 50000 and "{FFE133}" or "{FFFFFF}")
                        imgui.TextColoredRGB(taxColor .. "$" .. utils.formatNumber(house.tax))
                    else
                        imgui.TextColoredRGB("{808080}Н/Д")
                    end
                    imgui.EndGroup()
                    imgui.Hint("Текущий налог на дом")

                    -- Строка 4: Видеокарты и Жидкость
                    imgui.SetCursorPos(imgui.ImVec2(16, 72))
                    imgui.BeginGroup()
                    -- Видеокарты
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

                        local cardTooltip = table.concat(tooltipLines, "\n")
                        imgui.Text(fa.MICROCHIP)
                        imgui.SameLine()
                        imgui.TextColoredRGB(cardText)
                        imgui.EndGroup()
                        imgui.Hint(cardTooltip)
                    else
                        imgui.Text(fa.MICROCHIP)
                        imgui.SameLine()
                        imgui.TextColoredRGB("{808080}Карты: нет данных")
                        imgui.EndGroup()
                    end

                    imgui.SameLine()
                    local barW = 140
                    imgui.SetCursorPosX(rightColX)
                    imgui.SetCursorPosY(imgui.GetCursorPosY() + 2)

                    if not isKnownNoBasement then
                        if status and status.lastCheck > 0 and status.minCoolant <= 100 then
                            local coolantFraction = status.minCoolant / 100.0
                            local barColor
                            local threshold = cfg.useCoolantPercent / 100.0
                            local midpoint = threshold + (1.0 - threshold) / 2.0
                            if coolantFraction < threshold then
                                barColor = imgui.ImVec4(1, 0.2, 0.2, 1)
                            elseif coolantFraction < midpoint then
                                barColor = imgui.ImVec4(1, 0.88, 0.2, 1)
                            else
                                barColor = imgui.ImVec4(0.3, 0.8, 1, 1)
                            end

                            local needed = status.coolantsNeeded or 0
                            local barLabel = needed > 0
                                and u8(string.format("%.1f%% · нужно %d", status.minCoolant, needed))
                                or string.format("%.1f%%", status.minCoolant)
                            imgui.PushStyleColor(imgui.Col.PlotHistogram, barColor)
                            imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.2, 0.2, 0.2, 1.0))
                            imgui.ProgressBar(coolantFraction, imgui.ImVec2(barW, 15), barLabel)
                            imgui.PopStyleColor(2)

                            local currentNeeded = status.coolantsNeeded or 0
                            local targetText = cfg.economyMode and "до 70%" or "до 100%"

                            local hasAsic = false
                            if status.cardLevels then
                                for _, lvl in pairs(status.cardLevels) do
                                    if (lvl.btc and lvl.btc.total > 0) and (lvl.asc and lvl.asc.total > 0) then
                                        hasAsic = true; break
                                    end
                                end
                            end

                            local coolantHint = string.format(
                                "{FFFFFF}Минимальный уровень жидкости: {ffa500}%.2f%%\n" ..
                                "{FFFFFF}Порог заливки: {ffa500}%d%%\n" ..
                                "{FFFFFF}Цель заливки: {ffa500}%s\n\n",
                                status.minCoolant, cfg.useCoolantPercent, targetText
                            )

                            if currentNeeded > 0 then
                                coolantHint = coolantHint ..
                                    string.format("{BEF781}Требуется охл. жидкости: {FFFFFF}%d шт.", currentNeeded)
                            else
                                coolantHint = coolantHint .. "{808080}Заливка не требуется (выше порога)."
                            end

                            if hasAsic then
                                coolantHint = coolantHint .. "\n{FFA500}Есть ASIC карты (BTC+ASC)"
                            end

                            imgui.Hint(coolantHint)
                        else
                            imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.2, 0.2, 0.2, 1.0))
                            imgui.ProgressBar(0, imgui.ImVec2(barW, 15), u8 "Нет данных")
                            imgui.PopStyleColor()
                        end
                    else
                        imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.2, 0.2, 0.2, 1.0))
                        imgui.ProgressBar(0, imgui.ImVec2(barW, 15), u8 "Нет подвала")
                        imgui.PopStyleColor()
                    end

                    -- Строка 5: Время работы
                    imgui.SetCursorPos(imgui.ImVec2(16, 94))
                    imgui.BeginGroup()
                    local hoursLeft = nil
                    if status and status.lastCheck > 0 and status.minCoolant <= 100 then
                        hoursLeft = math.floor(utils.calculateRemainingHours(status.minCoolant or 0))
                    end

                    if hoursLeft and hoursLeft > 0 then
                        imgui.TextColoredRGB('{ffffff}Проработает: {ffa500}~' .. hoursLeft .. ' {ffffff}часов')
                        imgui.EndGroup()
                        imgui.Hint('Примерное оставшееся время до обслуживания фермы')
                    else
                        imgui.TextColoredRGB('{808080}Проработает: нет данных')
                        imgui.EndGroup()
                    end

                    if isExcluded then
                        imgui.SameLine()
                        imgui.SetCursorPosX(cardW - 140)
                        imgui.BeginGroup()
                        imgui.TextColored(imgui.ImVec4(1.0, 0.42, 0.42, 1.0), fa.BAN)
                        imgui.SameLine()
                        imgui.TextColoredRGB("{FF6B6B}Пропускается")
                        imgui.EndGroup()
                        imgui.Hint("Дом будет пропущен во всех массовых действиях")
                    end

                    local isSelected = false
                    local isHovered = false

                    if data.selectedHouseIndex then
                        local selectedHouse = data.dialogData.flashminer[data.selectedHouseIndex]
                        if selectedHouse and selectedHouse.house_number == house.house_number then
                            isSelected = true
                        end
                    end

                    imgui.SetCursorPos(imgui.ImVec2(0, 0))
                    local isClickable = not isKnownNoBasement
                    if isClickable then
                        if imgui.InvisibleButton("btn_house_" .. i, imgui.ImVec2(cardW, cardH)) then
                            for origIdx, origHouse in ipairs(data.dialogData.flashminer) do
                                if origHouse.house_number == house.house_number then
                                    data.selectedHouseIndex = origIdx
                                    data.lastSelectedHouse = house.house_number
                                    sampSendDialogResponse(data.dFlashminerId, 1, origHouse.index - 1, "")
                                    data.showHouseControlWindow[0] = false
                                    break
                                end
                            end
                        end

                        if imgui.IsItemHovered() then
                            for origIdx, origHouse in ipairs(data.dialogData.flashminer) do
                                if origHouse.house_number == house.house_number then
                                    data.selectedHouseIndex = origIdx
                                    data.lastSelectedHouse = house.house_number
                                    break
                                end
                            end
                        end
                    else
                        imgui.InvisibleButton("btn_placeholder_" .. i, imgui.ImVec2(cardW, cardH))
                    end

                    if isSelected or isHovered then
                        local cardPos = imgui.GetItemRectMin()
                        local dl = imgui.GetWindowDrawList()
                        dl:AddRectFilled(
                            cardPos,
                            imgui.ImVec2(cardPos.x + cardW, cardPos.y + cardH),
                            imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.2, 0.6, 1.0, 0.15)),
                            6.0
                        )
                    end

                    if imgui.IsItemHovered() then
                        if imgui.IsMouseClicked(1) then
                            imgui.OpenPopup("house_context_menu_" .. house.house_number)
                        end
                    end

                    if imgui.BeginPopup("house_context_menu_" .. house.house_number) then
                        imgui.TextColoredRGB(string.format("{FFA500}Дом №%d {808080}— %s",
                            house.house_number, house.city or "Неизвестно"))
                        imgui.Separator()

                        local excluded = houseFilter.isExcluded(house.house_number)
                        local houseStr = tostring(house.house_number)

                        if imgui.MenuItemBool(u8(excluded and "Снять метку 'Пропускать'" or "Пропускать дом"), nil, excluded) then
                            cfg.excludedHouses[houseStr] = not excluded and true or nil
                            save()
                        end

                        if imgui.MenuItemBool(u8 "Найти дом (/findihouse)") then
                            sampSendChat(string.format("/findihouse %d", house.house_number))
                        end

                        if not data.working then
                            imgui.Separator()
                            if imgui.MenuItemBool(u8 "Обновить статус этого дома") then
                                lua_thread.create(function()
                                    taskState.setWorking(true); data.taskTypeNow = 'updateStatuses'
                                    local sr = function(...) sampSendDialogResponse(...) end
                                    data.dialogData.videocards = {}
                                    dialogActions.selectHouse(sr, house.index - 1)
                                    wait(400)
                                    dialogActions.closeDialog(sr)
                                    wait(200)
                                    taskState.setWorking(false); data.taskTypeNow = nil
                                    imgui.addNotification(u8(string.format("Дом №%d обновлён", house.house_number)))
                                end)
                            end
                            if not houseFilter.isExcluded(house.house_number) and not houseFilter.hasNoBasement(house.house_number) then
                                if imgui.MenuItemBool(u8 "Зайти в дом") then
                                    sampSendDialogResponse(data.dFlashminerId, 1, house.index - 1, "")
                                    data.showHouseControlWindow[0] = false
                                end
                            end
                        end
                        imgui.EndPopup()
                    end

                    imgui.EndChild()
                    imgui.PopStyleColor()
                end
                imgui.EndChild()
            end

            imgui.End()
        end

        imgui.End()
    end
end)

function __i__progressPanel()
    imgui.BeginChild("##progress_panel", imgui.ImVec2(0, 0), true)

    local availWidth = imgui.GetContentRegionAvail().x
    local availHeight = imgui.GetContentRegionAvail().y
    local centerX = availWidth / 2
    local centerY = availHeight / 2

    local targetOuter = data.progressTotal > 0 and (data.progressCurrent / data.progressTotal) or 0
    targetOuter = math.min(math.max(targetOuter, 0), 1)
    local targetInner = data.progressHouseTotal > 0 and (data.progressHouseCurrent / data.progressHouseTotal) or 0
    targetInner = math.min(math.max(targetInner, 0), 1)

    local currentTime = os.clock()
    local deltaTime = math.min(currentTime - (data.progressSmooth.lastUpdateTime or currentTime), 0.1)
    data.progressSmooth.lastUpdateTime = currentTime

    local newOuter, newOuterVel = smoothDamp(data.progressSmooth.outer, targetOuter, data.progressSmooth.outerVelocity,
        deltaTime, 0.15)
    local newInner, newInnerVel = smoothDamp(data.progressSmooth.inner, targetInner, data.progressSmooth.innerVelocity,
        deltaTime, 0.12)
    data.progressSmooth.outer = newOuter
    data.progressSmooth.outerVelocity = newOuterVel
    data.progressSmooth.inner = newInner
    data.progressSmooth.innerVelocity = newInnerVel

    local drawList = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    local absCenter = imgui.ImVec2(p.x + centerX, p.y + centerY - 60)

    DrawDoubleProgressCircle(absCenter, 55, 40, 10, data.progressSmooth.outer, data.progressSmooth.inner)

    local percentText = string.format("%.0f%%", data.progressSmooth.outer * 100)
    local percentSize = imgui.CalcTextSize(percentText)
    drawList:AddText(
        imgui.ImVec2(absCenter.x - percentSize.x / 2, absCenter.y - percentSize.y / 2),
        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.95, 0.96, 0.98, 1.0)), percentText)

    local descriptions = {
        scanBasements = "Сканирование подвалов...",
        updateStatuses = "Обновление данных...",
        collectFromAllHouses = "Массовый сбор...",
        fixAllProblems = "Авто-обслуживание...",
        massSwitchCards = "Переключение карт...",
        coolant = "Заливка жидкостей..."
    }
    local taskText = u8(descriptions[data.taskTypeNow] or "Выполнение...")
    local taskTextSize = imgui.CalcTextSize(taskText)
    local taskTextY = absCenter.y + 55 + 15
    drawList:AddText(imgui.ImVec2(p.x + centerX - taskTextSize.x / 2, taskTextY),
        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.7, 0.7, 0.7, 1.0)), taskText)

    local counterText = u8(string.format("Дом: %d / %d", data.progressCurrent,
        data.progressTotal > 0 and data.progressTotal or 0))
    local counterSize = imgui.CalcTextSize(counterText)
    local counterY = taskTextY + taskTextSize.y + 8
    drawList:AddText(imgui.ImVec2(p.x + centerX - counterSize.x / 2, counterY),
        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.5, 0.5, 0.5, 1.0)), counterText)

    if data.progressHouseTotal > 0 then
        local houseText = u8(string.format("Карта: %d / %d", data.progressHouseCurrent, data.progressHouseTotal))
        local houseSize = imgui.CalcTextSize(houseText)
        local houseY = counterY + counterSize.y + 6
        drawList:AddText(imgui.ImVec2(p.x + centerX - houseSize.x / 2, houseY),
            imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.3, 0.8, 0.3, 1.0)), houseText)
    end

    local btnOffsetY = data.isWaitingPayday and (centerY + 85) or (centerY + 60)
    imgui.SetCursorPos(imgui.ImVec2(centerX - 100, btnOffsetY))

    if data.isWaitingPayday then
        local lastCounterY = counterY + counterSize.y + 6
        if data.progressHouseTotal > 0 then
            local houseLineH = imgui.GetTextLineHeight()
            lastCounterY = lastCounterY + houseLineH + 6
        end

        if data.isWaitingPayday then
            local pdText = u8 "Ожидание PayDay..."
            local pdSize = imgui.CalcTextSize(pdText)
            drawList:AddText(
                imgui.ImVec2(p.x + centerX - pdSize.x / 2, lastCounterY + 6),
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 0.88, 0.2, 1.0)),
                pdText
            )
        end
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.8, 0.2, 0.2, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1.0, 0.3, 0.3, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.6, 0.1, 0.1, 1.0))
        if imgui.Button(fa.STOP .. u8 " Остановить", imgui.ImVec2(95, 40)) then
            data.stopAction = true
            data.skipPayday = true
        end
        imgui.PopStyleColor(3)

        imgui.SameLine(0, 8)

        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.7, 0.55, 0.1, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.9, 0.7, 0.15, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.5, 0.4, 0.08, 1.0))
        if imgui.Button(fa.FORWARD_STEP .. u8 " Пропустить", imgui.ImVec2(95, 40)) then
            data.skipPayday = true
            data.paydaySkippedAt = os.time()
        end
        imgui.PopStyleColor(3)
    else
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.8, 0.2, 0.2, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1.0, 0.3, 0.3, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.6, 0.1, 0.1, 1.0))
        if imgui.Button(fa.STOP .. u8 " Остановить", imgui.ImVec2(200, 40)) then
            data.stopAction = true
        end
        imgui.PopStyleColor(3)
    end

    imgui.EndChild()
end

function imgui.customTitleBar(param, resetFunc, windowWidth)
    local imStyle = imgui.GetStyle()

    imgui.SetCursorPosY(imStyle.ItemSpacing.y + 5)
    if imgui.Link("t.me/justfedotScript", u8("Telegram канал автора.\nНажми чтобы перейти/скопировать")) then
        imgui.addNotification(u8 "Ссылка скопирована!")
        imgui.SetClipboardText("https://t.me/justfedotScript")
        --os.execute(('explorer.exe "%s"'):format("https://t.me/justfedotScript"))
    end

    imgui.SameLine()
    local titleX = (windowWidth - 170 - imStyle.ItemSpacing.x + imgui.CalcTextSize("t.me/justfedotScript").x) / 2 -
        imgui.CalcTextSize(script.this.name).x / 2
    if data.isViceCity then
        titleX = titleX - 20
    end
    imgui.SetCursorPosX(titleX)
    imgui.TextColoredRGB(script.this.name)
    if data.isViceCity then
        imgui.SameLine(0, 6)
        imgui.SetCursorPosY(imStyle.ItemSpacing.y + 5)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.4, 0.8, 1.0, 1.0))
        imgui.Text("VC")
        imgui.PopStyleColor()
        imgui.Hint("Вы находитесь в Vice City.\nОбычная охлаждающая жидкость работает как супер (100%).")
    end

    imgui.SameLine()

    imgui.SetCursorPosX(windowWidth - 170 - imStyle.ItemSpacing.x)
    imgui.SetCursorPosY(imStyle.ItemSpacing.y)
    if imgui.Button(fa('MONUMENT') .. "##popup_donation_button", imgui.ImVec2(50, 25)) then
        imgui.OpenPopup("donationPopupMenu")
    end

    imgui.SameLine()

    imgui.SetCursorPosX(windowWidth - 110 - imStyle.ItemSpacing.x)
    imgui.SetCursorPosY(imStyle.ItemSpacing.y)
    if imgui.Button(fa("BARS") .. "##settings_button", imgui.ImVec2(50, 25)) then
        data.showSettingsWindow[0] = not data.showSettingsWindow[0]
    end

    imgui.SameLine()

    imgui.SetCursorPosX(windowWidth - 50 - imStyle.ItemSpacing.x)
    imgui.SetCursorPosY(imStyle.ItemSpacing.y)
    if imgui.ButtonClickable("Подождите...", not data.working, fa("XMARK") .. "##close_button", imgui.ImVec2(50, 25)) then
        if data.showHouseControlWindow[0] then
            fixI()
            param[0] = false
            data.showSettingsWindow[0] = false
        end
    end

    if imgui.BeginPopup("donationPopupMenu") then
        imgui.Text(u8("Оригинальный автор: Just Fedot"), 0xFF00AAFF, 0xFF00FFCC)
        if imgui.Link("https://www.blast.hk/threads/213948/", u8 "Ссылка на исходный скрипт") then
            os.execute(('explorer.exe "%s"'):format("https://www.blast.hk/threads/213948/"))
        end

        imgui.Text(u8("Почтить память автора:"), 0xFFFF5555, 0xFFFFAAAA)
        if imgui.Link("https://www.blast.hk/threads/235846/", u8 "Нажмите чтобы перейти") then
            os.execute(('explorer.exe "%s"'):format("https://www.blast.hk/threads/235846/"))
        end
        imgui.EndPopup()
    end
end

local notifications = {}

function imgui.addNotification(text)
    table.insert(notifications, {
        text = text,
        startTime = os.clock()
    })
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
    _ids = {},
}

setmetatable(imgui.Scroller, {
    __call = function(self, id, step, duration, HoveredFlags)
        if not HoveredFlags then
            HoveredFlags = imgui.HoveredFlags.RectOnly
        end

        if not imgui.Scroller._ids[id] then
            imgui.Scroller._ids[id] = {}
        end

        local current_position = imgui.GetScrollY()

        if (imgui.IsWindowHovered(HoveredFlags) and imgui.IsMouseDown(0)) then
            imgui.Scroller._ids[id].start_clock = nil
        end

        if imgui.Scroller._ids[id].start_clock then
            local elapsed = (os.clock() - imgui.Scroller._ids[id].start_clock) * 1000

            if elapsed <= duration then
                local progress = elapsed / duration
                local fading_progress = progress * (2 - progress)
                local distance = imgui.Scroller._ids[id].target_position - imgui.Scroller._ids[id].start_position
                local new_position = imgui.Scroller._ids[id].start_position + distance * fading_progress

                if new_position < 0 then
                    new_position = 0
                    imgui.Scroller._ids[id].start_clock = nil
                elseif new_position > imgui.GetScrollMaxY() then
                    new_position = imgui.GetScrollMaxY()
                    imgui.Scroller._ids[id].start_clock = nil
                end

                imgui.SetScrollY(math.floor(new_position))
            else
                imgui.Scroller._ids[id].start_clock = nil
                imgui.SetScrollY(imgui.Scroller._ids[id].target_position)
            end
        end

        local wheel_delta = imgui.GetIO().MouseWheel

        if wheel_delta ~= 0 and imgui.IsWindowHovered(HoveredFlags) then
            local offset = -wheel_delta * step

            if not imgui.Scroller._ids[id].start_clock then
                imgui.Scroller._ids[id].start_clock = os.clock()
                imgui.Scroller._ids[id].start_position = current_position
                imgui.Scroller._ids[id].target_position = current_position + offset
            else
                imgui.Scroller._ids[id].start_clock = os.clock()
                imgui.Scroller._ids[id].start_position = current_position

                if imgui.Scroller._ids[id].start_position < imgui.Scroller._ids[id].target_position and offset > 0 then
                    imgui.Scroller._ids[id].target_position = imgui.Scroller._ids[id].target_position + offset
                elseif imgui.Scroller._ids[id].start_position > imgui.Scroller._ids[id].target_position and offset < 0 then
                    imgui.Scroller._ids[id].target_position = imgui.Scroller._ids[id].target_position + offset
                else
                    imgui.Scroller._ids[id].target_position = current_position + offset
                end
            end
        end
    end
})

function imgui.ScrollToPosition(id, targetPosition, duration)
    if not imgui.Scroller._ids[id] then
        imgui.Scroller._ids[id] = {}
    end

    local current_position = imgui.GetScrollY()
    imgui.Scroller._ids[id].start_clock = os.clock()
    imgui.Scroller._ids[id].start_position = current_position
    imgui.Scroller._ids[id].target_position = targetPosition
end

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
        local function startsWithFA(str)
            if not str or #str < 3 then return false end
            local b1, b2 = string.byte(str, 1), string.byte(str, 2)
            return b1 == 0xEF and b2 >= 0x80 and b2 <= 0xA3
        end

        for w in text_:gmatch('[^\r\n]+') do
            w = w:gsub('{(......)}', '{%1FF}')

            local lineIcon = nil
            local lineText = w

            if startsWithFA(w) then
                lineIcon = w:sub(1, 3)
                lineText = w:sub(4)
            end

            if lineIcon then
                imgui.Text(lineIcon)
                imgui.SameLine(0, 5)
            end

            local text, colors_, m = {}, {}, 1
            lineText = lineText:gsub('{(......)}', '{%1FF}')
            while lineText:find('{........}') do
                local n, k = lineText:find('{........}')
                local color = getcolor(lineText:sub(n + 1, k - 1))
                if color then
                    text[#text], text[#text + 1] = lineText:sub(m, n - 1), lineText:sub(k + 1, #lineText)
                    colors_[#colors_ + 1] = color
                    m = n
                end
                lineText = lineText:sub(1, n - 1) .. lineText:sub(k + 1, #lineText)
            end

            if text[0] then
                for i = 0, #text do
                    imgui.TextColored(colors_[i] or colors[1], u8(text[i]))
                    imgui.SameLine(nil, 0)
                end
                imgui.NewLine()
            else
                imgui.Text(u8(lineText))
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

function imgui.Hint(text, icon, active)
    if type(icon) == "boolean" then
        active = icon
        icon = nil
    end

    if not active then
        active = not imgui.IsItemActive()
    end

    if imgui.IsItemHovered() and active then
        imgui.BeginTooltip()

        if icon and icon ~= "" then
            imgui.Text(icon)
            imgui.SameLine(0, 5)
        end

        imgui.TextColoredRGB(text)

        imgui.EndTooltip()
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

function DrawDoubleProgressCircle(centerPos, outerRadius, innerRadius, thickness, outerProgress, innerProgress)
    local drawList = imgui.GetWindowDrawList()
    local num_segments = 100

    -- Цвета
    local colorBg = imgui.ImVec4(0.15, 0.16, 0.20, 1.0)
    local colorOuter = imgui.ImVec4(0.2, 0.6, 1.0, 1.0)
    local colorInner = imgui.ImVec4(0.3, 0.8, 0.3, 1.0)

    -- Внешний круг
    drawList:AddCircle(centerPos, outerRadius,
        imgui.ColorConvertFloat4ToU32(colorBg), num_segments, thickness)

    if outerProgress > 0.001 then
        local start_angle = -math.pi / 2
        local end_angle = start_angle + (2 * math.pi * outerProgress)

        drawList:PathClear()
        drawList:PathArcTo(centerPos, outerRadius, start_angle, end_angle, num_segments)
        drawList:PathStroke(imgui.ColorConvertFloat4ToU32(colorOuter), false, thickness)
    end

    -- Внутренний круг
    if innerRadius > 0 then
        drawList:AddCircle(centerPos, innerRadius,
            imgui.ColorConvertFloat4ToU32(colorBg), num_segments, thickness - 2)

        if innerProgress > 0.001 then
            local start_angle = -math.pi / 2
            local end_angle = start_angle + (2 * math.pi * innerProgress)

            drawList:PathClear()
            drawList:PathArcTo(centerPos, innerRadius, start_angle, end_angle, num_segments)
            drawList:PathStroke(imgui.ColorConvertFloat4ToU32(colorInner), false, thickness - 2)
        end
    end
end

function smoothDamp(current, target, velocity, deltaTime, smoothTime)
    smoothTime = math.max(0.0001, smoothTime)

    local omega = 2 / smoothTime
    local x = omega * deltaTime
    local exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)

    local change = current - target
    local temp = (velocity + omega * change) * deltaTime

    velocity = (velocity - omega * temp) * exp
    local newValue = target + (change + temp) * exp

    if (target - current > 0) == (newValue > target) then
        newValue = target
        velocity = 0
    end

    return newValue, velocity
end

function ButtonWithHint(label, hint, clickable, size)
    if clickable == nil then clickable = not data.working end

    local pressed = imgui.ButtonClickable(hint, clickable, label, size or imgui.ImVec2(-1, 0))

    if clickable and hint and imgui.IsItemHovered() then
        imgui.SetTooltip(u8(hint))
    end

    return pressed
end

function renderResetConfirm(idSuffix, timerStartedAt, title, subtitle, onConfirm, onCancel)
    local sw2, sh2 = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(sw2 / 2, sh2 / 2),
        imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(380, 150), imgui.Cond.Always)
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.08, 0.08, 0.10, 0.98))
    if imgui.Begin("##" .. idSuffix, nil,
            imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar +
            imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove) then
        imgui.SetCursorPosY(20)
        imgui.TextColored(imgui.ImVec4(0.97, 0.51, 0.51, 1), fa.TRIANGLE_EXCLAMATION)
        imgui.SameLine(0, 8)
        imgui.TextColoredRGB("{FFFFFF}" .. title)
        imgui.Spacing()
        imgui.TextColoredRGB("{808080}" .. subtitle)
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        local elapsed    = os.clock() - (timerStartedAt or 0)
        local remaining  = math.ceil(5 - elapsed)
        local canConfirm = elapsed >= 5.0
        local halfW      = (imgui.GetContentRegionAvail().x - imgui.GetStyle().ItemSpacing.x) / 2

        if canConfirm then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.6, 0.1, 0.1, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.8, 0.15, 0.15, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.4, 0.07, 0.07, 1))
            if imgui.Button(u8 "Сбросить", imgui.ImVec2(halfW, 28)) then onConfirm() end
            imgui.PopStyleColor(3)
        else
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.2, 0.1, 0.1, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.2, 0.1, 0.1, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.2, 0.1, 0.1, 1))
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.5, 0.5, 0.5, 1))
            imgui.Button(u8(string.format("Сбросить (%dс)", remaining)), imgui.ImVec2(halfW, 28))
            imgui.PopStyleColor(4)
        end
        imgui.SameLine()
        if imgui.Button(u8 "Отмена", imgui.ImVec2(halfW, 28)) then onCancel() end

        imgui.End()
    end
    imgui.PopStyleColor()
end

function isInImproveHintRange()
    if data.showImproveWindow[0] then return false end
    local px, py, pz = getCharCoordinates(PLAYER_PED)
    local dx         = px - IMPROVE_SPOT.x
    local dy         = py - IMPROVE_SPOT.y
    local dz         = pz - IMPROVE_SPOT.z
    return (dx * dx + dy * dy + dz * dz) <= (IMPROVE_HINT_RADIUS * IMPROVE_HINT_RADIUS)
end
