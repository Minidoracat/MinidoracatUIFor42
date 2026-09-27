-- MinidoracatUI Widgets/Window — 現代視窗與模態對話框（API rev 7）：Window／Dialog。
--
-- Window 取代 ISCollapsableWindow 的外觀：surface 圓角本體＋roundTop 標題列、標題列拖曳
-- （setCapture 五件套，同 FloatButton）、可選右下角縮放把手、關閉鈕；每幀 clamp 回螢幕。
-- 相容原版 ISLayoutManager.RegisterWindow(name, Class, instance)：存讀回呼在第二參數，
-- 以 funcs.SaveLayout/RestoreLayout(target, name, layout) 呼叫（ISLayoutManager.lua:6-13,99-113），
-- 所以 Window 的同名方法即可直接當 funcs 傳入。
--
-- rev 10：Window 是 Focus 的 root（MinidoracatUI/Focus.lua）——鍵盤 Tab／方向鍵／Enter 與手把
-- 方向鍵／A／B／LB／RB 操作視窗內的框架控制項；預設目標依閱讀順序自動找（keyboardTargets 可覆寫）。
-- 顯示時若玩家正用手把就接手手把焦點，隱藏時還原原本的焦點。
--
-- Dialog 取代 ISModalDialog：全螢幕吃滑鼠的 guard＋置中 Window；結果回呼只呼叫一次。
-- Enter／Esc 走原生 key 事件（setWantKeyEvents＋isKeyConsumed/onKeyRelease，同原版
-- ISBuildWindow.lua:16-21,355；UIElement.java:2174-2217），不 monkeypatch。手把 A＝焦點下的按鈕
-- （預設「確認」）、B＝取消。
--
-- 載入順序：Dialog 依賴 Controls 的 Button／TextField——本檔開頭自行 pcall require，
-- 不靠檔名排序。Controls 缺席時 Window 照常提供，只有 CAPABILITIES.dialog 維持 false；
-- Focus 缺席時 Window／Dialog 照常，只是沒有鍵盤導覽與手把。

if not (MinidoracatUI and MinidoracatUI.v1) then
    pcall(require, "MinidoracatUI/V1")
end

local UI = MinidoracatUI and MinidoracatUI.v1
if not (UI and UI.API_MAJOR == 1 and UI.Skin and UI.Theme and UI.Icons) or not ISPanel then
    return -- 核心缺席：不掛能力（consumer 以 CAPABILITIES.window／dialog 探測）
end

if not (UI.Button and UI.TextField) then
    pcall(require, "MinidoracatUI/Widgets/Controls")
end
if not UI.Focus then
    pcall(require, "MinidoracatUI/Focus")
end
local Focus = UI.Focus

local Skin = UI.Skin
local Icons = UI.Icons

local DEFAULT_MIN_WIDTH = 240
local DEFAULT_MIN_HEIGHT = 160
local CLOSE_ICON = 14
local GRIP_SIZE = 12
local TITLE_PAD = 8
local TITLE_ICON = 16

-- ============================================================
-- Window
-- ============================================================

local Window = ISPanel:derive("MinidoracatUIWindow")

local function clampToScreen(win)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local x = math.max(0, math.min(win:getX(), sw - win.width))
    local y = math.max(0, math.min(win:getY(), sh - win.height))
    if x ~= win:getX() then win:setX(x) end
    if y ~= win:getY() then win:setY(y) end
end

local function closeRect(win)
    local size = win._titleH
    return win.width - size, 0, size, size
end

local function inClose(win, x, y)
    if not win.closable then
        return false
    end
    local cx, cy, cw, ch = closeRect(win)
    return x >= cx and x < cx + cw and y >= cy and y < cy + ch
end

local function inGrip(win, x, y)
    return win.resizable and x >= win.width - GRIP_SIZE and y >= win.height - GRIP_SIZE
end

-- 回 true＝尺寸有變（已呼叫 onResize）
local function applySize(win, width, height)
    width = math.max(win.minWidth, math.floor(width))
    height = math.max(win.minHeight, math.floor(height))
    if width == win.width and height == win.height then
        return false
    end
    win:setWidth(width)
    win:setHeight(height)
    if win.onResize then
        win.onResize(win, width, height)
    end
    return true
