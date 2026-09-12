--==============================================================================
-- MACRO AI  v2  -  ghi lai DUNG CACH CHONG DI + chay lai cho moi do kho
--
-- Cach dung: dat file nay vao workspace cua executor roi chay
--     loadstring(readfile("macro_ai.lua"))()
--
--------------------------------------------------------------------------------
-- MOI CO CHE DUOI DAY DEU CO NGUON THAT (xem KE_HOACH_MACRO_CHUAN.md)
--------------------------------------------------------------------------------
-- * remotes nam o  ReplicatedStorage.remotes
-- * START   -> remotes.changeStartValue      (ui/startButton/LocalScript.lua:22)
-- * READY   -> remotes.readyUp               (ui/readyButton/LocalScript.lua:12)
-- * choi lai-> remotes.replayDungeon(duLieuAi)
--                         (ReplayDungeonButton/Replay/LocalScript.lua:16,51,184)
-- * danh tay-> Accessory co con "Weapon" -> RemoteEvent trong Accessory
--              :FireServer() roi remotes.weaponUsed:FireServer().
--              GATE THAT: LocalPlayer.peaceful.Value == false VA
--              Character.busyCasting PHAI TON TAI va == false
--                         (PlayerGui/UIS.lua:90-113, Ui/MobileLayout.lua:271-311)
-- * skill q/e-> tool co con "abilitySlot" = "q"/"e" trong Backpack,
--              cooldown phai <= 0; tool.localEvent:Fire() roi
--              remotes.abilityUsed:FireServer(slot, tool)
--                         (UIS.lua:40-85, MobileLayout.lua:295-363)
-- * SWAP    -> remotes.swapAbilitySet:FireServer() KHONG tham so, game debounce
--              0.5s. Swap KHONG doi tool, no doi abilitySlot.Value cua tool
--                         (Ui/abilities.lua:22-31,73-108,271; inventory.lua:1395)
-- * xong ai -> workspace.dungeon.bossRoom.dungeonFinished == true
-- * van DA BAT DAU -> workspace.dungeonProgress.Value == "inProgress"
--              (readyButton tu huy luc do, readyButton/LocalScript.lua:6-9)
--              hoac dungeonStarted / start == true (PlaceManager.lua:705-730)
-- * DO KHO  -> PlaceManager.GetPlaceTeleportData().dungeonStats.difficulty
--              (Utility/PlaceManager.lua:67-101,681-704)
--
-- CACH DIEU KHIEN NHAN VAT khi chay lai macro: dung DUNG duong ma game dung.
-- ControlModule that cua game moi render step lam hai viec:
--     moveFunction(LocalPlayer, MoveVector, cameraRelative)   -- = LocalPlayer:Move
--     humanoid.Jump = dangNhay
--   (PlayerScripts/PlayerModule/ControlModule.lua:56, 238-252)
-- No bind o ten "ControlScriptRenderstep" uu tien Enum.RenderPriority.Input.Value
--   (ControlModule.lua:77)
-- => Macro bind render step o uu tien Input+10 (chay SAU game) nen lenh Move cua
--    macro la lenh cuoi truoc buoc vat ly -> thang, khong can hook, khong can tat
--    tay dieu khien cua nguoi choi.
--
-- KHAC BAN CU: KHONG con dung Humanoid:MoveTo. MoveTo di bang bo tim duong noi bo
-- cua Humanoid nen no CAT GOC, khong leo dung cho, khong nhay dung diem. Nay macro
-- ghi lai chinh HUONG BAM (Humanoid.MoveDirection) + trang thai nhan vat, roi phat
-- lai bang Humanoid:Move -> di y nhu luc chong cam may.
--==============================================================================

local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local UIS         = game:GetService("UserInputService")
local RunService  = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LP          = Players.LocalPlayer

-- Xuong dong trong chuoi Lua viet bang string.char(10).
-- Ly do: cong cu sinh file tung ghi nham ky tu escape thanh newline THAT, lam
-- chuoi Lua tran sang dong sau -> loi cu phap -> loadstring tra nil.
local XUONG_DONG = string.char(10)

-- dung ban cu neu chay lai script
if _G.__MACRO_AI__ then
    pcall(function() _G.__MACRO_AI__.tat() end)
end

--== THAM SO ===================================================================
-- Nhung so nay la THAM SO TU CHON, khong phai hang so lay tu source game.
local CFG = {
    NHIP_GHI      = 0.05,  -- giay moi mau duong di (20 mau/giay)
    CHO_SAU_START = 10,    -- giay: start ai xong cho bao lau moi chay macro
    NGUONG_TOI    = 3,     -- studs: gan the coi nhu da toi khung do
    NGUONG_CAO    = 10,    -- studs: chenh cao con chap nhan la "da toi"
    NHIN_TRUOC    = 4,     -- studs: ngam truoc bay nhieu de di muot, khong giat
    NGUONG_BAM    = 8,     -- studs: lech hon the thi keo ve duong, bo huong ghi
    NGUONG_LAC    = 55,    -- studs: lac hon the thi do lai khung gan nhat
    HET_GIO_KHUNG = 12,    -- giay: mot khung khong tai nao toi duoc thi bo
    HET_GIO_NUT   = 6,     -- giay: mot nut khong tai nao ban duoc thi bo
    KET_GIAY      = 2,     -- giay: dung im qua lau thi nhay thu (bi quai chan)
    NHIP_DANH     = 0.1,   -- giay giua hai nhat danh (dung nhip game: Swing 0.1s)
    DANH_TRE      = 60,    -- khung: nhat danh tre hon the thi bo, khong don cuc
    XOAY_KHI_DANH = true,  -- xoay mat dung huong luc ghi truoc khi danh/skill
    DONG_BO_TOC_DO = false,-- dat WalkSpeed bang luc ghi (mac dinh KHONG sua)
}

local M = { dangGhi = false, dangChay = false, autoStart = true, autoReplay = true,
            autoPlay = false, autoChonAi = true }
_G.__MACRO_AI__ = M

local P = {}    -- trang thai cua lan chay lai dang dien ra
local TEP_DANHSACH = "macro_ai_danhsach.json"
local TEP_CU       = "macro_ai_luu.json"   -- ban dau chi co mot macro duy nhat
local macro        = { ver = 2, khung = {}, sukien = {} }
local danhSach     = {}    -- { {ten=,ai=,doKho=,hardcore=,khung=}, ... }
local tenDangChon  = nil

--== tien ich ==================================================================
local function char() return LP.Character end

local function hrp()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart") or nil
end

local function hum()
    local c = char()
    return c and c:FindFirstChildOfClass("Humanoid") or nil
end

local function remote(ten)
    local f = RS:FindFirstChild("remotes")
    local r = f and f:FindFirstChild(ten)
    return (r and r:IsA("RemoteEvent")) and r or nil
end

local function ban(ten, ...)
    local r = remote(ten)
    if not r then return false end
    return (pcall(function(...) r:FireServer(...) end, ...))
end

local function lam(v, n)
    if type(v) ~= "number" then return 0 end
    local m = 10 ^ (n or 2)
    return math.floor(v * m + 0.5) / m
end

local function phang(v) return Vector3.new(v.X, 0, v.Z) end

local function donVi(v)
    if v.Magnitude < 0.001 then return Vector3.new(0, 0, 0) end
    return v.Unit
end

-- TEN AI + DO KHO. Nguon: PlaceManager.GetPlaceTeleportData().dungeonStats
-- (PlaceManager.lua:67-101, 681-704; cac truong thay o TestTeleportData.lua:87-93).
-- Nho ket qua 2 giay: GUI goi ham nay lien tuc, khong can require lai moi lan.
local nhoAi, nhoAiLuc = nil, -99

local function thongTinAi()
    if nhoAi and os.clock() - nhoAiLuc < 2 then return nhoAi end
    local ra = {}
    local ut = RS:FindFirstChild("Utility")
    local pm = ut and ut:FindFirstChild("PlaceManager")
    if pm and pm:IsA("ModuleScript") then
        local ok, mod = pcall(require, pm)
        if ok and type(mod) == "table" and type(mod.GetPlaceTeleportData) == "function" then
            local ok2, td = pcall(mod.GetPlaceTeleportData)
            if ok2 and type(td) == "table" and type(td.dungeonStats) == "table" then
                ra.ai       = td.dungeonStats.dungeonName
                ra.doKho    = td.dungeonStats.difficulty
                ra.hardcore = td.dungeonStats.hardcore
            end
        end
    end
    -- Du phong: gia tri trong workspace (Replay/LocalScript.lua:51-98 doc y the)
    if not ra.ai then
        local dn = workspace:FindFirstChild("dungeonName")
        if dn and dn:IsA("StringValue") then ra.ai = dn.Value end
    end
    if ra.hardcore == nil then
        local hc = workspace:FindFirstChild("hardcore")
        if hc and hc:IsA("BoolValue") then ra.hardcore = hc.Value end
    end
    nhoAi, nhoAiLuc = ra, os.clock()
    return ra
