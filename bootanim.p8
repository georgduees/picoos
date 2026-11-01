pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
function _init()
    t = 0
    star_pixels = {
        {dx=2, dy=0, col=8,  col_dark=2},
        {dx=3, dy=1, col=15, col_dark=4},
        {dx=4, dy=2, col=14, col_dark=2},
        {dx=3, dy=3, col=13, col_dark=1},
        {dx=2, dy=4, col=12, col_dark=1},
        {dx=1, dy=3, col=11, col_dark=3},
        {dx=0, dy=2, col=10, col_dark=9},
        {dx=1, dy=1, col=9,  col_dark=4}
    }
end

function _update()
    t += 1
end

function _draw()
    cls(0)

    local spr_w = 35
    local spr_h = 5
    local scale = 2
    local dw = spr_w * scale
    local dh = spr_h * scale
    local dx = 36
    local dy = 59

    local progress = min(1, t / 36)
    local cur_w = flr(spr_w * progress)

    if cur_w > 0 then
        sspr(8, 0, cur_w, spr_h, dx, dy, cur_w * scale, dh)
    end

    if t >= 40 then
        local sx = dx + dw - 10
        local sy = dy - 8

        rectfill(sx + 4, sy + 2, sx + 5, sy + 7, 7)
        rectfill(sx + 2, sy + 4, sx + 7, sy + 5, 7)
        rectfill(sx + 4, sy + 4, sx + 5, sy + 5, 7)

        local step = flr((t - 40) / 4) % #star_pixels + 1

        for i = 1, #star_pixels do
            local sp = star_pixels[i]
            local px = sx + sp.dx * 2
            local py = sy + sp.dy * 2

            local c = sp.col
            if i == step or i == (step % #star_pixels + 1) then
                c = sp.col_dark
            end

            rectfill(px, py, px + 1, py + 1, c)
        end
    end
end
__gfx__
00000000077770777700777007777000007777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000770770077007700077077000007007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700777770077007700077077077077777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000770000077007700077077000077007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000770000777707777077770000077777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