end

function Window:titleBarHeight()
    return self._titleH
end

function Window:contentTop()
    return self._titleH
end

function Window:setTitle(title)
    self.title = title or ""
end

function Window:prerender()
    if self.isCollapsed then
        return
    end
    clampToScreen(self)
    local colors = self.theme.colors
    local w, titleH = self.width, self._titleH
    Skin.fill(self, 0, 0, w, self.height, colors.surface)
    Skin.fill(self, 0, 0, w, titleH, colors.surfaceTitle, "roundTop")

    local x = TITLE_PAD
    local textColor = colors.text
    if self.icon and Icons.draw(self, self.icon, x, math.floor((titleH - TITLE_ICON) / 2),
            TITLE_ICON, textColor) then
        x = x + TITLE_ICON + 6
    end
    self:drawText(self.title, x, math.floor((titleH - self._fontH) / 2),
        textColor.r, textColor.g, textColor.b, textColor.a or 1, self.font)
end

-- 邊框、關閉鈕、縮放把手畫在 children 之後（UIElement.render：prerender → children → render）
function Window:render()
    if self.isCollapsed then
        return
    end
    local colors = self.theme.colors
    Skin.border(self, 0, 0, self.width, self.height, colors.border)

    if self.closable then
        local cx, cy, cw, ch = closeRect(self)
        local hovered = self:isMouseOver() and inClose(self, self:getMouseX(), self:getMouseY())
        if hovered then
            Skin.fill(self, cx + 3, cy + 3, cw - 6, ch - 6, colors.hover)
        end
        local c = hovered and colors.text or colors.textMuted
        if not Icons.draw(self, "close", cx + math.floor((cw - CLOSE_ICON) / 2),
                cy + math.floor((ch - CLOSE_ICON) / 2), CLOSE_ICON, c) then
            self:drawTextCentre("x", cx + cw / 2, cy + math.floor((ch - self._fontH) / 2),
                c.r, c.g, c.b, c.a or 1, self.font)
        end
    end

    if self.resizable then
        -- 右下角三角點陣把手（2x2 點，零配置）
        local c = colors.textFaint
        for row = 0, 2 do
            for col = 0, row do
                self:drawRect(self.width - 5 - col * 4, self.height - 13 + row * 4, 2, 2,
                    c.a or 1, c.r, c.g, c.b)
            end
        end
    end
    if Focus then
        Focus.render(self, self.theme) -- 子元件之後畫：焦點框蓋在它標示的控制項上
    end
end

-- ===== 拖曳／縮放（setCapture 五件套：拖出視窗外仍收 Move/Up）=====

function Window:onMouseDown(x, y)
    if not self:getIsVisible() then
        return false
    end
    self:bringToTop()
    if inClose(self, x, y) then
        self._closeDown = true
        return true
    end
    local mode = nil
    if inGrip(self, x, y) then
        mode = "resize"
    elseif y < self._titleH then
        mode = "move"
    end
    if mode then
        self._drag = mode
        self._downX, self._downY = getMouseX(), getMouseY()
        self._origX, self._origY = self:getX(), self:getY()
        self._origW, self._origH = self.width, self.height
        self:setCapture(true)
    end
    return true
end

local function dragWindow(win)
    local mode = win._drag
    if not mode then
        return false
    end
    local dx, dy = getMouseX() - win._downX, getMouseY() - win._downY
    if mode == "move" then
        win:setX(win._origX + dx)
        win:setY(win._origY + dy)
    else
        applySize(win, win._origW + dx, win._origH + dy)
    end
    return true
end

local function releaseWindow(win, x, y, inside)
    local closeDown = win._closeDown
    win._closeDown = nil
    if win._drag then
        win._drag = nil
        win:setCapture(false)
        clampToScreen(win)
        return true
    end
    if closeDown and inside and inClose(win, x, y) then
        win:close()
    end
    return true
end