end

local function nhanAi(t)
    if not t then return "?" end
    local s = tostring(t.ai or "?")
    if t.doKho then s = s .. " " .. tostring(t.doKho) end
    if t.hardcore == true then s = s .. " HC" end
    return s
end

--== danh tay ==================================================================
-- Vu khi game nay la ACCESSORY (khong phai Tool): Accessory co con "Weapon" va
-- mot RemoteEvent ben trong (UIS.lua:100-112, MobileLayout.lua:255-283).
local function remoteVuKhi()
    local c = char()
    if not c then return nil end
    for _, ch in ipairs(c:GetChildren()) do
        if ch:IsA("Accessory") and ch:FindFirstChild("Weapon") then
            local re = ch:FindFirstChildOfClass("RemoteEvent")
            if re then return re end
        end
    end
    return nil
end

-- Ban dung ba cai chot cua game. Thieu mot cai la game that cung khong danh:
--   peaceful.Value == false        (khong danh trong lang)
--   busyCasting PHAI TON TAI       (source: `if not busyCasting then return end`)
--   busyCasting.Value == false     (dang cast thi khong danh)
local function chemTay()
    local pf = LP:FindFirstChild("peaceful")
    if pf and pf:IsA("BoolValue") and pf.Value ~= false then return false end
    local c = char()
    if not c then return false end
    local bc = c:FindFirstChild("busyCasting")
    if not bc or bc.Value ~= false then return false end
    local re = remoteVuKhi()
    if not re then return false end
    if not pcall(function() re:FireServer() end) then return false end
    ban("weaponUsed")
    return true
end

--== skill q / e / swap ========================================================
local function toolSkill(slot)
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            local s = t:FindFirstChild("abilitySlot")
            if s and s.Value == slot then return t end
        end
    end
    local c = char()
    if c then
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") then
                local s = t:FindFirstChild("abilitySlot")
                if s and s.Value == slot then return t end
            end
        end
    end
    return nil
end

-- Ten tool dang giu slot nay (vd "Water Orb"). Dung de biet dang o bo nao.
local function tenToolO(slot)
    local t = toolSkill(slot)
    return t and t.Name or nil
end

-- BAN SKILL. LocalScript that cua tung chieu
-- (ReplicatedStorage/abilities/<ten>/LocalScript.lua:8-28):
--     localEvent.Event -> neu cooldown <= 0 va busyCasting.Value == false thi
--     busyCasting = true; spellEvent:FireServer(); play anim. Neu khong thi
--     Humanoid:UnequipTools() roi THOAT IM LANG (khong ban gi, khong bao loi).
-- Nen:
--   * cooldown > 0            -> tra false, de vong sau thu lai (khong mat nut)
--   * busyCasting == true     -> tra false, cho cast xong
--   * busyCasting KHONG TON TAI -> LocalScript chan vinh vien, luc do moi ban
--     THANG spellEvent (dung y dump cua chong: Backpack["Agony Orbs"].spellEvent)
-- Khong bao gio goi ca localEvent lan spellEvent, keo ban hai lan.
local function banSkill(slot)
    local tool = toolSkill(slot)
    if not tool then return false end
    local cd = tool:FindFirstChild("cooldown")
    if not cd or not cd:IsA("ValueBase") or (tonumber(cd.Value) or 1) > 0 then
        return false
    end

    local c = char()
    local bc = c and c:FindFirstChild("busyCasting")
    local ev    = tool:FindFirstChild("localEvent")
    local spell = tool:FindFirstChild("spellEvent")

    if bc ~= nil then
        if bc.Value ~= false then return false end     -- dang cast, cho
        if not (ev and ev:IsA("BindableEvent")) then return false end
        if not pcall(function() ev:Fire() end) then return false end
    elseif spell and spell:IsA("RemoteEvent") then
        if not pcall(function() spell:FireServer() end) then return false end
    else
        return false
    end

    ban("abilityUsed", slot, tool)
    return true
end

local lanSwap = 0

local function banSwap()
    local r = remote("swapAbilitySet")
    if not r then return false end
    if os.clock() - lanSwap < 0.55 then return false end   -- debounce 0.5s cua game
    if not pcall(function() r:FireServer() end) then return false end
    lanSwap = os.clock()
    return true
end

--== auto start / auto replay ==================================================
local lanReady, lanStart, lanReplay = 0, 0, 0
local daChayVanNay = false   -- da tu chay macro cho van hien tai chua

local function thuBamStart()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return end
    local now = os.clock()

    local ready = LP:FindFirstChild("ready")
    if pg:FindFirstChild("readyButton") and (ready == nil or ready.Value ~= true) then
        if now - lanReady > 2 then
            lanReady = now
            ban("readyUp")
        end
    end

    if pg:FindFirstChild("startButton") then
        local st = workspace:FindFirstChild("start")
        if (not st or st.Value ~= true) and now - lanStart > 2 then
            lanStart = now
            ban("changeStartValue")
        end
    end
end

local function daXongAi()
    local d = workspace:FindFirstChild("dungeon")
    local br = d and d:FindFirstChild("bossRoom")
    local v = br and br:FindFirstChild("dungeonFinished")
    return v ~= nil and v:IsA("BoolValue") and v.Value == true
end

-- Chep dung collectDungeonData() cua nut Replay (Replay/LocalScript.lua:51-98)
local function duLieuAi()
    local d = {}
    local dn = workspace:FindFirstChild("dungeonName")
    if dn and dn:IsA("StringValue") then d.dungeonName = dn.Value end
    local dp = workspace:FindFirstChild("dungeonProgress")
    if dp and dp:IsA("StringValue") then d.dungeonProgress = dp.Value end
    local ds = workspace:FindFirstChild("dungeonStarted")
    if ds and ds:IsA("BoolValue") then d.dungeonStarted = ds.Value end
    local hc = workspace:FindFirstChild("hardcore")
    if hc and hc:IsA("BoolValue") then
        d.hardcore = hc.Value
        d.isHardcore = hc.Value
    end
    local dungeon = workspace:FindFirstChild("dungeon")
    if dungeon then
        for _, c in ipairs(dungeon:GetChildren()) do
            if c:IsA("ValueBase") then d[c.Name] = c.Value end
        end
        local br = dungeon:FindFirstChild("bossRoom")
        if br then
            for _, c in ipairs(br:GetChildren()) do
                if c:IsA("ValueBase") then d[c.Name] = c.Value end
            end
        end
    end
    return d
end

local function thuReplay()
    if not daXongAi() then return end
    local now = os.clock()
    if now - lanReplay < 8 then return end
    local d = duLieuAi()
    if not d.dungeonName then return end
    lanReplay = now
    ban("replayDungeon", d)
end

--== GHI MACRO =================================================================
local ketNoi      = {}     -- moi ket noi tao ra luc ghi, de ngat sach
local batDauLuc   = 0
local donDt       = 0
local daNhay      = false  -- co: khung nay vua nhay
local giuDanh     = false  -- dang giu nut Swing (mobile) -> game chem 0.1s/lan
local danhLuc     = 0
local daHook      = {}     -- tool da gan theo doi

