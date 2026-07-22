// ============================================================
// 04_云台_Roll轴.scad — Roll横滚连接件 v2
// ============================================================
// 材料：PLA 3D打印, 填充≥35%
// 功能：连接Roll舵机(MG996R #2)输出轴与上层平台面板
//
// v2 修订：
//   - 改用舵盘螺丝固定 (不再打印花键)
//   - 平台端法兰4×M3孔, 28×28mm方形排列
//   - 连接柱偏置以补偿舵机轴心不在舵机几何中心
// ============================================================

/* [全局参数] */
// ---- 舵盘连接端 ----
hub_dia        = 28;    // 圆盘直径
hub_thick      = 5;     // 圆盘厚
horn_circle    = 14;    // 舵盘螺丝孔圆直径
horn_hole_dia  = 2.6;   // M2.5
center_hole    = 3.2;   // M3

// ---- 连接柱 ----
// 舵机轴心偏置 (MG996R输出轴偏向前端约5mm)
shaft_offset_y = 5;     // 轴心Y偏置 (舵机坐标)
conn_height    = 12;    // 柱高
conn_dia       = 16;    // 柱径

// ---- 平台端法兰 ----
flange_size   = 44;     // 法兰边长
flange_thick  = 4;      // 法兰厚
// 4×M3孔, 28mm方形排列 (匹配平台底面)
flange_hole_spacing = 28;
flange_hole_dia     = 3.2;

// ============================================================
module roll_bracket() {
    difference() {
        union() {
            // === 舵盘端圆盘 ===
            translate([0, shaft_offset_y, 0])
            cylinder(d = hub_dia, h = hub_thick, $fn = 64);

            // === 连接柱 ===
            translate([0, shaft_offset_y, hub_thick])
            cylinder(d1 = hub_dia, d2 = conn_dia, h = 4, $fn = 64);

            translate([0, shaft_offset_y, hub_thick + 4])
            cylinder(d = conn_dia, h = conn_height - 4, $fn = 64);

            // === 平台法兰 ===
            translate([0, 0, hub_thick + conn_height])
            cube([flange_size, flange_size, flange_thick], center = true);

            // === 加强筋 ===
            for (a = [0:60:300])
                translate([0, shaft_offset_y, hub_thick + conn_height/2])
                rotate([0, 0, a])
                cube([conn_dia + 8, 3, conn_height/2 + flange_thick/2], center = true);

            // 法兰底部三角撑
            for (a = [45:90:315])
                translate([flange_size/3 * cos(a), flange_size/3 * sin(a),
                           hub_thick + conn_height - 0.5])
                rotate([0, 0, a])
                cube([8, 3, flange_thick + 1], center = true);
        }

        // ===== 切除 =====

        // 舵盘中心M3
        translate([0, shaft_offset_y, -0.01])
        cylinder(d = center_hole, h = hub_thick + 0.02, $fn = 32);

        // 舵盘4×M2.5
        for (a = [0:90:270])
            translate([horn_circle/2 * cos(a),
                       shaft_offset_y + horn_circle/2 * sin(a), -0.01])
            cylinder(d = horn_hole_dia, h = hub_thick + 0.02, $fn = 24);

        // 舵盘嵌入槽
        translate([0, shaft_offset_y, hub_thick - 2.5])
        cylinder(d = 22, h = 3, $fn = 64);

        // 法兰4×M3孔 (28×28mm方形)
        for (x = [-flange_hole_spacing/2, flange_hole_spacing/2])
            for (y = [-flange_hole_spacing/2, flange_hole_spacing/2])
                translate([x, y, hub_thick + conn_height - 0.01])
                cylinder(d = flange_hole_dia, h = flange_thick + 2, $fn = 32);

        // 减重镂空 (连接柱内部)
        translate([0, shaft_offset_y, hub_thick + 2])
        cylinder(d = conn_dia - 7, h = conn_height + flange_thick, $fn = 32);
    }
}

roll_bracket();

// ============================================================
// 装配说明:
// 1. 将MG996R自带的圆形舵盘用M3螺丝固定在舵机输出轴上
// 2. 将此件的舵盘端圆盘用4颗M2.5螺丝固定在舵盘上
// 3. 平台端法兰用4颗M3螺丝固定在平台面板底面(28×28mm孔位)
//
// 打印建议:
// - 填充 35%+, 受力件
// - 方向: 平台法兰朝下, 舵盘端朝上
// - 支撑: 法兰悬空处需要少量支撑
// - 预计时间: ~40min
// ============================================================
