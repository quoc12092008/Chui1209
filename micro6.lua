--==============================================================================
-- MACRO AI  -  auto start + auto replay + ghi/chay lai NHIEU macro co ten
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
--
--   * phim F / nut Swap -> remotes.swapAbilitySet:FireServer()  KHONG tham so,
--     game co debounce 0.5 giay (Ui/inventory.lua:1395, Ui/abilities.lua:73).
--     F chinh la DOI BO SKILL, khong phai mot skill rieng.
--     abilitySlot trong source chi co "q" va "e"; doi bo la server thay tool
--     gan vao dung hai slot do (Ui/abilities.lua:22-31, PlayerGui/UIS.lua:59,77).
--
-- CHAY TREN DIEN THOAI: tren mobile khong co phim Q/E/F, chong bam NUT TREN MAN
-- HINH. Ban dau script ghi bang UserInputService va bo qua moi thu co
-- gameProcessedEvent = true (tuc la cham vao nut GUI) => tren dien thoai KHONG
-- GHI DUOC GI. Nay doi cach: uu tien ghi lai CAI GAME THUC SU GUI DI (hook
-- __namecall bat FireServer), nen bam kieu gi - phim, chuot, hay cham nut tren
-- man hinh - deu ghi duoc nhu nhau. Khong co hook thi lui ve hai lop du phong:
-- theo doi `cooldown` cua tool (chay duoc ca mobile) va bat phim (chi PC).
--==============================================================================

local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local UIS         = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local LP          = Players.LocalPlayer

-- Xuong dong trong chuoi Lua viet bang string.char(10).
-- Ly do: cong cu sinh file tung ghi nham ky tu escape thanh newline THAT,
-- lam chuoi Lua tran sang dong sau -> loi cu phap -> loadstring tra nil ->
-- chay ra 'attempt to call a nil value' ngay dong 1.
local XUONG_DONG = string.char(10)

-- dung ban cu neu chay lai script
if _G.__MACRO_AI__ then
    pcall(function() _G.__MACRO_AI__.tat() end)
end

local M = { dangGhi = false, dangChay = false, autoStart = true, autoReplay = true }
_G.__MACRO_AI__ = M

local NHIP_GHI    = 0.1    -- giay moi khung duong di
local TEP_DANHSACH = "macro_ai_danhsach.json"
local TEP_CU       = "macro_ai_luu.json"   -- ban dau chi co mot macro duy nhat
local macro        = { khung = {}, sukien = {} }
local danhSach     = {}    -- { "ten1", "ten2", ... }
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

--== skill q / e / f ===========================================================
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

-- DOI BO SKILL (Swap). Cu lieu THAT chong dua + source:
--   bo 1:  abilityUsed("q", Backpack["Water Orb"])
--   Swap:  swapAbilitySet:FireServer()           -- khong tham so
--   bo 2:  abilityUsed("q", Backpack["Inner Rage"])
--          abilityUsed("e", Backpack["Water Orb"])   <-- CHU Y
--
-- Doc ra duoc dieu quyet dinh: TOOL KHONG ROI BACKPACK khi Swap. Ca hai bo
-- deu nam san trong Backpack, Swap chi doi `abilitySlot.Value` cua chung.
-- Bang chung: "Water Orb" la slot q o bo 1, thanh slot e o bo 2.
-- Source UIS.lua:40-85 cung duyet dung kieu do:
--     for _, child in pairs(LocalPlayer.Backpack:GetChildren()) do
--         if child.abilitySlot.Value == "q" then v4 = child break end
--     end
--     v4.localEvent:Fire(); abilityUsed:FireServer("q", v4)
--
-- NEN CACH CU CUA EM LA SAI HUONG: em bam theo SO BO (1/2) lay tu remote
-- `abilitySetSwapped`. Neu remote do khong ton tai / khong ban ve thi so bo
-- dung im -> macro tuong minh dang o bo sai -> Swap lien tuc -> khong bao gio
-- ban duoc skill. Dung y "swap van khong sai duoc".
-- Nay bam theo TEN TOOL dang nam o slot do - doc truc tiep tu Backpack, luon
-- dung, khong phu thuoc remote nao ban ve hay khong.
local lanSwap = 0

