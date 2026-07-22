// ============================================================
// 01_车体底盘.scad — 开放网格化底盘 v4
// ============================================================
// v4 修订：
//   - 网格逻辑简化, 无空洞 (全区域10mm间距M3孔)
//   - 舵机安装孔加深, 螺母从下方拧 (凸台底面开六角槽)
//   - pitch_servo_x 参数化, 默认20(建议值)
//   - 避免底盘上方螺丝顶到下方电池的警告
// ============================================================

/* [全局参数] */
chassis_length = 180;
chassis_width  = 100;
base_thickness = 3;
wall_height    = 5;
wall_thickness = 2.5;
m3_dia         = 3.2;

// Pitch舵机X位置 — 调节重心!
// 默认20: 云台重量靠近中央, 配合电池平衡
// 如果重心偏后可增大, 偏前可减小 (范围 -30 ~ 60)
pitch_servo_x  = 20;

// M3网格
grid_spacing   = 10;

// 电机座凸台孔位
motor_hole_z   = [5, 15];
motor_hole_fy  = [-8, 8];

// 舵机安装孔 (MG996R: 48×10mm)
servo_hole_l   = 48;
servo_hole_w   = 10;

// ============================================================
module m3_hole() {
    cylinder(d = m3_dia, h = base_thickness + 0.02, $fn = 32);
}

module ziptie_slot_x(x, length) {
    translate([x, 0, base_thickness - 2])
    cube([length, 3.5, 3], center = true);
}

module ziptie_slot_y(y, length) {
    translate([0, y, base_thickness - 2])
    cube([3.5, length, 3], center = true);
}

// ============================================================
module chassis_base() {
    difference() {
        union() {
            // 底板
            cube([chassis_length, chassis_width, base_thickness], center = true);

            // 四周围挡
            for (sx = [-1, 1])
                translate([sx * (chassis_length/2 - wall_thickness/2), 0,
                           wall_height/2 + base_thickness/2])
                cube([wall_thickness, chassis_width, wall_height], center = true);
            for (sy = [-1, 1])
                translate([0, sy * (chassis_width/2 - wall_thickness/2),
                           wall_height/2 + base_thickness/2])
                cube([chassis_length, wall_thickness, wall_height], center = true);

            // 电机座凸台 (左右两侧加高20mm)
            for (sy = [-1, 1])
                translate([0, sy * (chassis_width/2 - wall_thickness/2),
                           10 + base_thickness/2])
                cube([36, wall_thickness + 4, 20], center = true);

            // Pitch舵机凸台
            translate([pitch_servo_x, 0, base_thickness/2 + 2])
            cube([servo_hole_l + 10, servo_hole_w + 20, 4], center = true);
        }

        // ===== M3网格 (全底板, 10mm间距) =====
        // 避开舵机凸台区域
        for (x = [-85 : grid_spacing : 85])
            for (y = [-45 : grid_spacing : 45])
                // 不在舵机凸台范围内打孔 (留出完整安装面)
                if (!(x > pitch_servo_x - servo_hole_l/2 - 8 &&
                      x < pitch_servo_x + servo_hole_l/2 + 8 &&
                      y > -servo_hole_w/2 - 12 &&
                      y <  servo_hole_w/2 + 12))
                    translate([x, y, 0])
                    m3_hole();

        // ===== 舵机安装孔 (M3, 配螺母槽) =====
        for (x = [pitch_servo_x - servo_hole_l/2, pitch_servo_x + servo_hole_l/2])
            for (y = [-servo_hole_w/2, servo_hole_w/2]) {
                // M3通孔 (从凸台顶面贯穿到底面)
                translate([x, y, -0.01])
                cylinder(d = m3_dia, h = base_thickness + 4 + 2, $fn = 32);
                // 底面六角螺母槽 (M3螺母嵌入)
                translate([x, y, base_thickness - 0.5])
                cylinder(d = 6.5, h = 2.8, $fn = 6);
            }

        // ===== 电机座安装孔 (穿过凸台, Y方向) =====
        for (sy = [-1, 1])
            translate([0, sy * (chassis_width/2 - wall_thickness/2), 0])
            for (fy = motor_hole_fy)
                for (fz = motor_hole_z)
                    translate([fy, 0, fz])
                    rotate([90, 0, 0])
                    cylinder(d = m3_dia, h = wall_thickness + 6,
                             center = true, $fn = 32);

        // ===== 扎带槽 (元件固定 + 电池绑带) =====
        for (x = [-60 : 25 : 60])
            ziptie_slot_x(x, chassis_width - 20);
        for (y = [-30, -15, 0, 15, 30])
            ziptie_slot_y(y, chassis_length - 20);

        // ===== 围挡出线缺口 =====
        for (s = [-1, 1]) {
            translate([s * chassis_length/2, 0, base_thickness/2 + 2])
            cube([wall_thickness + 2, 15, 6], center = true);
            translate([0, s * chassis_width/2, base_thickness/2 + 2])
            cube([20, wall_thickness + 2, 6], center = true);
        }
        translate([-chassis_length/2, 0, base_thickness/2 + 2])
        cube([wall_thickness + 2, 12, 6], center = true);
    }
}

chassis_base();

// ============================================================
// 装配指南:
// - 电子元件用M3尼龙柱+短螺丝固定到网格上 (螺丝别太长!
//   底板下面有电池, M3×6够用, 穿过尼龙柱的用M3×12)
// - Pitch舵机用M3×16从上面穿入, 螺母嵌在凸台底面槽里
// - 电池用扎带/魔术贴绑在底板下面 (电池座固定)
// - pitch_servo_x 默认20: 建议装好后测试重心再调
//
// 打印: 层高0.2, 填充20%, 平放(围挡朝上), ~2h
// ============================================================