function Window:onMouseMove(dx, dy) dragWindow(self) return true end
function Window:onMouseMoveOutside(dx, dy) return dragWindow(self) end
function Window:onMouseUp(x, y) return releaseWindow(self, x, y, true) end
function Window:onMouseUpOutside(x, y) return releaseWindow(self, x, y, false) end

function Window:close()
    if self._drag then
        self._drag = nil
        self:setCapture(false)
    end
    self:setVisible(false)
    if self.onClose then
        self.onClose(self)
    end
end

-- ===== 焦點（rev 10）：Window 是 Focus 的 root =====

-- 預設目標：視窗內可見的框架控制項，依閱讀順序（consumer 可在實例上覆寫 keyboardTargets）
function Window:keyboardTargets()
    return Focus and Focus.collectTargets(self) or nil
end

function Window:onKeyPress(key) if Focus then Focus.onKeyPress(self, key) end end
function Window:onKeyRepeat(key) if Focus then Focus.onKeyRepeat(self, key) end end
function Window:onKeyRelease(key) if Focus then Focus.onKeyRelease(self, key) end end
function Window:isKeyConsumed(key) return Focus ~= nil and Focus.isKeyConsumed(self, key) end
function Window:onFocus() if Focus then Focus.onFocus(self) end end

function Window:onJoypadDown(button, joypadData) if Focus then Focus.onJoypadDown(self, button, joypadData) end end
function Window:onJoypadDirUp(joypadData) if Focus then Focus.onJoypadDir(self, "up", joypadData) end end
function Window:onJoypadDirDown(joypadData) if Focus then Focus.onJoypadDir(self, "down", joypadData) end end
function Window:onJoypadDirLeft(joypadData) if Focus then Focus.onJoypadDir(self, "left", joypadData) end end
function Window:onJoypadDirRight(joypadData) if Focus then Focus.onJoypadDir(self, "right", joypadData) end end

-- 手把斷線（JoyPadSetup.lua onJoypadBeforeDeactivate 轉給目前焦點）：還原焦點、收掉焦點框
function Window:onJoypadBeforeDeactivate(joypadData)
    if Focus then
        Focus.releaseJoypad(self)
        Focus.clear(self)
    end
end

-- 手把 LB／RB：切換視窗內第一個分頁列
function Window:onFocusShoulder(delta)
    local list = self:keyboardTargets()
    if type(list) ~= "table" then return end
    for i = 1, #list do
        local c = list[i].control
        if type(c) == "table" and c.selectRelative then
            c:selectRelative(delta)
            return
        end
    end
end

-- 顯示／加入 UIManager 時成為作用中的 root（下一次 Tab 屬於它），玩家用手把就接手手把焦點；
-- 隱藏時還原原本的手把焦點並收掉焦點框與輸入框的文字焦點
local function onShown(win)
    if Focus then
        Focus.onFocus(win)
        Focus.takeJoypad(win, 0)
    end
end

function Window:setVisible(visible)
    local was = self.javaObject ~= nil and self:getIsVisible()
    ISPanel.setVisible(self, visible)
    if was == (visible == true) then
        return
    end
    if visible then
        onShown(self)
    elseif Focus then
        Focus.releaseJoypad(self)
        Focus.clear(self)
    end
end

function Window:addToUIManager()
    ISPanel.addToUIManager(self)
    if self:getIsVisible() then
        onShown(self)
    end
end

-- ===== ISLayoutManager 相容（RegisterWindow(name, UI.Window, win)）=====

function Window:SaveLayout(name, layout)
    layout.x = self:getX()
    layout.y = self:getY()
    if self.resizable then
        layout.width = self.width
        layout.height = self.height
    end
end

function Window:RestoreLayout(name, layout)
    local x, y = tonumber(layout.x), tonumber(layout.y)
    if x and y then
        self:setX(x)
        self:setY(y)
    end
    local width, height = tonumber(layout.width), tonumber(layout.height)
    if self.resizable and width and height then
        applySize(self, width, height)
    end
    clampToScreen(self)
end

