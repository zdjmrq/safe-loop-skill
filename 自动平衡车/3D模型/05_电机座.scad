// ============================================================
// 05_电机座.scad — N20电机可调夹具 v4
// ============================================================
// v4 修订：
//   - 两段式内孔：后段Ø13mm(电机圆柱体) + 前段13×11mm(减速箱矩形腔)
//   - 开口槽从内孔边缘直通外壁 (真正能夹紧)
//   - 法兰长孔Z=[4,18], 匹配底盘凸台孔Z=5,15
//   - 数量×2 (第二个镜像)
// ============================================================

/* [全局参数] */
// N20电机尺寸
motor_dia       = 12;    // 电机后段直径
motor_len       = 25;    // 电机后段长度
gearbox_w       = 12;    // 减速箱截面宽
gearbox_h       = 10;    // 减速箱截面高
gearbox_len     = 15;    // 减速箱段长度
motor_total     = 40;    // 总长
shaft_dia       = 3.2;   // 输出轴径
shaft_len       = 12;    // 轴露出长度

// 夹具主体
clamp_len       = 44;    // 夹具总长
body_w          = 24;    // 宽
body_h          = 24;    // 高

// 法兰 (接底盘凸台)
flange_len      = 36;    // 法兰前后长
flange_w        = 10;    // 法兰宽
flange_thick    = 3;     // 法兰厚 (实际是Y方向深度)
flange_hole_h   = 16;    // 前后孔距 (±8)
flange_slot_z0  = 4;     // 长孔起点Z
flange_slot_h   = 14;    // 长孔长度 (终点Z=18)
flange_slot_w   = 3.2;   // 槽宽=M3

// 锁紧结构
clamp_screw_dia = 3.2;
clamp_ear_w     = 8;     // 耳朵宽
clamp_ear_thick = 4;     // 耳朵厚

m3_dia = 3.2;
nut_d  = 6.5;            // M3螺母对边
nut_h  = 2.8;

// ============================================================
module motor_mount() {
    difference() {
        union() {
            // 主体 (含前后壁)
            translate([0, 0, body_h/2])
            cube([clamp_len, body_w, body_h], center = true);

            // 安装法兰 (从侧面伸出, 接底盘凸台)
            translate([0, -body_w/2 - flange_w/2, body_h/2])
            cube([flange_len, flange_w, body_h], center = true);

            // 夹紧耳朵 (上下各一对, 在夹缝两侧)
            // 上耳
            translate([0, body_w/2 + clamp_ear_w/2, body_h - clamp_ear_thick/2])
            cube([clamp_len, clamp_ear_w, clamp_ear_thick], center = true);
            // 下耳
            translate([0, body_w/2 + clamp_ear_w/2, clamp_ear_thick/2])
            cube([clamp_len, clamp_ear_w, clamp_ear_thick], center = true);

            // 法兰加强三角
            for (fx = [-flange_len/3, 0, flange_len/3])
                translate([fx, -body_w/2, body_h/2])
                rotate([90, 0, 0])
                linear_extrude(height = flange_w)
                polygon([[0,0], [4,0], [0,4]]);
        }

        // ===== 两段式内孔 =====
        // 后段: 电机圆柱体 Ø13mm (留1mm间隙)
        translate([-(gearbox_len)/2, 0, body_h/2])
        rotate([0, 90, 0])
        cylinder(d = motor_dia + 1, h = motor_len + 4,
                 center = true, $fn = 48);

        // 前段: 减速箱矩形腔 13×11mm
        translate([clamp_len/2 - 2 - gearbox_len/2, 0, body_h/2])
        cube([gearbox_len + 0.6, gearbox_w + 1, gearbox_h + 1], center = true);

        // 两段之间的过渡锥
        translate([gearbox_len/2, 0, body_h/2])
        rotate([0, 90, 0])
        cylinder(d1 = motor_dia + 1, d2 = max(gearbox_w, gearbox_h) + 3,
                 h = 4, center = true, $fn = 48);

        // 输出轴孔
        translate([clamp_len/2 - 1, 0, body_h/2])
        rotate([0, 90, 0])
        cylinder(d = shaft_dia, h = shaft_len + 4, center = true, $fn = 32);

        // ===== 开口槽 (从内孔直通外壁, 让夹具能弹性变形) =====
        // 缝宽2mm, 从内孔到外壁
        slit_start_y = motor_dia/2;           // 孔边缘 Y≈6
        slit_end_y   = body_w/2;              // 外壁 Y=12
        slit_center_y = (slit_start_y + slit_end_y) / 2;
        slit_width_y  = slit_end_y - slit_start_y;

        translate([0, slit_center_y, body_h/2])
        cube([clamp_len + 2, slit_width_y, body_h + 2], center = true);

        // 上下水平释放槽 (让夹缝更灵活)
        translate([0, body_w/4, body_h - 1])
        cube([clamp_len + 2, body_w/2 + 2, 2], center = true);
        translate([0, body_w/4, 1])
        cube([clamp_len + 2, body_w/2 + 2, 2], center = true);

        // ===== 法兰竖向长孔 (×4) =====
        for (fx = [-flange_hole_h/2, flange_hole_h/2])
            translate([fx, -body_w/2 - flange_w/2,
                       flange_slot_z0 + flange_slot_h/2])
            hull() {
                cylinder(d = flange_slot_w, h = flange_w + 2,
                         center = true, $fn = 24);
                translate([0, 0, flange_slot_h - flange_slot_w])
                cylinder(d = flange_slot_w, h = flange_w + 2,
                         center = true, $fn = 24);
            }

        // ===== 夹紧螺丝孔 (从耳朵外侧穿入) =====
        for (fz = [clamp_ear_thick/2, body_h - clamp_ear_thick/2])
            for (fx = [-clamp_len/4, clamp_len/4])
                translate([fx, body_w/2 + clamp_ear_w, fz])
                rotate([90, 0, 0])
                cylinder(d = clamp_screw_dia, h = clamp_ear_w + 2,
                         center = true, $fn = 32);

        // ===== 螺母陷阱 (耳朵内侧) =====
        for (fz = [clamp_ear_thick/2, body_h - clamp_ear_thick/2])
            for (fx = [-clamp_len/4, clamp_len/4])
                translate([fx, body_w/2 + clamp_ear_w - clamp_ear_w + 1, fz])
                rotate([90, 0, 0])
                cylinder(d = nut_d, h = nut_h + 0.3, center = true, $fn = 6);

        // ===== 减重/散热孔 =====
        for (fx = [-12, 0, 12])
            translate([fx, -4, body_h/2])
            rotate([0, 90, 0])
            cylinder(d = 6, h = 6, center = true, $fn = 24);
    }
}

motor_mount();

// ============================================================
// 使用说明:
// 1. 打印×2 (第二个镜像)
// 2. N20电机从后端塞入: 电机体进Ø13段, 减速箱进矩形腔
// 3. M3×20螺丝穿过上下耳朵→螺母陷阱→逐步拧紧夹住电机
// 4. M3×14螺丝穿过法兰长孔→底盘凸台孔→加螺母锁死
// 5. Z轴可调: 长孔范围4~18mm, 底盘孔在5和15mm, 有足够余量
//
// 打印: 层高0.2, 填充25%, 法兰朝下平放, ~50min
// ============================================================