-- Ten tool dang giu slot nay (vd "Water Orb"). Dung de biet dang o bo nao.
local function tenToolO(slot)
    local t = toolSkill(slot)
    return t and t.Name or nil
end

local function banSwap()
    local r = remote("swapAbilitySet")
    if not r then return false end
    if os.clock() - lanSwap < 0.55 then return false end   -- debounce 0.5s cua game
    if not pcall(function() r:FireServer() end) then return false end
    lanSwap = os.clock()
    return true
end

-- F va nut Swap la CUNG mot hanh dong (Ui/inventory.lua:1395).
local banF = banSwap
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
local ketNoiCooldown = {}
local CACH_GHI = "?"     -- hien len GUI de biet dang ghi bang duong nao

local function ghiSuKien(loai, args)
    if not M.dangGhi then return end
    -- chong ghi trung: hai lop bat cung mot hanh dong trong cung mot nhip
    local cuoi = macro.sukien[#macro.sukien]
    local bayGio = os.clock() - batDauLuc
    if cuoi and cuoi.loai == loai and bayGio - cuoi.t < 0.12 then return end
    -- Ghi kem TEN TOOL dang nam o slot do. Nho no ma luc chay lai biet skill
    -- nay thuoc bo nao: neu slot dang giu tool ten khac thi phai Swap truoc.
    local ten = nil
    if loai == "q" or loai == "e" then ten = tenToolO(loai) end
    macro.sukien[#macro.sukien + 1] =
        { t = bayGio, loai = loai, args = args, ten = ten }
end

-- Chi giu tham so JSON luu duoc. Instance / userdata thi bo (luc phat lai tu
-- tim tool theo slot, khong can Instance cu).
local function locThamSo(...)
    local ra, n = {}, select("#", ...)
    for i = 1, n do
        local v = select(i, ...)
        local kieu = type(v)
        if kieu == "string" or kieu == "number" or kieu == "boolean" then
            ra[#ra + 1] = v
        end
    end
    return ra
end

-- LOP 1 DA BI GO BO. (chong: "tren dien thoai an sai skill tren man hinh ma
-- khong sai duoc luon")
-- Truoc day lop nay hook `__namecall` cua game de bat FireServer. Sai lam nang:
--     local cu
--     cu = hookmetamethod(game, "__namecall", function(self, ...)
--         ...
--         return cu(self, ...)    -- `cu` con la NIL neu hook chay truoc khi gan xong
--     end)
-- Hook co hieu luc NGAY khi cai, con phep gan `cu` thi xong SAU do. Game goi
-- __namecall hang nghin lan moi giay nen gan nhu chac chan roi vao khe do:
-- `cu` = nil -> hook nem loi -> MOI lenh remote cua game chet theo -> bam skill
-- khong an gi nua.
-- Ngoai ra hook chen vao TOAN BO game chu khong rieng macro, va khong go lai
-- duoc. Rui ro qua lon so voi cai duoc, nen BO HAN. CAM them lai.

-- LOP 1 MOI (an toan, chay ca PC lan DIEN THOAI): chi NGHE nut GUI cua game.
-- Khac hook o cho: khong chen vao luong lenh cua game, chi dang ky lang nghe
-- them -> khong the lam hong viec bam skill.
local function batDauNgheNut()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return end
    local function nghe(v)
        if not v:IsA("GuiButton") then return end
        ketNoiCooldown[#ketNoiCooldown + 1] = v.Activated:Connect(function()
            if not M.dangGhi then return end
            -- Ten nut lay tu source: abilities.lua:73 dung `abilities.Swap`.
            -- Hai nut skill la ImageButton con cua slot_Q / slot_E (abilities.lua
            -- :276,294) nen bat theo ca ten cha.
            local ten = string.lower(v.Name)
            local cha = v.Parent and string.lower(v.Parent.Name) or ""
            if ten == "swap" then
                ghiSuKien("swap")
            elseif ten == "q" or cha:find("slot_q") then
                ghiSuKien("q")
            elseif ten == "e" or cha:find("slot_e") then
                ghiSuKien("e")
            end
        end)
    end
    for _, v in ipairs(pg:GetDescendants()) do nghe(v) end
    ketNoiCooldown[#ketNoiCooldown + 1] = pg.DescendantAdded:Connect(nghe)
end

-- LOP 2 (du phong cho dien thoai khi executor khong cho hook): cooldown cua tool
-- nhay tu 0 len > 0 nghia la skill do VUA duoc dung, bat ke bam bang gi.
local function batDauTheoCooldown()
    for _, slot in ipairs({ "q", "e" }) do   -- source chi co hai slot nay
        local tool = toolSkill(slot)
        local cd = tool and tool:FindFirstChild("cooldown")
        if cd and cd:IsA("ValueBase") then
            local truoc = tonumber(cd.Value) or 0
            ketNoiCooldown[#ketNoiCooldown + 1] =
                cd:GetPropertyChangedSignal("Value"):Connect(function()
                    local nay = tonumber(cd.Value) or 0
                    if truoc <= 0.01 and nay > 0.01 then ghiSuKien(slot) end
                    truoc = nay
                end)
        end
    end
end

function M.batGhi()
    if M.dangChay then return end
    macro = { khung = {}, sukien = {} }
    batDauLuc = os.clock()
    M.dangGhi = true

    -- Khong con hook. Hai lop duoi day deu chi LANG NGHE, khong dung gi vao
    -- luong lenh cua game.
    CACH_GHI = "an toan"
    batDauTheoCooldown()
    batDauNgheNut()

    -- LOP 3: ban phim, CHI co tac dung tren PC. Van giu de neu hook hong thi
    -- tren may tinh khong mat gi. Tren dien thoai lop nay khong bao gio chay.
    ketNoiInput = UIS.InputBegan:Connect(function(input, guiBatDuoc)
        if not M.dangGhi then return end
        if input.KeyCode == Enum.KeyCode.Space then
            ghiSuKien("nhay")   -- nhay thi ghi ca khi GUI an phim
            return
        end
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
    for _, c in ipairs(ketNoiCooldown) do pcall(function() c:Disconnect() end) end
    ketNoiCooldown = {}
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

-- CHAY LAI MACRO. Chong chot: "lam macro thi dung quan tam den thoi gian,
-- chay luc nao cung duoc khac thoi gian, nhung mien dieu khien no lam dung
-- nhung gi macro lam la duoc".
-- => Vong chay KHONG con dinh gi den dong ho. Khong tua theo thoi gian, khong
--    cho cho dung nhip luc record, khong co tran thoi gian cat ngang.
--    No chi lam hai viec, lam xong moi buoc tiep:
--      1. Di TOI dung khung do (khong toi thi cu di tiep, khong bo qua som).
--      2. Ban DU nhung nut da ghi o khung do. Skill dang hoi chieu thi CHO
--         hoi xong roi ban, chu khong bo mat.
--    Chet giua chung thi cho hoi sinh roi chay tiep tu dung khung dang do.
-- Hai moc gio duy nhat con lai chi de CHONG TREO vinh vien, khong phai de
-- bam nhip: khung khong tai nao toi duoc, va nut khong tai nao ban duoc.
local NGUONG_TOI    = 6    -- studs: coi nhu da toi khung do
local HET_GIO_KHUNG = 30   -- giay: chiu thua mot khung khong toi duoc
local HET_GIO_NUT   = 20   -- giay: chiu thua mot nut khong ban duoc

function M.chay()
    if M.dangGhi or M.dangChay then return end
    if #macro.khung == 0 then return end
    M.dangChay = true
    M.boQua, M.nutHut, M.lyDoDung = 0, 0, nil
    task.spawn(function()
        local h0 = hum()
        if h0 then h0.AutoRotate = true end
        local iKhung, iSuKien = 1, 1
        local khungTu, nutTu = os.clock(), os.clock()

        -- Ban cac nut thuoc khung dang bam. Tra ve true khi da ban HET.
        -- Nut nao chua ban duoc (skill dang hoi chieu, chua cam vu khi) thi
        -- giu nguyen cho, vong sau thu lai - khong bo mat.
        local function thuBanNut(h, tMacro)
            while iSuKien <= #macro.sukien and macro.sukien[iSuKien].t <= tMacro do
                local s = macro.sukien[iSuKien]
                local xong
                -- Skill nay duoc ghi o bo khac voi bo dang dung -> Swap cho khop
                -- roi hay ban. Nho vay lech mot nhip Swap khong lam sai het phan
                -- con lai cua macro.
                -- Slot nay dang giu tool KHAC voi luc record -> dang o bo kia.
                -- Swap cho khop roi hay ban. So bang TEN TOOL doc truc tiep tu
                -- Backpack nen luon dung, khong can biet so bo.
                if s.ten and (s.loai == "q" or s.loai == "e") then
                    local dangCo = tenToolO(s.loai)
                    if dangCo and dangCo ~= s.ten then
                        banSwap()
                        return false
                    end
                end
                if s.loai == "danh" then
                    xong = chemTay()
                elseif s.loai == "q" then
                    xong = banSkill("q")
                elseif s.loai == "e" then
                    xong = banSkill("e")
                elseif s.loai == "f" then
                    xong = banF()   -- macro cu co the con ghi loai "f": F = Swap
                elseif s.loai == "swap" then
                    xong = banSwap()
                elseif s.loai == "nhay" then
                    if h then h.Jump = true end
                    xong = true
                else
                    xong = true
                end
                if not xong then
                    if os.clock() - nutTu > HET_GIO_NUT then
                        M.nutHut = (M.nutHut or 0) + 1
                        iSuKien = iSuKien + 1
                        nutTu = os.clock()
                    end
                    return false
                end
                iSuKien = iSuKien + 1
                nutTu = os.clock()
            end
            return true
        end

        while M.dangChay and iKhung <= #macro.khung do
            local h, r = hum(), hrp()
            if not h or not r or h.Health <= 0 then
                -- CHET giua macro: cho hoi sinh roi chay TIEP tu khung nay.
                M.tienDo = ("%d/%d cho hoi sinh"):format(iKhung, #macro.khung)
                task.wait(0.5)
                khungTu, nutTu = os.clock(), os.clock()
            else
                local viTri = r.Position
                local k = macro.khung[iKhung]
                local diemMoc = Vector3.new(k.x, k.y, k.z)
                local con = (diemMoc - viTri).Magnitude
                local daBanHet = thuBanNut(h, k.t)

                if con <= NGUONG_TOI and daBanHet then
                    -- Toi noi va lam xong viec o khung nay -> sang khung ke.
                    -- Khong cho them giay nao: thoi gian khong quan trong.
                    iKhung = iKhung + 1
                    khungTu = os.clock()
                elseif con > NGUONG_TOI and os.clock() - khungTu > HET_GIO_KHUNG then
                    M.boQua = (M.boQua or 0) + 1
                    iKhung = iKhung + 1
                    khungTu = os.clock()
                elseif con > NGUONG_TOI then
                    local iNgam, diemNgam = iKhung, diemMoc
                    while iNgam < #macro.khung
                        and (diemNgam - viTri).Magnitude < NHIN_TRUOC do
                        iNgam = iNgam + 1
                        local kn = macro.khung[iNgam]
                        diemNgam = Vector3.new(kn.x, kn.y, kn.z)
                    end
                    h:MoveTo(diemNgam)
                end

                M.tienDo = ("%d/%d"):format(iKhung, #macro.khung)
            end
            task.wait(0.05)
        end

        -- Ban not nhung nut con sot sau khung cuoi, van cho neu dang hoi chieu.
        local choNot = os.clock()
        while M.dangChay and iSuKien <= #macro.sukien
            and os.clock() - choNot < HET_GIO_NUT do
            if thuBanNut(hum(), math.huge) then break end
            task.wait(0.1)
        end

        M.lyDoDung = M.dangChay and "xong" or "chong bam dung"
        M.dangChay = false
        M.tienDo = nil
        if M.capNhatGui then M.capNhatGui() end
    end)
end

function M.dungChay()
    M.dangChay = false
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
    -- bo ky tu co the pha ten file
    ten = tostring(ten or ""):gsub("^%s+", ""):gsub("%s+$", "")
    ten = ten:gsub("[^%w%s_%-]", ""):gsub("%s+", "_")
    return ten
end

local function duongDan(ten)
    return ("macro_ai_%s.json"):format(ten)
end

local function luuDanhSach()
    if type(writefile) ~= "function" then return end
    pcall(function()
        writefile(TEP_DANHSACH, HttpService:JSONEncode(danhSach))
    end)
end

function M.napDanhSach()
    local d = docFile(TEP_DANHSACH)
    danhSach = (type(d) == "table") and d or {}
    -- macro cu tu ban dau: gom vao danh sach cho khoi mat
    if type(isfile) == "function" and isfile(TEP_CU) then
        local coRoi = false
        for _, t in ipairs(danhSach) do
            if t == "macro_cu" then coRoi = true break end
        end
        if not coRoi then
            danhSach[#danhSach + 1] = "macro_cu"
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
    local ok = pcall(function()
        writefile(duongDan(ten), HttpService:JSONEncode(macro))
    end)
    if not ok then return false, "ghi file loi" end
    local coRoi = false
    for _, t in ipairs(danhSach) do
        if t == ten then coRoi = true break end
    end
    if not coRoi then
        danhSach[#danhSach + 1] = ten
        luuDanhSach()
    end
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
    macro = { khung = data.khung, sukien = data.sukien or {} }
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
        if danhSach[i] == ten then table.remove(danhSach, i) end
    end
    luuDanhSach()
    if tenDangChon == ten then tenDangChon = nil end
    return true
end

--== GUI =======================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "MacroAI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = (gethui and gethui()) or LP:WaitForChild("PlayerGui")

local bang = Instance.new("Frame")
bang.Size = UDim2.new(0, 230, 0, 428)
bang.Position = UDim2.new(0, 20, 0.5, -214)
bang.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
bang.BorderSizePixel = 0
bang.Active = true
bang.Draggable = true
bang.Parent = gui
Instance.new("UICorner", bang).CornerRadius = UDim.new(0, 8)

local tieuDe = Instance.new("TextLabel")
tieuDe.Size = UDim2.new(1, 0, 0, 26)
tieuDe.BackgroundTransparency = 1
tieuDe.Text = "MACRO AI"
tieuDe.TextColor3 = Color3.fromRGB(235, 240, 250)
tieuDe.Font = Enum.Font.GothamBold
tieuDe.TextSize = 14
tieuDe.Parent = bang

local trangThai = Instance.new("TextLabel")
trangThai.Size = UDim2.new(1, -16, 0, 32)
trangThai.Position = UDim2.new(0, 8, 0, 26)
trangThai.BackgroundColor3 = Color3.fromRGB(18, 19, 25)
trangThai.Text = "san sang"
trangThai.TextColor3 = Color3.fromRGB(150, 200, 255)
trangThai.Font = Enum.Font.Gotham
trangThai.TextSize = 11
trangThai.TextWrapped = true
trangThai.Parent = bang
Instance.new("UICorner", trangThai).CornerRadius = UDim.new(0, 6)

local oTen = Instance.new("TextBox")
oTen.Size = UDim2.new(1, -16, 0, 26)
oTen.Position = UDim2.new(0, 8, 0, 62)
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
    b.TextSize = 12
    b.AutoButtonColor = true
    b.Parent = bang
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(chay)
    return b
end

local danhSachKhung = Instance.new("ScrollingFrame")
danhSachKhung.Size = UDim2.new(1, -16, 0, 132)
danhSachKhung.Position = UDim2.new(0, 8, 0, 158)
danhSachKhung.BackgroundColor3 = Color3.fromRGB(18, 19, 25)
danhSachKhung.BorderSizePixel = 0
danhSachKhung.ScrollBarThickness = 4
danhSachKhung.CanvasSize = UDim2.new(0, 0, 0, 0)
danhSachKhung.Parent = bang
Instance.new("UICorner", danhSachKhung).CornerRadius = UDim.new(0, 6)

local xepDoc = Instance.new("UIListLayout")
xepDoc.Padding = UDim.new(0, 2)
xepDoc.Parent = danhSachKhung

local nutGhi, nutChay, nutAutoStart, nutAutoReplay

function M.veDanhSach()
    for _, c in ipairs(danhSachKhung:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    for _, ten in ipairs(danhSach) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -8, 0, 24)
        b.BackgroundColor3 = (ten == tenDangChon)
            and Color3.fromRGB(45, 100, 160) or Color3.fromRGB(38, 41, 52)
        b.Text = (ten == tenDangChon and "> " or "   ") .. ten
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.TextColor3 = Color3.fromRGB(235, 238, 245)
        b.Font = Enum.Font.Gotham
        b.TextSize = 11
        b.Parent = danhSachKhung
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
        b.MouseButton1Click:Connect(function()
            local ok, vi = M.napTen(ten)
            oTen.Text = ten
            trangThai.Text = ok
                and ("chon [%s]  %d khung / %d nut"):format(ten, #macro.khung, #macro.sukien)
                or ("khong nap duoc: " .. tostring(vi))
            M.veDanhSach()
        end)
    end
    danhSachKhung.CanvasSize = UDim2.new(0, 0, 0, #danhSach * 26 + 4)
end

function M.capNhatGui()
    if M.dangGhi then
        trangThai.Text = ("DANG GHI (%s)  %d khung / %d nut"):format(
            CACH_GHI, #macro.khung, #macro.sukien)
        trangThai.TextColor3 = Color3.fromRGB(255, 140, 140)
        nutGhi.Text = "DUNG GHI"
    elseif M.dangChay then
        trangThai.Text = ("DANG CHAY [%s]  %s%s"):format(
            tenDangChon or "chua luu", M.tienDo or ("0/" .. #macro.khung),
            ((M.boQua or 0) > 0 or (M.nutHut or 0) > 0)
                and ("  bo qua %d khung / %d nut"):format(M.boQua or 0, M.nutHut or 0)
                or "")
        trangThai.TextColor3 = Color3.fromRGB(140, 255, 170)
        nutGhi.Text = "GHI MACRO"
    else
        trangThai.Text = ("[%s]  %d khung / %d nut%s"):format(
            tenDangChon or "chua luu", #macro.khung, #macro.sukien,
            M.lyDoDung and ("  (" .. M.lyDoDung .. ")") or "")
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

nutGhi = taoNut("GHI MACRO", 8, 96, 104, Color3.fromRGB(150, 60, 60), function()
    if M.dangGhi then M.dungGhiLai() else M.batGhi() end
    M.capNhatGui()
end)

nutChay = taoNut("CHAY MACRO", 118, 96, 104, Color3.fromRGB(45, 100, 160), function()
    if M.dangChay then M.dungChay() else M.chay() end
    M.capNhatGui()
end)

taoNut("LUU THANH TEN", 8, 126, 140, Color3.fromRGB(60, 70, 95), function()
    local ok, vi = M.luuTen(oTen.Text)
    trangThai.Text = ok and ("da luu [%s]"):format(tenSach(oTen.Text))
        or ("luu that bai: " .. tostring(vi))
    M.veDanhSach()
end)

taoNut("XOA", 154, 126, 68, Color3.fromRGB(110, 50, 50), function()
    local ten = tenSach(oTen.Text)
    if ten == "" then
        trangThai.Text = "go ten can xoa vao o tren"
        return
    end
    M.xoaTen(ten)
    trangThai.Text = ("da xoa [%s]"):format(ten)
    M.veDanhSach()
end)

nutAutoStart = taoNut("Auto Start: BAT", 8, 300, 214, Color3.fromRGB(40, 110, 70), function()
    M.autoStart = not M.autoStart
    M.capNhatGui()
end)

nutAutoReplay = taoNut("Auto Replay: BAT", 8, 330, 214, Color3.fromRGB(40, 110, 70), function()
    M.autoReplay = not M.autoReplay
    M.capNhatGui()
end)

local ghiChu = Instance.new("TextLabel")
ghiChu.Size = UDim2.new(1, -16, 0, 56)
ghiChu.Position = UDim2.new(0, 8, 0, 362)
ghiChu.BackgroundTransparency = 1
ghiChu.Text = "Ghi: di chuyen + danh tay, Q, E, F, Swap, Space." .. XUONG_DONG .. "Chay duoc ca PC lan dien thoai (bam nut tren man hinh van ghi)." .. XUONG_DONG .. "Bam ten trong danh sach de chon macro."
ghiChu.TextColor3 = Color3.fromRGB(120, 128, 145)
ghiChu.Font = Enum.Font.Gotham
ghiChu.TextSize = 10
ghiChu.TextWrapped = true
ghiChu.TextYAlignment = Enum.TextYAlignment.Top
ghiChu.Parent = bang

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

M.napDanhSach()
M.veDanhSach()
M.capNhatGui()
print(("[MACRO AI] da bat, co %d macro da luu. Tat bang:  _G.__MACRO_AI__.tat()")
    :format(#danhSach))