local function them(c)
    if c then ketNoi[#ketNoi + 1] = c end
end

local function ngatHet()
    for _, c in ipairs(ketNoi) do pcall(function() c:Disconnect() end) end
    ketNoi = {}
    daHook = {}
end

local function ghiSuKien(loai, tenTool)
    if not M.dangGhi then return end
    local bayGio = os.clock() - batDauLuc
    -- chong ghi trung: nhieu lop cung bat mot hanh dong trong cung mot nhip
    local cuoi = macro.sukien[#macro.sukien]
    if cuoi and cuoi.loai == loai and bayGio - cuoi.t < 0.12 then return end
    -- Ghi kem TEN TOOL dang giu slot do. Nho no ma luc chay lai biet skill nay
    -- thuoc bo nao: slot dang giu tool ten khac thi phai Swap truoc.
    local ten = tenTool
    if not ten and (loai == "q" or loai == "e") then ten = tenToolO(loai) end
    local r = hrp()
    local lv = r and r.CFrame.LookVector or nil
    macro.sukien[#macro.sukien + 1] = {
        t = lam(bayGio, 3),
        k = #macro.khung,           -- neo theo KHUNG, khong chi theo gio
        loai = loai,
        ten = ten,
        lx = lv and lam(lv.X, 3) or nil,
        lz = lv and lam(lv.Z, 3) or nil,
    }
end

-- Ma trang thai Humanoid -> so, cho file nho va de so sanh.
local function maTrangThai(st)
    if st == Enum.HumanoidStateType.Running
        or st == Enum.HumanoidStateType.RunningNoPhysics then return 1 end
    if st == Enum.HumanoidStateType.Freefall then return 2 end
    if st == Enum.HumanoidStateType.Jumping then return 3 end
    if st == Enum.HumanoidStateType.Climbing then return 4 end
    if st == Enum.HumanoidStateType.Landed then return 5 end
    if st == Enum.HumanoidStateType.Swimming then return 6 end
    return 0
end

local function ghiMotKhung()
    local r, h = hrp(), hum()
    if not r or not h then return end
    local p  = r.Position
    local md = h.MoveDirection        -- huong DI THAT (RbxCharacterSounds.lua:516)
    macro.khung[#macro.khung + 1] = {
        t  = lam(os.clock() - batDauLuc, 3),
        x  = lam(p.X), y = lam(p.Y), z = lam(p.Z),
        dx = lam(md.X, 3), dz = lam(md.Z, 3),
        s  = maTrangThai(h:GetState()),
        w  = lam(h.WalkSpeed, 1),
        j  = daNhay and 1 or nil,
    }
    daNhay = false
end

-- Neo moi su kien vao mot khung. Macro cu (ver 1) khong co truong k -> suy ra tu
-- moc thoi gian.
local function ganKhungChoSuKien()
    local n = #macro.khung
    if n == 0 then return end
    for _, s in ipairs(macro.sukien) do
        if not s.k then
            local j = 1
            while j < n and (macro.khung[j].t or 0) < (s.t or 0) do j = j + 1 end
            s.k = j
        end
        if s.k < 1 then s.k = 1 end
        if s.k > n then s.k = n end
    end
end

-- Theo doi mot tool: cooldown nhay 0 -> >0 nghia la skill do VUA duoc dung, bat
-- ke bam bang phim, chuot, nut tren man hinh hay DualCast. abilitySlot.Value doi
-- nghia la vua SWAP bo (Ui/abilities.lua: swap doi slot, tool khong roi Backpack).
local function hookTool(t)
    if daHook[t] then return end
    local cd = t:FindFirstChild("cooldown")
    local sl = t:FindFirstChild("abilitySlot")
    if not (cd and cd:IsA("ValueBase")) or not (sl and sl:IsA("ValueBase")) then return end
    daHook[t] = true
    local truoc = tonumber(cd.Value) or 0
    them(cd:GetPropertyChangedSignal("Value"):Connect(function()
        local nay = tonumber(cd.Value) or 0
        if truoc <= 0.01 and nay > 0.01 then
            local slot = tostring(sl.Value)
            if slot == "q" or slot == "e" then ghiSuKien(slot, t.Name) end
        end
        truoc = nay
    end))
    them(sl:GetPropertyChangedSignal("Value"):Connect(function()
        ghiSuKien("swap")
    end))
end

local function quetTool()
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do hookTool(t) end
        them(bp.ChildAdded:Connect(function(t) hookTool(t) end))
    end
    local c = char()
    if c then
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") then hookTool(t) end
        end
    end
end

-- Nhay: bat bang Humanoid.StateChanged nen ghi duoc TREN CA DIEN THOAI (nut nhay
-- tren man hinh khong sinh KeyCode.Space nao).
local function ngheNhanVat(c)
    if not c then return end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h then
        local ok, v = pcall(function() return c:WaitForChild("Humanoid", 5) end)
        h = ok and v or nil
    end
    if not h then return end
    them(h.StateChanged:Connect(function(_, new)
        if new == Enum.HumanoidStateType.Jumping then daNhay = true end
    end))
end

-- Nghe nut GUI cua game. Chi DANG KY LANG NGHE THEM, khong chen vao luong lenh
-- cua game nen khong the lam hong viec bam skill.
-- Ten nut lay tu source: abilities.Swap (abilities.lua:73), slot_Q/slot_E co con
-- ImageButton (abilities.lua:275-300), mobile: Swing / DualCast / quickSwapButton
-- (MobileLayout.lua:570,648,852).
local function ngheNut(v)
    if not v:IsA("GuiButton") then return end
    local ten = string.lower(v.Name)
    local cha = v.Parent and string.lower(v.Parent.Name) or ""

    if ten == "swing" then
        -- Giu nut Swing: game goi swingOnce() moi 0.1s cho toi khi nha
        -- (MobileLayout.lua:615-628). Ghi lai dung nhip do.
        them(v.MouseButton1Down:Connect(function() giuDanh = true end))
        them(v.MouseButton1Up:Connect(function() giuDanh = false end))
        them(v.MouseLeave:Connect(function() giuDanh = false end))
    end

    them(v.Activated:Connect(function()
        if not M.dangGhi then return end
        if ten == "swap" or ten == "quickswapbutton" then
            ghiSuKien("swap")
        elseif ten == "dualcast" then
            ghiSuKien("q")
            ghiSuKien("e")
        elseif ten == "swing" then
            ghiSuKien("danh")
        elseif ten == "q" or cha:find("slot_q") then
            ghiSuKien("q")
        elseif ten == "e" or cha:find("slot_e") then
            ghiSuKien("e")
        end
    end))
end

function M.batGhi()
    if M.dangChay then return end
    local ai = thongTinAi()
    macro = { ver = 2, ai = ai.ai, doKho = ai.doKho, hardcore = ai.hardcore,
              nhip = CFG.NHIP_GHI, khung = {}, sukien = {} }
    batDauLuc = os.clock()
    donDt, daNhay, giuDanh, danhLuc = 0, false, false, 0
    M.dangGhi = true

    quetTool()
    ngheNhanVat(char())
    them(LP.CharacterAdded:Connect(function(c)
        ngheNhanVat(c)
        quetTool()
    end))

    local pg = LP:FindFirstChild("PlayerGui")
    if pg then
        for _, v in ipairs(pg:GetDescendants()) do pcall(ngheNut, v) end
        them(pg.DescendantAdded:Connect(function(v) pcall(ngheNut, v) end))
    end
    them(UIS.TouchEnded:Connect(function() giuDanh = false end))

    -- Ban phim / chuot: chi co tac dung tren PC. Giu lai cho may tinh.
    them(UIS.InputBegan:Connect(function(input, guiBatDuoc)
        if not M.dangGhi then return end
        if guiBatDuoc then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            ghiSuKien("danh")
        elseif input.KeyCode == Enum.KeyCode.Q then
            ghiSuKien("q")
        elseif input.KeyCode == Enum.KeyCode.E then
            ghiSuKien("e")
        elseif input.KeyCode == Enum.KeyCode.F then
            ghiSuKien("swap")   -- source: F chinh la doi bo skill
        end
    end))

    -- Lay mau duong di bang Heartbeat: nhip deu, khong tich luy sai so nhu
    -- task.wait, va may yeu (FPS thap) van ghi dung moc thoi gian thuc.
    them(RunService.Heartbeat:Connect(function(dt)
        if not M.dangGhi then return end
        donDt = donDt + dt
        if donDt < CFG.NHIP_GHI then return end
        donDt = donDt - CFG.NHIP_GHI
        if donDt > CFG.NHIP_GHI then donDt = 0 end
        ghiMotKhung()
        -- giu nut danh tren dien thoai: ghi 0.1s mot nhat, dung nhu game lam
        if giuDanh and os.clock() - danhLuc >= CFG.NHIP_DANH then
            danhLuc = os.clock()
            ghiSuKien("danh")
        end
    end))
end

function M.dungGhiLai()
    M.dangGhi = false
    giuDanh = false
    ngatHet()
    ganKhungChoSuKien()
end

--== CHAY MACRO ================================================================
local TEN_BIND = "MacroAI_Chay"

-- Tay dieu khien cua game, chi dung o duong lui (khi executor khong cho
-- BindToRenderStep). PlayerModule.lua:19-23 -> GetControls; ControlModule.lua
-- :171-180 -> Disable ghim move vector ve 0.
local function dieuKhien()
    local ps = LP:FindFirstChild("PlayerScripts")
    local pm = ps and ps:FindFirstChild("PlayerModule")
    if not pm or not pm:IsA("ModuleScript") then return nil end
    local ok, mod = pcall(require, pm)
    if not ok or type(mod) ~= "table" then return nil end
    local ok2, ctrl = pcall(function() return mod:GetControls() end)
    return ok2 and ctrl or nil
end

-- Huong nguoi that DA BAM o khung nay. Macro ver 2 co san (MoveDirection);
-- macro ver 1 thi suy ra tu hai khung lien nhau.
local function huongGhi(i)
    local a = macro.khung[i]
    if not a then return Vector3.new(0, 0, 0) end
    if a.dx or a.dz then
        return donVi(Vector3.new(a.dx or 0, 0, a.dz or 0))
    end
    local b = macro.khung[i + 1]
    if b then return donVi(Vector3.new(b.x - a.x, 0, b.z - a.z)) end
    local t = macro.khung[i - 1]
    if t then return donVi(Vector3.new(a.x - t.x, 0, a.z - t.z)) end
    return Vector3.new(0, 0, 0)
end

-- Khung nay chong DUNG YEN. Quan trong: khuc dung cho bay/nen sap phai dung DU
-- so giay da dung, khong duoc chay luon vao.
local function dungYen(i)
    local a = macro.khung[i]
    if not a then return false end
    if a.dx or a.dz then
        return (math.abs(a.dx or 0) + math.abs(a.dz or 0)) < 0.12
    end
    local b = macro.khung[i + 1]
    if not b then return false end
    local d  = (Vector3.new(b.x - a.x, 0, b.z - a.z)).Magnitude
    local dt = (b.t or 0) - (a.t or 0)
    return dt > 0 and (d / dt) < 1.5
end

-- Da toi khung i chua. Tinh theo VI TRI nen tocdo chay nhanh/cham deu di dung
-- duong, khong bi keo lech nhu kieu tua theo dong ho.
local function daToi(pos, i)
    local a = macro.khung[i]
    if not a then return true end
    local dxz = (Vector3.new(a.x - pos.X, 0, a.z - pos.Z)).Magnitude
    if dxz <= CFG.NGUONG_TOI then
        return math.abs(a.y - pos.Y) <= CFG.NGUONG_CAO
    end
    -- da di qua khung nay (gan khung sau hon) thi cung tinh la toi
    local b = macro.khung[i + 1]
    if b then
        local d2 = (Vector3.new(b.x - pos.X, 0, b.z - pos.Z)).Magnitude
        if d2 + 0.5 < dxz and d2 <= CFG.NGUONG_TOI * 2 then return true end
    end
    return false
end

-- Diem ngam cach nguoi khoang NHIN_TRUOC studs doc theo duong da ghi. Ngam truoc
-- nen khong giat (khong phai vua toi khung la doi huong gat 90 do).
local function diemNgam(pos, i)
    local a = macro.khung[i]
    local truoc = Vector3.new(a.x, a.y, a.z)
    local d = (Vector3.new(a.x - pos.X, 0, a.z - pos.Z)).Magnitude
    local j = i
    while d < CFG.NHIN_TRUOC and j < P.n do
        j = j + 1
        local kn = macro.khung[j]
        local p2 = Vector3.new(kn.x, kn.y, kn.z)
        d = d + (phang(p2) - phang(truoc)).Magnitude
        truoc = p2
    end
    return truoc
end

-- Khung gan cho dang dung nhat. `uuTienGan` cong them diem thuong cho khung gan
-- con tro hien tai, de duong di vong lai khong nhay lung tung.
local function timKhungGanNhat(pos, uuTienGan)
    local best, bestD, bestS = nil, math.huge, math.huge
    local moc = P.i or 1
    local i = 1
    while i <= #macro.khung do
        local a = macro.khung[i]
        local d = (Vector3.new(a.x, a.y, a.z) - pos).Magnitude
        local s = d
        if uuTienGan then s = d + math.abs(i - moc) * 0.02 end
        if s < bestS then bestS, bestD, best = s, d, i end
        i = i + 2                      -- buoc 2 cho nhanh, du chinh xac
    end
    return best or 1, bestD
end

-- Khung dau tien nam trong `tam` studs (uu tien khung SOM nhat de khong nhay
-- vot qua nua macro khi duong di co doan vong lai gan cho cu).
local function timKhungDau(pos, tam)
    for i = 1, #macro.khung do
        local a = macro.khung[i]
        if (Vector3.new(a.x, a.y, a.z) - pos).Magnitude <= tam then return i end
    end
    return 1
end

local function suKienTuKhung(j)
    local i = 1
    while i <= #macro.sukien and (macro.sukien[i].k or 1) < j do i = i + 1 end
    return i
end

local function banCoNhay(k, h)
    if k and k.j == 1 and h then h.Jump = true end
end

-- Xoay mat dung huong luc ghi truoc khi danh/ban skill. Dat CFrame se HUY van
-- toc nen luu lai roi tra ve ngay; va khong xoay khi dang o tren khong.
local function xoayMat(s, r, h)
    if not CFG.XOAY_KHI_DANH then return end
    if not (s.lx and s.lz) or not r or not h then return end
    local d = donVi(Vector3.new(s.lx, 0, s.lz))
    if d.Magnitude < 0.05 then return end
    local st = h:GetState()
    if st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.Jumping then
        return
    end
    local nay = donVi(phang(r.CFrame.LookVector))
    if nay.Magnitude < 0.05 then return end
    if nay:Dot(d) > 0.87 then return end            -- lech duoi ~30 do thi thoi
    pcall(function()
        local v = r.AssemblyLinearVelocity
        r.CFrame = CFrame.lookAt(r.Position, r.Position + d)
        r.AssemblyLinearVelocity = v
    end)
end

-- Ban cac nut thuoc khung dang bam. Tra ve true khi khong con gi phai cho.
-- Nut nao chua ban duoc (hoi chieu, dang cast, chua cam vu khi) thi GIU NGUYEN
-- CHO, vong sau thu lai - khong bo mat.
local function thuBanNut(h, r)
    while P.iSK <= #macro.sukien do
        local s = macro.sukien[P.iSK]
        local moc = s.k or 1
        if moc > P.i then return true end

        if s.loai == "danh" and (P.i - moc) > CFG.DANH_TRE then
            P.iSK = P.iSK + 1          -- nhat danh tre qua, bo (khong don cuc)
        else
            if s.loai == "danh" and os.clock() - (P.danhLuc or 0) < CFG.NHIP_DANH then
                return true            -- chua toi nhip chem, de vong sau
            end
            -- Slot nay dang giu tool KHAC luc record -> dang o bo kia. Swap cho
            -- khop roi hay ban. So bang TEN TOOL doc truc tiep tu Backpack nen
            -- luon dung, khong phu thuoc remote nao ban ve.
            if s.ten and (s.loai == "q" or s.loai == "e") then
                local dangCo = tenToolO(s.loai)
                if dangCo and dangCo ~= s.ten then
                    banSwap()
                    return false
                end
            end
            xoayMat(s, r, h)
            local xong
            if s.loai == "danh" then
                xong = chemTay()
                if xong then P.danhLuc = os.clock() end
            elseif s.loai == "q" then
                xong = banSkill("q")
            elseif s.loai == "e" then
                xong = banSkill("e")
            elseif s.loai == "swap" or s.loai == "f" then
                xong = banSwap()
            elseif s.loai == "nhay" then
                if h then h.Jump = true end
                xong = true
            else
                xong = true
            end
            if not xong then
                if os.clock() - (P.mocNut or 0) > CFG.HET_GIO_NUT then
                    M.nutHut = (M.nutHut or 0) + 1
                    P.iSK = P.iSK + 1
                    P.mocNut = os.clock()
                end
                return false
            end
            P.iSK = P.iSK + 1
            P.mocNut = os.clock()
        end
    end
    return true
end

-- MOT NHIP CHAY LAI. Chay trong render step, uu tien SAU ControlModule cua game
-- nen lenh Move o day la lenh cuoi truoc buoc vat ly.
local function buocChay(dt)
    if not M.dangChay then return end
    local h, r = hum(), hrp()
    if not h or not r or h.Health <= 0 then
        P.chetLuc = P.chetLuc or os.clock()
        M.tienDo = ("%d/%d cho hoi sinh"):format(P.i, P.n)
        return
    end

    -- Vua hoi sinh: hoi sinh o cua ai ma con tro dang o cuoi map -> di thang toi
    -- do la xuyen tuong vo nghia. Do lai khung gan nhat roi di lai tu do.
    if P.chetLuc then
        P.chetLuc = nil
        local j = timKhungGanNhat(r.Position, true)
        P.i = j
        P.iSK = suKienTuKhung(j)
        P.hold = nil
        P.moc, P.mocNut, P.mocKet = os.clock(), os.clock(), os.clock()
        P.viTri = r.Position
        M.soDo = (M.soDo or 0) + 1
        return
    end

    -- Het khung: ban not nhung nut con sot roi dung
    if P.i > P.n then
        P.mocXong = P.mocXong or os.clock()
        if P.iSK <= #macro.sukien and os.clock() - P.mocXong < CFG.HET_GIO_NUT then
            thuBanNut(h, r)
            h:Move(Vector3.new(0, 0, 0), false)
            return
        end
        M.lyDoDung = "xong"
        M.dungChay()
        return
    end

    local pos = r.Position
    local k   = macro.khung[P.i]
    local moc = Vector3.new(k.x, k.y, k.z)
    local lech = (Vector3.new(moc.X - pos.X, 0, moc.Z - pos.Z)).Magnitude

    -- Lac qua xa (bi day, bi keo, di nham nga) -> do lai khung gan nhat
    if lech > CFG.NGUONG_LAC and os.clock() - (P.mocDo or 0) > 3 then
        P.mocDo = os.clock()
        local j, d = timKhungGanNhat(pos, true)
        if j and d and d < lech - 5 then
            P.i = j
            P.iSK = suKienTuKhung(j)
            P.hold = nil
            P.moc = os.clock()
            M.soDo = (M.soDo or 0) + 1
            return
        end
    end

    local xongNut = thuBanNut(h, r)
    local st  = h:GetState()
    local bay = (st == Enum.HumanoidStateType.Freefall)
            or (st == Enum.HumanoidStateType.Jumping)

    if CFG.DONG_BO_TOC_DO and k.w and math.abs((h.WalkSpeed or 0) - k.w) > 0.5 then
        h.WalkSpeed = k.w
    end

    -- KHUC CHONG DUNG YEN: dung du so giay da dung (cho bay, cho nen sap, cho
    -- quai di qua). Day la thu ban cu lam sai nhat: no bo han thoi gian nen chay
    -- thang vao bay.
    if (not bay) and lech <= CFG.NGUONG_BAM and dungYen(P.i) then
        if not P.hold then P.hold, P.holdT = os.clock(), (k.t or 0) end
        local troi = os.clock() - P.hold
        -- `P.i <= P.n` chu khong phai `<`: phai cho con tro di QUA khung cuoi,
        -- khong thi macro ket thuc o khung chot va treo cho tan het gio.
        while xongNut and P.i <= P.n and dungYen(P.i)
            and ((macro.khung[P.i].t or 0) - P.holdT) <= troi do
            banCoNhay(macro.khung[P.i], h)
            P.i = P.i + 1
            P.moc = os.clock()
        end
        if not dungYen(P.i) then P.hold = nil end
        -- Dang DUNG CO Y thi khong duoc tinh la ket. Thieu dong nay la vua het
        -- khuc dung cho, dong ho ket da qua han -> bot nhay mot cai vo co
        -- (do live: "ket 2" o doan dung yen 1 giay).
        P.viTri, P.mocKet = pos, os.clock()
        if lech > CFG.NGUONG_TOI then
            h:Move(donVi(Vector3.new(moc.X - pos.X, 0, moc.Z - pos.Z)), false)
        else
            h:Move(Vector3.new(0, 0, 0), false)
        end
        M.tienDo = ("%d/%d dung cho %.1fs"):format(P.i, P.n, troi)
        return
    end
    P.hold = nil

    -- Tien khung theo vi tri: toi dau tinh den do.
    -- `not dungYen(P.i)`: phai DUNG LAI o khung dau khuc dung yen, khong duoc
    -- an mot phat qua het khuc do. Khung dung yen nam dung cho nguoi dang dung
    -- nen daToi() luon dung -> thieu chot nay la bot chay thang vao bay.
    local tien = 0
    while xongNut and P.i <= P.n and tien < 40
        and (not dungYen(P.i)) and daToi(pos, P.i) do
        banCoNhay(macro.khung[P.i], h)
        P.i = P.i + 1
        tien = tien + 1
        P.moc = os.clock()
    end
    if P.i > P.n then
        h:Move(Vector3.new(0, 0, 0), false)
        return                      -- vong sau vao nhanh "het khung" o tren
    end
    k = macro.khung[P.i] or k
    moc = Vector3.new(k.x, k.y, k.z)
    lech = (Vector3.new(moc.X - pos.X, 0, moc.Z - pos.Z)).Magnitude

    -- Nut chua ban duoc: dung dung cho nguoi that da dung ma cho, dung di tiep
    if not xongNut then
        if lech > CFG.NGUONG_TOI then
            h:Move(donVi(Vector3.new(moc.X - pos.X, 0, moc.Z - pos.Z)), false)
        else
            h:Move(Vector3.new(0, 0, 0), false)
        end
        M.tienDo = ("%d/%d cho nut"):format(P.i, P.n)
        return
    end

    local ghi = huongGhi(P.i)
    local huong
    if bay then
        -- Tren khong thi lai theo dung huong nguoi that bam (dieu khien khong
        -- trung). Tu lai o day la hong cu nhay qua khe.
        huong = (ghi.Magnitude > 0.05) and ghi
            or donVi(Vector3.new(moc.X - pos.X, 0, moc.Z - pos.Z))
    elseif lech > CFG.NGUONG_BAM then
        huong = donVi(Vector3.new(moc.X - pos.X, 0, moc.Z - pos.Z))
    else
        local ng = diemNgam(pos, P.i)
        huong = donVi(Vector3.new(ng.X - pos.X, 0, ng.Z - pos.Z) + ghi * 0.35)
    end
    h:Move(huong, false)

    -- NHAY BU (suy luan, khong phai logic game): ban ghi dang o tren khong /
    -- dang nhay ma bot van chay duoi thap va moc cao hon dau -> nhay.
    if (not bay) and (k.s == 2 or k.s == 3) and (k.y - pos.Y) > 2.5
        and os.clock() - (P.nhayLuc or 0) > 0.35 then
        P.nhayLuc = os.clock()
        h.Jump = true
    end

    -- Ket tai cho (quai chan, goc tuong) -> nhay thu.
    -- `not bay`: dang roi / dang nhay thi khong phai ket, nhay them chi pha cu
    -- nhay dang dang (do live: "ket 1" ngay sau khi nhan vat roi xuong dat).
    if bay or (pos - (P.viTri or pos)).Magnitude > 1.2 then
        P.viTri, P.mocKet = pos, os.clock()
    elseif os.clock() - (P.mocKet or os.clock()) > CFG.KET_GIAY then
        P.mocKet = os.clock()
        h.Jump = true
        M.soKet = (M.soKet or 0) + 1
    end

    -- Khung khong tai nao toi duoc -> bo, khong treo vinh vien
    if os.clock() - (P.moc or os.clock()) > CFG.HET_GIO_KHUNG then
        M.boQua = (M.boQua or 0) + 1
        P.i = P.i + 1
        P.moc = os.clock()
    end

    M.tienDo = ("%d/%d lech %.0f"):format(P.i, P.n, lech)
end

local function nhipAnToan(dt)
    local ok, loi = pcall(buocChay, dt)
    if ok then return end
    P.loi = (P.loi or 0) + 1
    if P.loi <= 3 then warn("[MACRO AI] loi khi chay: " .. tostring(loi)) end
    if P.loi > 40 then
        M.lyDoDung = "loi lien tuc"
        M.dungChay()
    end
end

local function batRender()
    P.render, P.tim = false, nil
    local ok = pcall(function()
        RunService:BindToRenderStep(TEN_BIND,
            Enum.RenderPriority.Input.Value + 10, nhipAnToan)
    end)
    if ok then
        P.render = true
        return
    end
    -- Duong lui: executor khong cho BindToRenderStep. Luc do phai TAT tay dieu
    -- khien cua game, khong thi moi render step no lai ghim move vector ve 0
    -- (ControlModule.lua:238-252) va macro khong dieu khien duoc gi.
    P.ctrl = dieuKhien()
    if P.ctrl then pcall(function() P.ctrl:Disable() end) end
    P.tim = RunService.Heartbeat:Connect(nhipAnToan)
end

local function tatRender()
    if P.render then
        pcall(function() RunService:UnbindFromRenderStep(TEN_BIND) end)
        P.render = false
    end
    if P.tim then
        pcall(function() P.tim:Disconnect() end)
        P.tim = nil
    end
    if P.ctrl then
        pcall(function() P.ctrl:Enable() end)
        P.ctrl = nil
    end
end

function M.chay()
    if M.dangGhi or M.dangChay then return end
    if #macro.khung == 0 then
        M.lyDoDung = "macro rong"
        return
    end
    ganKhungChoSuKien()
    tatRender()                      -- don sach ban bind cu neu con sot
    local r = hrp()
    P = { i = 1, n = #macro.khung, iSK = 1, loi = 0,
          moc = os.clock(), mocNut = os.clock(), mocKet = os.clock(), mocDo = 0,
          danhLuc = 0, nhayLuc = 0, viTri = r and r.Position or nil }
    -- Bam macro giua duong (vd chay tay): bat dau tu khung SOM nhat gan cho dang
    -- dung, khong keo nguoi ve dau map.
    if r then
        P.i = timKhungDau(r.Position, 20)
        P.iSK = suKienTuKhung(P.i)
    end
    M.boQua, M.nutHut, M.soDo, M.soKet, M.lyDoDung = 0, 0, 0, 0, nil
    local h = hum()
    if h then h.AutoRotate = true end
    M.dangChay = true
    batRender()
end

function M.dungChay()
    if not M.dangChay then
        tatRender()
        return
    end
    M.dangChay = false
    tatRender()
    local h = hum()
    if h then pcall(function() h:Move(Vector3.new(0, 0, 0), false) end) end
    M.tienDo = nil
    if not M.lyDoDung then M.lyDoDung = "chong bam dung" end
    if M.capNhatGui then pcall(M.capNhatGui) end
end

--== AUTO PLAYBACK: van moi -> cho CHO_SAU_START giay -> chay macro ============
-- Bat theo CANH DOI (doi tu gia tri nay sang gia tri kia), khong theo trang thai
-- dung yen. Ly do: khi choi lai bang replayDungeon, workspace.start co the GIU
-- NGUYEN true, chi dungeonFinished nhay ve false - khong co luc nao ca hai cung
-- "tat" de co duoc ha xuong => van sau khong bao gio chay lai.
--   start / dungeonStarted: false -> true   = van moi bat dau
--   dungeonProgress -> "inProgress"         = da vao tran that (readyButton tu
--                                             huy luc do, readyButton:6-9)
--   dungeonFinished: true -> false          = da sang van moi
--   dungeonName doi                         = sang ai khac
local canh = {}

function M.tuChonMacro()
    local ai = thongTinAi()
    if not ai.ai then return false end
    local aiL = string.lower(tostring(ai.ai))
    local khL = ai.doKho and string.lower(tostring(ai.doKho)) or nil
    local khop, khopAi = nil, nil
    for _, m in ipairs(danhSach) do
        if type(m) == "table" and m.ai and string.lower(tostring(m.ai)) == aiL then
            if khL and m.doKho and string.lower(tostring(m.doKho)) == khL then
                if m.hardcore == ai.hardcore or ai.hardcore == nil then
                    khop = khop or m.ten
                end
            end
            khopAi = khopAi or m.ten
        end
    end
    local chon = khop or khopAi
    if not chon or chon == tenDangChon then return chon ~= nil end
    local ok = M.napTen(chon)
    if ok and M.veDanhSach then pcall(M.veDanhSach) end
    return ok
end

function M.thuTuChay()
    local st = workspace:FindFirstChild("start")
    local ds = workspace:FindFirstChild("dungeonStarted")
    local dp = workspace:FindFirstChild("dungeonProgress")
    local dn = workspace:FindFirstChild("dungeonName")
    local batDau = (st ~= nil and st.Value == true) or (ds ~= nil and ds.Value == true)
    local xong   = daXongAi()
    local ten    = dn and dn.Value or nil
    local tt     = dp and dp.Value or nil

    local moi = false
    if canh.batDau == false and batDau == true then moi = true end
    if canh.xong == true and xong == false then moi = true end
    if canh.tt ~= nil and canh.tt ~= "inProgress" and tt == "inProgress" then moi = true end
    if canh.ten ~= nil and ten ~= nil and ten ~= canh.ten then moi = true end
    -- Lan quan sat dau tien ma van da chay: cung cho du CHO_SAU_START giay, vi
    -- luc moi nap script nhan vat / tool con dang tai.
    if canh.batDau == nil and batDau == true then moi = true end
    canh.batDau, canh.xong, canh.ten, canh.tt = batDau, xong, ten, tt

    if moi then
        daChayVanNay = false
        M.mocChay = os.clock() + CFG.CHO_SAU_START
        if M.autoChonAi then pcall(M.tuChonMacro) end
    end

    if M.dangGhi or M.dangChay then return end
    if xong or not batDau then return end       -- chua vao tran / da xong
    if daChayVanNay then return end
    if M.mocChay and os.clock() < M.mocChay then return end
    if not tenDangChon and M.autoChonAi then pcall(M.tuChonMacro) end
    if not tenDangChon then return end
    if #macro.khung == 0 then return end

    daChayVanNay = true
    M.chay()
end

--== NHIEU MACRO: luu / nap / xoa theo TEN =====================================
-- Moi macro mot file rieng `macro_ai_<ten>.json`, kem mot file danh sach ten.
-- Khong dung `listfiles` vi khong phai executor nao cung co.
local function docFile(duongDan)
    if type(isfile) ~= "function" or type(readfile) ~= "function" then return nil end
    if not isfile(duongDan) then return nil end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(duongDan))
    end)
    return ok and data or nil