local function newWindow(class, opts)
    opts = opts or {}
    local font = opts.font or UIFont.Small
    local fontH = getTextManager():getFontHeight(font)
    local minWidth = opts.minWidth or DEFAULT_MIN_WIDTH
    local minHeight = opts.minHeight or DEFAULT_MIN_HEIGHT
    local resizable = opts.resizable == true
    local width, height = opts.width or minWidth, opts.height or minHeight
    if resizable then
        width, height = math.max(minWidth, width), math.max(minHeight, height)
    end
    local o = ISPanel.new(class, opts.x or 0, opts.y or 0, width, height)
    o.background = false
    o.moveWithMouse = false
    o.theme = opts.theme or UI.Theme.create()
    o.font = font
    o.title = opts.title or ""
    o.icon = opts.icon
    o.resizable = resizable
    o.minWidth = minWidth
    o.minHeight = minHeight
    o.closable = opts.closable ~= false
    o.onClose = opts.onClose
    o.onResize = opts.onResize
    o._fontH = fontH
    o._titleH = math.max(24, fontH + 10)
    if Focus then
        o:setWantKeyEvents(true) -- 只有 top-level 會收到 key 事件（UIManager.java:1435-1466）
    end
    o:initialise()
    return o
end

-- opts: x, y, width, height, title, icon?, theme?, font?, resizable?, minWidth?, minHeight?,
--       closable?（預設 true）, onClose(win)?, onResize(win, w, h)?
-- 回傳已 initialise 的實例；consumer 自行 addToUIManager。
function Window.new(opts)
    return newWindow(Window, opts)
end

UI.Window = Window
UI.CAPABILITIES.window = true

-- ============================================================
-- Dialog
-- ============================================================

local Button, TextField = UI.Button, UI.TextField
if not (Button and TextField) then
    return Window -- Controls 缺席：只提供 Window，dialog 能力維持 false
end

local DIALOG_WIDTH = 360
local DIALOG_PAD = 12
local BUTTON_MIN_WIDTH = 80
local BUTTON_GAP = 8
local MAX_WRAP_UNITS = 4096
local GUARD_COLOR = { r = 0, g = 0, b = 0, a = 0.5 }

local KEY_ESCAPE = Keyboard and Keyboard.KEY_ESCAPE or 1
local KEY_ENTER = Keyboard and Keyboard.KEY_RETURN or 28
local KEY_NUMPAD_ENTER = Keyboard and Keyboard.KEY_NUMPADENTER or 156

local Dialog = {}
local current = nil

-- 全螢幕 guard：吃掉所有滑鼠事件、半透明黑底
local Guard = ISPanel:derive("MinidoracatUIDialogGuard")

function Guard:prerender()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    if self.width ~= sw or self.height ~= sh then
        self:setWidth(sw)
        self:setHeight(sh)
    end
    self:drawRect(0, 0, sw, sh, GUARD_COLOR.a, GUARD_COLOR.r, GUARD_COLOR.g, GUARD_COLOR.b)
end

function Guard:render() end
function Guard:onMouseDown() return true end
function Guard:onMouseUp() return true end
function Guard:onRightMouseDown() return true end
function Guard:onRightMouseUp() return true end
function Guard:onMouseMove() return true end
function Guard:onMouseWheel() return true end

-- 內文：多行文字（建構時換行，prerender 只畫）
local Body = ISPanel:derive("MinidoracatUIDialogBody")

function Body:prerender()
    if self.isCollapsed then
        return
    end
    local c = self.color
    local lines = self.lines
    for i = 1, #lines do
        self:drawText(lines[i], 0, (i - 1) * self.lineHeight, c.r, c.g, c.b, c.a or 1, self.font)
    end
end

local function isHighSurrogate(unit)
    return unit ~= nil and unit >= 55296 and unit <= 56319
end

