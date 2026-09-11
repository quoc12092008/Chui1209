--==============================================================================
-- MACRO AI  -  auto start + auto replay + ghi/chay lai macro
--
-- Cach dung: dat file nay vao workspace cua executor roi chay
--     loadstring(readfile("macro_ai.lua"))()
--
-- Moi thu duoi day lay tu co che THAT dang dung trong Dqr.lua:
--   * remotes nam o  ReplicatedStorage.remotes
--   * bam START      -> remotes.changeStartValue   (khi co PlayerGui.startButton
--                       va Workspace.start ~= true)
--   * bam READY      -> remotes.readyUp            (khi co PlayerGui.readyButton)
--   * choi lai ai    -> remotes.replayDungeon(duLieuAi)
--   * danh tay       -> Accessory co con "Weapon" -> RemoteEvent trong Accessory
--                       :FireServer(), roi remotes.weaponUsed:FireServer()
--   * skill q/e      -> Tool co con "abilitySlot" = "q"/"e";
--                       tool.localEvent:Fire() roi remotes.abilityUsed(slot, tool)
--                       (chi khi tool.cooldown == 0)
--   * xong ai        -> Workspace.dungeon.bossRoom.dungeonFinished == true
--==============================================================================

local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local UIS         = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local LP          = Players.LocalPlayer

-- dung ban cu neu chay lai script
if _G.__MACRO_AI__ then
    pcall(function() _G.__MACRO_AI__.tat() end)
end

local M = { dangGhi = false, dangChay = false, autoStart = true, autoReplay = true }
_G.__MACRO_AI__ = M

local NHIP_GHI  = 0.1    -- giay moi khung duong di
local TEP_MACRO = "macro_ai_luu.json"
local macro     = { khung = {}, sukien = {} }

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

--== danh tay ==================================================================
-- Vu khi game nay la ACCESSORY (khong phai Tool): Accessory co con "Weapon" va
-- mot RemoteEvent ben trong.
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

local function chemTay()
    local re = remoteVuKhi()
    if not re then return false end
    if not pcall(function() re:FireServer() end) then return false end
    ban("weaponUsed")
    return true
end

--== skill q / e ===============================================================
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

local function banSkill(slot)
    local tool = toolSkill(slot)
    if not tool then return false end
    local cd = tool:FindFirstChild("cooldown")
    -- cooldown > 0 la dang hoi chieu, ban cung khong an
    if not cd or not cd:IsA("ValueBase") or (tonumber(cd.Value) or 1) > 0 then
        return false
    end
    local ev = tool:FindFirstChild("localEvent")
    if not ev or not ev:IsA("BindableEvent") then return false end
    if not pcall(function() ev:Fire() end) then return false end
    ban("abilityUsed", slot, tool)
    return true
end

--== auto start / auto replay ==================================================
local lanReady, lanStart, lanReplay = 0, 0, 0

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
local ketNoiInput, batDauLuc