end

local function tenSach(ten)
    ten = tostring(ten or ""):gsub("^%s+", ""):gsub("%s+$", "")
    ten = ten:gsub("[^%w%s_%-]", ""):gsub("%s+", "_")
    return ten
end

local function duongDan(ten)
    return ("macro_ai_%s.json"):format(ten)
end

-- Muc trong danh sach co the la chuoi (file cu) hoac bang (file moi co kem ai).
local function mucTen(m)
    if type(m) == "string" then return m end
    if type(m) == "table" then return m.ten end
    return nil
end

local function luuDanhSach()
    if type(writefile) ~= "function" then return end
    pcall(function()
        writefile(TEP_DANHSACH, HttpService:JSONEncode(danhSach))
    end)
end

function M.napDanhSach()
    local d = docFile(TEP_DANHSACH)
    danhSach = {}
    if type(d) == "table" then
        for _, m in ipairs(d) do
            local t = mucTen(m)
            if t then
                if type(m) == "string" then
                    danhSach[#danhSach + 1] = { ten = t }
                else
                    danhSach[#danhSach + 1] = m
                end
            end
        end
    end
    -- macro cu tu ban dau: gom vao danh sach cho khoi mat
    if type(isfile) == "function" and isfile(TEP_CU) then
        local coRoi = false
        for _, m in ipairs(danhSach) do
            if mucTen(m) == "macro_cu" then coRoi = true end
        end
        if not coRoi then
            danhSach[#danhSach + 1] = { ten = "macro_cu" }
            if type(writefile) == "function" and type(readfile) == "function" then
                pcall(function() writefile(duongDan("macro_cu"), readfile(TEP_CU)) end)
            end
            luuDanhSach()
        end
    end
    return danhSach
end

function M.luuTen(ten)
    ten = tenSach(ten)
    if ten == "" then return false, "chua dat ten" end
    if type(writefile) ~= "function" then return false, "executor khong co writefile" end
    if #macro.khung == 0 then return false, "chua ghi gi" end
    ganKhungChoSuKien()
    local ok = pcall(function()
        writefile(duongDan(ten), HttpService:JSONEncode(macro))
    end)
    if not ok then return false, "ghi file loi" end
    local muc = { ten = ten, ai = macro.ai, doKho = macro.doKho,
                  hardcore = macro.hardcore, khung = #macro.khung }
    local thay = false
    for i, m in ipairs(danhSach) do
        if mucTen(m) == ten then
            danhSach[i] = muc
            thay = true
        end
    end
    if not thay then danhSach[#danhSach + 1] = muc end
    luuDanhSach()
    tenDangChon = ten
    return true
end

function M.napTen(ten)
    ten = tenSach(ten)
    if ten == "" then return false, "chua chon macro" end
    local data = docFile(duongDan(ten))
    if type(data) ~= "table" or type(data.khung) ~= "table" then
        return false, "file hong hoac chua co"
    end
    macro = { ver = data.ver or 1, ai = data.ai, doKho = data.doKho,
              hardcore = data.hardcore, nhip = data.nhip,
              khung = data.khung, sukien = data.sukien or {} }
    ganKhungChoSuKien()
    tenDangChon = ten
    return true
end

function M.xoaTen(ten)
    ten = tenSach(ten)
    if ten == "" then return false end
    if type(delfile) == "function" then
        pcall(function() delfile(duongDan(ten)) end)
    end
    for i = #danhSach, 1, -1 do
        if mucTen(danhSach[i]) == ten then table.remove(danhSach, i) end
    end
    luuDanhSach()
    if tenDangChon == ten then tenDangChon = nil end
    return true
end

--== GUI =======================================================================
local UI = {}

local gui = Instance.new("ScreenGui")
gui.Name = "MacroAI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = (gethui and gethui()) or LP:WaitForChild("PlayerGui")

local bang = Instance.new("Frame")
bang.Size = UDim2.new(0, 230, 0, 504)
-- Mac dinh nam BEN PHAI man hinh (chong yeu cau). Van keo tha duoc.
bang.Position = UDim2.new(1, -250, 0.5, -252)
bang.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
bang.BorderSizePixel = 0
bang.Active = true
bang.Draggable = true
bang.Parent = gui
Instance.new("UICorner", bang).CornerRadius = UDim.new(0, 8)

local tieuDe = Instance.new("TextLabel")
tieuDe.Size = UDim2.new(1, -34, 0, 22)
tieuDe.Position = UDim2.new(0, 8, 0, 4)
tieuDe.BackgroundTransparency = 1
tieuDe.Text = "MACRO AI v2"
tieuDe.TextXAlignment = Enum.TextXAlignment.Left
tieuDe.TextColor3 = Color3.fromRGB(235, 240, 250)
tieuDe.Font = Enum.Font.GothamBold
tieuDe.TextSize = 14
tieuDe.Parent = bang

local trangThai = Instance.new("TextLabel")
trangThai.Size = UDim2.new(1, -16, 0, 48)
trangThai.Position = UDim2.new(0, 8, 0, 28)
trangThai.BackgroundColor3 = Color3.fromRGB(18, 19, 25)
trangThai.Text = "san sang"
trangThai.TextColor3 = Color3.fromRGB(150, 200, 255)
trangThai.Font = Enum.Font.Gotham
trangThai.TextSize = 11
trangThai.TextWrapped = true
trangThai.TextYAlignment = Enum.TextYAlignment.Top
trangThai.Parent = bang
Instance.new("UICorner", trangThai).CornerRadius = UDim.new(0, 6)

local oTen = Instance.new("TextBox")
oTen.Size = UDim2.new(1, -16, 0, 26)
oTen.Position = UDim2.new(0, 8, 0, 80)
oTen.BackgroundColor3 = Color3.fromRGB(18, 19, 25)
oTen.PlaceholderText = "dat ten macro..."
oTen.Text = ""
oTen.TextColor3 = Color3.fromRGB(240, 240, 240)
oTen.PlaceholderColor3 = Color3.fromRGB(120, 125, 140)
oTen.Font = Enum.Font.Gotham
oTen.TextSize = 12
oTen.ClearTextOnFocus = false
oTen.Parent = bang
Instance.new("UICorner", oTen).CornerRadius = UDim.new(0, 6)

local function taoNut(ten, x, y, rong, mau, chay)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, rong, 0, 26)
    b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = mau
    b.Text = ten
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 11
    b.AutoButtonColor = true
    b.Parent = bang
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(function() pcall(chay) end)
    return b
end

local danhSachKhung = Instance.new("ScrollingFrame")
danhSachKhung.Size = UDim2.new(1, -16, 0, 120)
danhSachKhung.Position = UDim2.new(0, 8, 0, 170)
danhSachKhung.BackgroundColor3 = Color3.fromRGB(18, 19, 25)
danhSachKhung.BorderSizePixel = 0
danhSachKhung.ScrollBarThickness = 4
danhSachKhung.CanvasSize = UDim2.new(0, 0, 0, 0)
danhSachKhung.Parent = bang
Instance.new("UICorner", danhSachKhung).CornerRadius = UDim.new(0, 6)

local xepDoc = Instance.new("UIListLayout")
xepDoc.Padding = UDim.new(0, 2)
xepDoc.Parent = danhSachKhung

function M.veDanhSach()
    for _, c in ipairs(danhSachKhung:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    local n = 0
    for _, m in ipairs(danhSach) do
        local ten = mucTen(m)
        if ten then
            n = n + 1
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1, -8, 0, 24)
            b.BackgroundColor3 = (ten == tenDangChon)
                and Color3.fromRGB(45, 100, 160) or Color3.fromRGB(38, 41, 52)
            local phu = ""
            if type(m) == "table" and m.ai then
                phu = "  (" .. nhanAi(m) .. ")"
            end
            b.Text = (ten == tenDangChon and "> " or "   ") .. ten .. phu
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.TextTruncate = Enum.TextTruncate.AtEnd
            b.TextColor3 = Color3.fromRGB(235, 238, 245)
            b.Font = Enum.Font.Gotham
            b.TextSize = 11
            b.Parent = danhSachKhung
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
            b.MouseButton1Click:Connect(function()
                local ok, vi = M.napTen(ten)
                oTen.Text = ten
                trangThai.Text = ok
                    and ("chon [%s]  %d khung / %d nut"):format(
                        ten, #macro.khung, #macro.sukien)
                    or ("khong nap duoc: " .. tostring(vi))
                M.veDanhSach()
            end)
        end
    end
    danhSachKhung.CanvasSize = UDim2.new(0, 0, 0, n * 26 + 4)
end

function M.capNhatGui()
    local d1, d2, d3
    if M.dangGhi then
        d1 = ("DANG GHI  %d khung / %d nut"):format(#macro.khung, #macro.sukien)
        trangThai.TextColor3 = Color3.fromRGB(255, 140, 140)
        UI.ghi.Text = "DUNG GHI"
    elseif M.dangChay then
        d1 = ("DANG CHAY  %s"):format(M.tienDo or ("0/" .. #macro.khung))
        trangThai.TextColor3 = Color3.fromRGB(140, 255, 170)
        UI.ghi.Text = "GHI MACRO"
    else
        d1 = ("san sang%s"):format(M.lyDoDung and ("  (" .. M.lyDoDung .. ")") or "")
        trangThai.TextColor3 = Color3.fromRGB(150, 200, 255)
        UI.ghi.Text = "GHI MACRO"
    end
    d2 = ("[%s] %d khung / %d nut"):format(
        tenDangChon or "chua chon", #macro.khung, #macro.sukien)
    if macro.ai then d2 = d2 .. "  ghi o: " .. nhanAi(macro) end
    d3 = "ai gio: " .. nhanAi(thongTinAi())
    if M.autoPlay and M.mocChay and os.clock() < M.mocChay
        and not M.dangChay and not M.dangGhi then
        d3 = d3 .. ("  | cho start %ds"):format(
            math.ceil(M.mocChay - os.clock()))
    end
    if (M.boQua or 0) > 0 or (M.nutHut or 0) > 0 or (M.soDo or 0) > 0
        or (M.soKet or 0) > 0 then
        d3 = d3 .. ("  | bo %d khung / %d nut, do lai %d, ket %d"):format(
            M.boQua or 0, M.nutHut or 0, M.soDo or 0, M.soKet or 0)
    end
    trangThai.Text = d1 .. XUONG_DONG .. d2 .. XUONG_DONG .. d3

    UI.chay.Text = M.dangChay and "DUNG CHAY" or "CHAY MACRO"
    -- Ten hai nut chieu doc lai tu Backpack moi lan -> Swap xong tu doi ten.
    local tq, te = tenToolO("q"), tenToolO("e")
    UI.q.Text = tq and ("Q: " .. string.sub(tq, 1, 12)) or "Q: (khong co)"
    UI.e.Text = te and ("E: " .. string.sub(te, 1, 12)) or "E: (khong co)"
    if tq or te then
        UI.swap.Text = ("SWAP  q:%s  e:%s"):format(
            tq and string.sub(tq, 1, 8) or "?", te and string.sub(te, 1, 8) or "?")
    else
        UI.swap.Text = "SWAP (doi bo skill)"
    end

    local xanh, do_ = Color3.fromRGB(40, 110, 70), Color3.fromRGB(70, 50, 50)
    UI.start.Text = "Start: " .. (M.autoStart and "BAT" or "TAT")
    UI.start.BackgroundColor3 = M.autoStart and xanh or do_
    UI.replay.Text = "Replay: " .. (M.autoReplay and "BAT" or "TAT")
    UI.replay.BackgroundColor3 = M.autoReplay and xanh or do_
    UI.play.Text = "Playback: " .. (M.autoPlay and "BAT" or "TAT")
    UI.play.BackgroundColor3 = M.autoPlay and xanh or do_
    UI.chonAi.Text = "Tu chon ai: " .. (M.autoChonAi and "BAT" or "TAT")
    UI.chonAi.BackgroundColor3 = M.autoChonAi and xanh or do_
    UI.cho.Text = ("Cho start: %ds"):format(CFG.CHO_SAU_START)
    UI.toc.Text = "Toc do: " .. (CFG.DONG_BO_TOC_DO and "theo ghi" or "nguyen")
    UI.toc.BackgroundColor3 = CFG.DONG_BO_TOC_DO and xanh or do_
end

UI.ghi = taoNut("GHI MACRO", 8, 110, 104, Color3.fromRGB(150, 60, 60), function()
    if M.dangGhi then
        M.dungGhiLai()
    else
        M.batGhi()
        if tenSach(oTen.Text) == "" then
            local ai = thongTinAi()
            if ai.ai then oTen.Text = tenSach(nhanAi(ai)) end
        end
    end
    M.capNhatGui()
end)

UI.chay = taoNut("CHAY MACRO", 118, 110, 104, Color3.fromRGB(45, 100, 160), function()
    if M.dangChay then
        M.lyDoDung = "chong bam dung"
        M.dungChay()
    else
        M.chay()
    end
    M.capNhatGui()
end)

taoNut("LUU THANH TEN", 8, 140, 104, Color3.fromRGB(60, 70, 95), function()
    local ok, vi = M.luuTen(oTen.Text)
    trangThai.Text = ok and ("da luu [%s]"):format(tenSach(oTen.Text))
        or ("luu that bai: " .. tostring(vi))
    M.veDanhSach()
end)

taoNut("XOA", 118, 140, 104, Color3.fromRGB(110, 50, 50), function()
    local ten = tenSach(oTen.Text)
    if ten == "" then
        trangThai.Text = "go ten can xoa vao o tren"
        return
    end
    M.xoaTen(ten)
    trangThai.Text = ("da xoa [%s]"):format(ten)
    M.veDanhSach()
end)

-- HAI NUT XAI CHIEU RIENG: ten nut doc tu Backpack nen Swap xong tu doi ten.
-- Bam nut = xai chieu THAT + neu dang ghi thi ghi luon vao macro.
local function bamChieu(slot)
    local ten = tenToolO(slot) or slot
    local ok = banSkill(slot)
    if ok and M.dangGhi then ghiSuKien(slot, ten) end
    if ok then
        trangThai.Text = M.dangGhi
            and ("da xai [" .. ten .. "] + ghi vao macro")
            or ("da xai [" .. ten .. "]")
    else
        local tool = toolSkill(slot)
        local cd = tool and tool:FindFirstChild("cooldown")
        local con = cd and tonumber(cd.Value) or nil
        if con and con > 0 then
            trangThai.Text = ("[%s] dang hoi chieu %.1fs"):format(ten, con)
        else
            trangThai.Text = ("[%s] chua xai duoc"):format(ten)
        end
    end
end

UI.q = taoNut("Q", 8, 294, 104, Color3.fromRGB(45, 95, 130), function()
    bamChieu("q")
end)

UI.e = taoNut("E", 118, 294, 104, Color3.fromRGB(45, 95, 130), function()
    bamChieu("e")
end)

UI.swap = taoNut("SWAP (doi bo skill)", 8, 324, 214,
    Color3.fromRGB(120, 80, 165), function()
    local ok = banSwap()
    if ok and M.dangGhi then ghiSuKien("swap") end
    trangThai.Text = ok
        and (M.dangGhi and "da SWAP + ghi vao macro" or "da SWAP")
        or "swap chua duoc, cho 0.5 giay roi bam lai"
end)

UI.start = taoNut("Start: BAT", 8, 354, 104, Color3.fromRGB(40, 110, 70), function()
    M.autoStart = not M.autoStart
    M.capNhatGui()
end)

UI.replay = taoNut("Replay: BAT", 118, 354, 104, Color3.fromRGB(40, 110, 70), function()
    M.autoReplay = not M.autoReplay
    M.capNhatGui()
end)

-- AUTO PLAYBACK: chon macro nao thi MOI VAN MOI no tu chay macro do, sau khi cho
-- du CHO_SAU_START giay ke tu luc van bat dau.
UI.play = taoNut("Playback: TAT", 8, 384, 104, Color3.fromRGB(70, 50, 50), function()
    M.autoPlay = not M.autoPlay
    if not M.autoPlay then
        daChayVanNay = false
    else
        M.mocChay = os.clock() + CFG.CHO_SAU_START
    end
    M.capNhatGui()
end)

UI.chonAi = taoNut("Tu chon ai: BAT", 118, 384, 104,
    Color3.fromRGB(40, 110, 70), function()
    M.autoChonAi = not M.autoChonAi
    if M.autoChonAi then pcall(M.tuChonMacro) end
    M.capNhatGui()
end)

UI.cho = taoNut("Cho start: 10s", 8, 414, 104, Color3.fromRGB(60, 70, 95), function()
    local buoc = { 0, 3, 5, 10, 15, 20, 30 }
    local vi = 1
    for i, v in ipairs(buoc) do
        if v == CFG.CHO_SAU_START then vi = i end
    end
    CFG.CHO_SAU_START = buoc[(vi % #buoc) + 1]
    M.capNhatGui()
end)

UI.toc = taoNut("Toc do: nguyen", 118, 414, 104, Color3.fromRGB(70, 50, 50), function()
    CFG.DONG_BO_TOC_DO = not CFG.DONG_BO_TOC_DO
    M.capNhatGui()
end)

local ghiChu = Instance.new("TextLabel")
ghiChu.Size = UDim2.new(1, -16, 0, 54)
ghiChu.Position = UDim2.new(0, 8, 0, 444)
ghiChu.BackgroundTransparency = 1
ghiChu.Text = "Ghi: di dung nhu binh thuong, bam phim hay nut tren man hinh deu ghi duoc."
    .. XUONG_DONG .. "Chay lai: di theo dung huong da bam, dung du cho da dung, nhay dung diem."
    .. XUONG_DONG .. "Playback: van moi -> cho 10s -> tu chay macro khop ten ai + do kho."
ghiChu.TextColor3 = Color3.fromRGB(120, 128, 145)
ghiChu.Font = Enum.Font.Gotham
ghiChu.TextSize = 10
ghiChu.TextWrapped = true
ghiChu.TextYAlignment = Enum.TextYAlignment.Top
ghiChu.Parent = bang

-- Nut thu gon cho man hinh dien thoai
local nutThu = Instance.new("TextButton")
nutThu.Size = UDim2.new(0, 26, 0, 22)
nutThu.Position = UDim2.new(1, -30, 0, 4)
nutThu.BackgroundColor3 = Color3.fromRGB(60, 64, 78)
nutThu.Text = "-"
nutThu.TextColor3 = Color3.fromRGB(240, 240, 240)
nutThu.Font = Enum.Font.GothamBold
nutThu.TextSize = 14
nutThu.Parent = bang
Instance.new("UICorner", nutThu).CornerRadius = UDim.new(0, 6)
nutThu.MouseButton1Click:Connect(function()
    local thu = bang.Size.Y.Offset > 40
    for _, c in ipairs(bang:GetChildren()) do
        if c ~= tieuDe and c ~= nutThu and not c:IsA("UICorner") then
            if c:IsA("GuiObject") then c.Visible = not thu end
        end
    end
    bang.Size = thu and UDim2.new(0, 230, 0, 30) or UDim2.new(0, 230, 0, 504)
    nutThu.Text = thu and "+" or "-"
end)

--== vong chay nen =============================================================
M.song = true
task.spawn(function()
    while M.song do
        if M.autoStart then pcall(thuBamStart) end
        if M.autoReplay then pcall(thuReplay) end
        if M.autoPlay then pcall(M.thuTuChay) end
        pcall(M.capNhatGui)
        task.wait(0.5)
    end
end)

function M.tat()
    M.song = false
    M.dangGhi = false
    if M.dangChay then
        M.lyDoDung = "tat script"
        pcall(M.dungChay)
    end
    pcall(tatRender)
    pcall(ngatHet)
    pcall(function() gui:Destroy() end)
end

M.napDanhSach()
if M.autoChonAi then pcall(M.tuChonMacro) end
M.veDanhSach()
M.capNhatGui()
print(("[MACRO AI v2] da bat, co %d macro da luu. Tat bang:  _G.__MACRO_AI__.tat()")
    :format(#danhSach))
