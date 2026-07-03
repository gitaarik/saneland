-- Yazi init.lua - UI customizations
-- https://yazi-rs.github.io/docs/configuration/overview

-- Show full absolute path in header instead of shortened path (~ for home)
function Header:cwd()
    local max = self._area.w - self._right_width
    if max <= 0 then
        return ""
    end
    -- Use tostring() directly instead of ya.readable_path() for full path
    local s = tostring(self._current.cwd) .. self:flags()
    return ui.Span(ui.truncate(s, { max = max, rtl = true })):style(th.mgr.cwd)
end
