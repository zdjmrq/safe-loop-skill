// ============================================================
// 02_平台面板.scad — 上层载物平台 v3
// ============================================================
// 150×120mm, 网格化M3孔, 扎带槽
// 底面中央: Roll云台法兰接口 (28×28mm)
// ============================================================

platform_length = 150;
platform_width  = 120;
platform_thick  = 3;
lip_height      = 4;
lip_width       = 2;
m3_dia          = 3.2;
m3_cb_dia       = 6.0;
m3_cb_depth     = 2.5;

// Roll云台接口 (28×28方形, 4×M3)
flange_spacing = 28;
flange_hole    = 3.2;

// ============================================================
module rounded_rect(l, w, h, r) {
    linear_extrude(height = h, center = true)
    offset(r = r)
    square([l - 2*r, w - 2*r], center = true);
}

module platform_top() {
    difference() {
        union() {
            // 主体
            rounded_rect(platform_length, platform_width, platform_thick, 8);

            // 边缘防滑凸起
            translate([0, 0, platform_thick/2 + lip_height/2])
            difference() {
                rounded_rect(platform_length, platform_width, lip_height, 8);
                translate([0, 0, -0.01])
                rounded_rect(platform_length - 2*lip_width,
                             platform_width  - 2*lip_width,
                             lip_height + 0.02, 8 - lip_width);
            }

            // 底面中央连接凸台
            translate([0, 0, -platform_thick/2 - 3])
            cylinder(d = 36, h = 6, $fn = 64);
        }

        // ===== M3网格 (10mm间距, 避开中央法兰区) =====
        for (x = [-70 : 10 : 70])
            for (y = [-55 : 10 : 55])
                if (abs(x) > 18 || abs(y) > 18)  // 避开中央区域
                    translate([x, y, 0])
                    cylinder(d = m3_dia, h = platform_thick + 2, center = true, $fn = 32);

        // ===== 四角沉头孔 (M3, 用于固定到支架等) =====
        for (x = [-67, 67], y = [-52, 52]) {
            translate([x, y, platform_thick/2 - m3_cb_depth])
            cylinder(d = m3_cb_dia, h = m3_cb_depth + 0.01, $fn = 32);
            translate([x, y, -platform_thick/2 - 0.01])
            cylinder(d = m3_dia, h = platform_thick + 2, $fn = 32);
        }

        // ===== Roll法兰安装孔 (28×28, 从底面打入) =====
        for (x = [-flange_spacing/2, flange_spacing/2])
            for (y = [-flange_spacing/2, flange_spacing/2])
                translate([x, y, -platform_thick/2 - 3 - 6 - 0.01])
                cylinder(d = flange_hole, h = platform_thick + 3 + 6 + 0.02, $fn = 32);

        // ===== 扎带槽 (4边各1条) =====
        for (s = [-1, 1]) {
            translate([0, s * (platform_width/2 - 8), platform_thick - 2.5])
            cube([platform_length - 30, 3, 3], center = true);
            translate([s * (platform_length/2 - 8), 0, platform_thick - 2.5])
            cube([3, platform_width - 30, 3], center = true);
        }
    }
}

platform_top();

// ============================================================
// 打印：层高0.2, 填充15%, 平放, 凸台朝下需支撑, ~1.5h
// 替代方案：亚克力板激光切割 + 胶粘中央凸台
// ============================================================