-- 單段換行：每行二分找最長可放前綴（CJK 無空白按字元切；拉丁文退到最後一個空白），
-- 量測次數 O(lines × log n)。截點落在 surrogate pair 中間時回退一位。
local function wrapParagraph(lines, text, maxWidth, font)
    local manager = getTextManager()
    local rest = text
    while rest ~= "" do
        if manager:MeasureStringX(font, rest) <= maxWidth then
            lines[#lines + 1] = rest
            return
        end
        local low, high, best = 1, string.len(rest), 1
        while low <= high do
            local mid = math.floor((low + high) / 2)
            local cut = mid
            if isHighSurrogate(string.byte(rest, cut)) then cut = cut - 1 end
            if cut >= 1 and manager:MeasureStringX(font, string.sub(rest, 1, cut)) <= maxWidth then
                best = cut
                low = mid + 1
            else
                high = mid - 1
            end
        end
        local head = string.sub(rest, 1, best)
        for i = string.len(head), 2, -1 do
            if string.byte(head, i) == 32 then
                head = string.sub(head, 1, i - 1)
                break
            end
        end
        lines[#lines + 1] = head
        rest = string.gsub(string.sub(rest, string.len(head) + 1), "^%s+", "")
    end
end

local function wrapText(text, maxWidth, font)
    local lines = {}
    text = string.sub(text or "", 1, MAX_WRAP_UNITS)
    local start = 1
    while true do
        local nl = string.find(text, "\n", start, true)
        local paragraph = nl and string.sub(text, start, nl - 1) or string.sub(text, start)
        if paragraph == "" then
            lines[#lines + 1] = ""
        else
            wrapParagraph(lines, paragraph, maxWidth, font)
        end
        if not nl then
            break
        end
        start = nl + 1
    end
    return lines
end

-- 唯一收尾路徑：按鈕、關閉鈕、Enter/Esc、Dialog.close 全走這裡；_done 保證只回呼一次
local function finish(dialog, ok)
    if dialog._done then
        return
    end
    dialog._done = true
    if current == dialog then
        current = nil
    end
    local text = nil
    if dialog._input then
        text = dialog._input:getText()
        dialog._input._entry:unfocus()
    end
    dialog:setVisible(false)
    dialog._guard:setVisible(false)
    dialog._guard:removeFromUIManager()
    dialog:removeFromUIManager()
    if dialog._onResult then
        dialog._onResult(ok, text)
    end
end

local DialogWindow = Window:derive("MinidoracatUIDialog")

-- 按下與放開配對才算：避免「consumer 在 Enter 按下時開窗、放開瞬間就被確認」。
-- 其他鍵交給 Focus（Tab 在按鈕與輸入框之間走）。
function DialogWindow:onKeyPress(key)
    if key == KEY_ESCAPE then
        self._escDown = true
    elseif key == KEY_ENTER or key == KEY_NUMPAD_ENTER then
        self._enterDown = true
    elseif Focus then
        Focus.onKeyPress(self, key)
    end
end

function DialogWindow:onKeyRelease(key)
    if key == KEY_ESCAPE and self._escDown then
        finish(self, false)
    elseif (key == KEY_ENTER or key == KEY_NUMPAD_ENTER) and self._enterDown then
        -- 焦點框在某顆按鈕上（例如 Tab 到「取消」）時 Enter 按那一顆；沒有焦點框＝確認
        local c = Focus and Focus.root == self and Focus.focused() or nil
        if c ~= nil and c ~= self._confirm and Focus.isKeyboardFocused(c) and c.forceClick then
            c:forceClick()
        else
            finish(self, true)
        end
    elseif Focus then
        Focus.onKeyRelease(self, key)
    end
end

-- 關閉後仍須消耗同一個 key（UIElement.java:2211-2213 先 onKeyRelease 再 isKeyConsumed），
-- 否則同一個 Esc 會再關掉後面的視窗——不看 visible
function DialogWindow:isKeyConsumed(key)
    if key == KEY_ESCAPE or key == KEY_ENTER or key == KEY_NUMPAD_ENTER then
        return true
    end
    return Focus ~= nil and Focus.isKeyConsumed(self, key)
end

function Dialog.close(dialog, ok)
    if dialog then
        finish(dialog, ok == true)
    end
end

-- opts: title, text, confirmText, cancelText?, danger?, input={text?,placeholder?,onlyNumbers?}?,
--       width?, theme?, font?, onResult(ok, inputText)?
-- 回傳 dialog（Window 實例，已 addToUIManager）。同時只允許一個：新開先以 cancel 關掉舊的。
function Dialog.show(opts)
    opts = opts or {}
    if current then
        finish(current, false)
    end
    local theme = opts.theme or UI.Theme.create()
    local font = opts.font or UIFont.Small
    local fontH = getTextManager():getFontHeight(font)
    local width = opts.width or DIALOG_WIDTH
    local innerW = width - DIALOG_PAD * 2
    local lines = wrapText(opts.text, innerW, font)
    local buttonH = fontH + 10
    local titleH = math.max(24, fontH + 10)

    local height = titleH + DIALOG_PAD + #lines * fontH + DIALOG_PAD + buttonH + DIALOG_PAD
    local inputH = fontH + 10
    if opts.input then
        height = height + inputH + DIALOG_PAD
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()

    local dialog
    dialog = newWindow(DialogWindow, {
        x = math.floor((sw - width) / 2), y = math.floor((sh - height) / 2),
        width = width, height = height,
        title = opts.title, theme = theme, font = font, closable = true,
        onClose = function() finish(dialog, false) end,
    })
    dialog._onResult = opts.onResult
    dialog:setWantKeyEvents(true)

    local body = ISPanel.new(Body, DIALOG_PAD, titleH + DIALOG_PAD, innerW, #lines * fontH)
    body.background = false
    body.lines = lines
    body.lineHeight = fontH
    body.font = font
    body.color = theme.colors.text
    body:initialise()
    dialog:addChild(body)

    local y = titleH + DIALOG_PAD + #lines * fontH + DIALOG_PAD
    if opts.input then
        local input = TextField.new{
            x = DIALOG_PAD, y = y, width = innerW, height = inputH,
            text = opts.input.text, placeholder = opts.input.placeholder,
            onlyNumbers = opts.input.onlyNumbers, theme = theme, font = font,
        }
        -- 焦點在輸入框時 key 事件不進 UIManager（GameKeyboard.java:32-43），Enter 改由原生
        -- onCommandEntered 送出（UITextBox2.java:841-845）
        input._entry.onCommandEntered = function() finish(dialog, true) end
        dialog:addChild(input)
        dialog._input = input
        y = y + inputH + DIALOG_PAD
    end

    local right = width - DIALOG_PAD
    local confirm = Button.new{
        x = 0, y = y, height = buttonH, title = opts.confirmText or "OK",
        style = opts.danger and "danger" or "primary", theme = theme, font = font,
        onClick = function() finish(dialog, true) end,
    }
    confirm:setWidth(math.max(BUTTON_MIN_WIDTH, confirm.width))
    confirm:setX(right - confirm.width)
    dialog:addChild(confirm)
    dialog._confirm = confirm
    right = right - confirm.width - BUTTON_GAP
    if opts.cancelText then
        local cancel = Button.new{
            x = 0, y = y, height = buttonH, title = opts.cancelText,
            style = "normal", theme = theme, font = font,
            onClick = function() finish(dialog, false) end,
        }
        cancel:setWidth(math.max(BUTTON_MIN_WIDTH, cancel.width))
        cancel:setX(right - cancel.width)
        dialog:addChild(cancel)
        dialog._cancel = cancel
    end

    local guard = ISPanel.new(Guard, 0, 0, sw, sh)
    guard.background = false
    guard:initialise()
    dialog._guard = guard

    -- 置頂層級：guard 與視窗都是 alwaysOnTop，UIManager 依加入順序穩定排序（UIManager.java:544-556），
    -- 視窗後加所以在 guard 之上；setter 必須在實例化（addToUIManager）後呼叫
    guard:addToUIManager()
    guard:setAlwaysOnTop(true)
    dialog:addToUIManager()
    dialog:setAlwaysOnTop(true)
    current = dialog
    if dialog._input then
        dialog._input:focus()
    end
    -- 手把玩家（addToUIManager 已接手焦點）：焦點預設在「確認」，A＝確認、B＝取消
    if Focus and Focus.holdsJoypad(dialog) then
        Focus.focusControl(confirm, true)
    end
    return dialog
end

UI.Dialog = Dialog
UI.CAPABILITIES.dialog = true

return Window