local function ghiSuKien(loai)
    if not M.dangGhi then return end
    macro.sukien[#macro.sukien + 1] = { t = os.clock() - batDauLuc, loai = loai }
end

function M.batGhi()
    if M.dangChay then return end
    macro = { khung = {}, sukien = {} }
    batDauLuc = os.clock()
    M.dangGhi = true

    -- "sai nut gi luc nao": ghi thang INPUT cua chong, khong doan qua cooldown
    ketNoiInput = UIS.InputBegan:Connect(function(input, guiBatDuoc)
        if guiBatDuoc or not M.dangGhi then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            ghiSuKien("danh")
        elseif input.KeyCode == Enum.KeyCode.Q then
            ghiSuKien("q")
        elseif input.KeyCode == Enum.KeyCode.E then
            ghiSuKien("e")
        elseif input.KeyCode == Enum.KeyCode.Space then
            ghiSuKien("nhay")
        end
    end)

    task.spawn(function()
        while M.dangGhi do
            local r = hrp()
            if r then
                local p = r.Position
                local lv = r.CFrame.LookVector
                macro.khung[#macro.khung + 1] = {
                    t = os.clock() - batDauLuc,
                    x = p.X, y = p.Y, z = p.Z,
                    lx = lv.X, lz = lv.Z,
                }
            end
            task.wait(NHIP_GHI)
        end
    end)
end

function M.dungGhiLai()
    M.dangGhi = false
    if ketNoiInput then
        ketNoiInput:Disconnect()
        ketNoiInput = nil
    end
end

--== CHAY MACRO ================================================================
-- HAI LOI DA SUA (chong: "co thay chay dau no co di chuyen dau"):
--  1. Ban dau moi vong lap deu dat `r.CFrame = CFrame.new(viTriHienTai, huong)`.
--     Dat CFrame lien tuc nhu vay HUY VAN TOC cua nhan vat -> bi ghim tai cho,
--     Humanoid khong the buoc di. Nay BO han, de Humanoid tu xoay (AutoRotate)
--     theo huong no dang di.
--  2. `MoveTo` toi dung khung hien tai, ma moi khung chi cach nhau 1.63 studs
--     (do that tu file chong quay). Humanoid coi nhu DA TOI khi con ~2 studs
--     nen dung yen. Nay MoveTo toi diem NHIN TRUOC, cach it nhat NHIN_TRUOC studs.
local NHIN_TRUOC = 8      -- studs: diem ngam phai cach nguoi it nhat bay nhieu
local NGUONG_TUT = 14     -- studs: tut xa hon the thi CHO, khong bo qua doan duong

function M.chay()
    if M.dangGhi or M.dangChay then return end
    if #macro.khung == 0 then return end
    M.dangChay = true
    task.spawn(function()
        local h0 = hum()
        if h0 then h0.AutoRotate = true end
        local t0 = os.clock()
        local iKhung, iSuKien = 1, 1
        local treTong = 0          -- tong thoi gian da dung lai cho bat kip
        while M.dangChay do
            local t = os.clock() - t0 - treTong
            local h, r = hum(), hrp()
            if not h or not r then break end
            local viTri = r.Position

            -- tien khung theo thoi gian
            while iKhung < #macro.khung and macro.khung[iKhung].t < t do
                iKhung = iKhung + 1
            end

            local kHienTai = macro.khung[math.min(iKhung, #macro.khung)]
            if kHienTai then
                local diemMoc = Vector3.new(kHienTai.x, kHienTai.y, kHienTai.z)
                -- Tut lai qua xa (ket, bi chan, ro vao tuong): DUNG DONG HO lai
                -- cho toi khi bat kip, khong thi macro chay tiep con nguoi o lai.
                if (diemMoc - viTri).Magnitude > NGUONG_TUT then
                    treTong = treTong + 0.05
                end

                -- diem ngam: di toi truoc cho du xa de Humanoid chiu buoc
                local iNgam = iKhung
                local diemNgam = diemMoc
                while iNgam < #macro.khung
                    and (diemNgam - viTri).Magnitude < NHIN_TRUOC do
                    iNgam = iNgam + 1
                    local kn = macro.khung[iNgam]
                    diemNgam = Vector3.new(kn.x, kn.y, kn.z)
                end
                h:MoveTo(diemNgam)
            end

            -- phat lai cac nut da bam, dung moc thoi gian
            while iSuKien <= #macro.sukien and macro.sukien[iSuKien].t <= t do
                local s = macro.sukien[iSuKien]
                if s.loai == "danh" then
                    chemTay()
                elseif s.loai == "q" then
                    banSkill("q")
                elseif s.loai == "e" then
                    banSkill("e")
                elseif s.loai == "nhay" then
                    h.Jump = true
                end
                iSuKien = iSuKien + 1
            end

            M.tienDo = ("%d/%d"):format(iKhung, #macro.khung)

            -- xong khi da di het khung CUOI va ban het nut
            local kCuoi = macro.khung[#macro.khung]
            local toiDich = kCuoi
                and (Vector3.new(kCuoi.x, kCuoi.y, kCuoi.z) - viTri).Magnitude <= 6
            if iKhung >= #macro.khung and iSuKien > #macro.sukien and toiDich then
                break
            end
            -- chan an toan: khong chay qua gap doi thoi luong da ghi
            if os.clock() - t0 > (macro.khung[#macro.khung].t + 10) * 2 then break end
            task.wait(0.05)
        end
        M.dangChay = false
        M.tienDo = nil
        if M.capNhatGui then M.capNhatGui() end
    end)
end

function M.dungChay()
    M.dangChay = false
end

--== LUU / NAP =================================================================
function M.luu()
    if type(writefile) ~= "function" then return false, "executor khong co writefile" end
    return (pcall(function()
        writefile(TEP_MACRO, HttpService:JSONEncode(macro))
    end))
end

function M.nap()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then
        return false, "executor khong co readfile"
    end
    if not isfile(TEP_MACRO) then return false, "chua co file" end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(TEP_MACRO))
    end)
    if ok and type(data) == "table" and type(data.khung) == "table" then
        macro = { khung = data.khung, sukien = data.sukien or {} }
        return true
    end
    return false, "file hong"
end

--== GUI =======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "MacroAI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = (gethui and gethui()) or LP:WaitForChild("PlayerGui")

local bang = Instance.new("Frame")
bang.Size = UDim2.new(0, 210, 0, 252)
bang.Position = UDim2.new(0, 20, 0.5, -126)
bang.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
bang.BorderSizePixel = 0
bang.Active = true
bang.Draggable = true
bang.Parent = gui
Instance.new("UICorner", bang).CornerRadius = UDim.new(0, 8)

local tieuDe = Instance.new("TextLabel")
tieuDe.Size = UDim2.new(1, 0, 0, 28)
tieuDe.BackgroundTransparency = 1
tieuDe.Text = "MACRO AI"
tieuDe.TextColor3 = Color3.fromRGB(235, 240, 250)
tieuDe.Font = Enum.Font.GothamBold
tieuDe.TextSize = 14
tieuDe.Parent = bang

local trangThai = Instance.new("TextLabel")
trangThai.Size = UDim2.new(1, -16, 0, 30)
trangThai.Position = UDim2.new(0, 8, 0, 28)
trangThai.BackgroundColor3 = Color3.fromRGB(18, 19, 25)
trangThai.Text = "san sang"
trangThai.TextColor3 = Color3.fromRGB(150, 200, 255)
trangThai.Font = Enum.Font.Gotham
trangThai.TextSize = 11
trangThai.TextWrapped = true
trangThai.Parent = bang
Instance.new("UICorner", trangThai).CornerRadius = UDim.new(0, 6)

local function taoNut(ten, y, mau, chay)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -16, 0, 26)
    b.Position = UDim2.new(0, 8, 0, y)
    b.BackgroundColor3 = mau
    b.Text = ten
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 12
    b.AutoButtonColor = true
    b.Parent = bang
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(chay)
    return b
end

local nutGhi, nutChay, nutAutoStart, nutAutoReplay

function M.capNhatGui()
    if M.dangGhi then
        trangThai.Text = ("DANG GHI  %d khung / %d nut"):format(#macro.khung, #macro.sukien)
        trangThai.TextColor3 = Color3.fromRGB(255, 140, 140)
        nutGhi.Text = "DUNG GHI"
    elseif M.dangChay then
        trangThai.Text = ("DANG CHAY  %s khung / %d nut"):format(
            M.tienDo or ("0/" .. #macro.khung), #macro.sukien)
        trangThai.TextColor3 = Color3.fromRGB(140, 255, 170)
        nutGhi.Text = "GHI MACRO"
    else
        trangThai.Text = ("da co %d khung / %d nut"):format(#macro.khung, #macro.sukien)
        trangThai.TextColor3 = Color3.fromRGB(150, 200, 255)
        nutGhi.Text = "GHI MACRO"
    end
    nutChay.Text = M.dangChay and "DUNG CHAY" or "CHAY MACRO"
    nutAutoStart.Text = "Auto Start: " .. (M.autoStart and "BAT" or "TAT")
    nutAutoStart.BackgroundColor3 = M.autoStart
        and Color3.fromRGB(40, 110, 70) or Color3.fromRGB(70, 50, 50)
    nutAutoReplay.Text = "Auto Replay: " .. (M.autoReplay and "BAT" or "TAT")
    nutAutoReplay.BackgroundColor3 = M.autoReplay
        and Color3.fromRGB(40, 110, 70) or Color3.fromRGB(70, 50, 50)
end

nutGhi = taoNut("GHI MACRO", 64, Color3.fromRGB(150, 60, 60), function()
    if M.dangGhi then M.dungGhiLai() else M.batGhi() end
    M.capNhatGui()
end)

nutChay = taoNut("CHAY MACRO", 94, Color3.fromRGB(45, 100, 160), function()
    if M.dangChay then M.dungChay() else M.chay() end
    M.capNhatGui()
end)

taoNut("LUU", 124, Color3.fromRGB(60, 70, 95), function()
    local ok = M.luu()
    trangThai.Text = ok and ("da luu " .. TEP_MACRO) or "luu THAT BAI"
end)

taoNut("NAP LAI", 154, Color3.fromRGB(60, 70, 95), function()
    local ok, vi = M.nap()
    trangThai.Text = ok and ("da nap %d khung"):format(#macro.khung)
        or ("nap that bai: " .. tostring(vi))
end)

nutAutoStart = taoNut("Auto Start: BAT", 188, Color3.fromRGB(40, 110, 70), function()
    M.autoStart = not M.autoStart
    M.capNhatGui()
end)

nutAutoReplay = taoNut("Auto Replay: BAT", 218, Color3.fromRGB(40, 110, 70), function()
    M.autoReplay = not M.autoReplay
    M.capNhatGui()
end)

--== vong chay nen =============================================================
M.song = true
task.spawn(function()
    while M.song do
        if M.autoStart then pcall(thuBamStart) end
        if M.autoReplay then pcall(thuReplay) end
        pcall(M.capNhatGui)
        task.wait(1)
    end
end)

function M.tat()
    M.song = false
    M.dangGhi, M.dangChay = false, false
    if ketNoiInput then pcall(function() ketNoiInput:Disconnect() end) end
    pcall(function() gui:Destroy() end)
end

M.capNhatGui()
print("[MACRO AI] da bat. Tat bang:  _G.__MACRO_AI__.tat()")
