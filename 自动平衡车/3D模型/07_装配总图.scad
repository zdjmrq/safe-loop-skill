// ============================================================
// 07_装配总图.scad — 自动平衡车3D结构总装 v4
// ============================================================
// v4: Pitch舵机移至X=20, 电机座两段式内孔, 开口槽切透
// ============================================================

pitch_x = 20;  // 与01底盘pitch_servo_x一致

// ---- 底盘 ----
module chassis_simple() {
    color("DarkGreen", 0.8) {
        translate([0, 0, -1.5])
        cube([180, 100, 3], center = true);
        difference() {
            translate([0, 0, 2.5])
            cube([180, 100, 5], center = true);
            translate([0, 0, 2.5])
            cube([175, 95, 6], center = true);
        }
        for (s = [-1, 1])
            translate([0, s * 48.75, 11.5])
            cube([36, 6.5, 20], center = true);
        translate([pitch_x, 0, 3.5])
        cube([58, 30, 4], center = true);
    }
}

// ---- 平台 ----
module platform_simple() {
    color("Orange", 0.7)
    cube([150, 120, 3], center = true);
    color("Orange", 0.5)
    difference() {
        translate([0, 0, 3.5])
        cube([150, 120, 4], center = true);
        translate([0, 0, 3.5])
        cube([146, 116, 5], center = true);
    }
}

// ---- Pitch支架 ----
module pitch_bracket_simple() {
    color("SteelBlue", 0.8) {
        cylinder(d = 30, h = 5, $fn = 48);
        translate([-8, 0, 27.5])
        cube([24, 6, 45], center = true);
        translate([-8, 0, 5 + 45 + 2.5])
        cube([60, 20, 5], center = true);
    }
}

// ---- Roll支架 ----
module roll_bracket_simple() {
    color("Tomato", 0.8) {
        translate([0, 5, 0])
        cylinder(d = 28, h = 5, $fn = 48);
        translate([0, 5, 5])
        cylinder(d = 16, h = 12, $fn = 32);
        translate([0, 0, 17])
        cube([44, 44, 4], center = true);
    }
}

// ---- 电机座 v4 ----
module motor_mount_simple() {
    color("DimGray", 0.7) {
        cube([44, 24, 24], center = true);
        translate([0, -17, 12])
        cube([36, 10, 24], center = true);
    }
}

// ---- N20电机+轮子 (减速箱清晰可见) ----
module motor_wheel(side) {
    // 电机圆柱段
    color("Silver", 0.6)
    translate([-10, side * 56, 0])
    rotate([0, 90, 0])
    cylinder(d = 12, h = 25, center = true, $fn = 32);
    // 减速箱矩形段
    color("Silver", 0.5)
    translate([10, side * 56, 0])
    cube([15, 12, 10], center = true);
    // 轴
    color("Gray", 0.8)
    translate([22, side * 56, 0])
    rotate([0, 90, 0])
    cylinder(d = 3, h = 10, center = true, $fn = 24);
    // 轮
    color("Black", 0.8)
    translate([29, side * 56, 0])
    rotate([0, 90, 0])
    cylinder(d = 43, h = 8, center = true, $fn = 64);
}

// ---- MG996R舵机 ----
module servo(pos, rot) {
    color("DodgerBlue", 0.7)
    translate(pos)
    rotate(rot)
    cube([40.7, 19.7, 42.9], center = true);
}

// ---- 舵盘 ----
module horn(pos, rot) {
    color("White", 0.9)
    translate(pos)
    rotate(rot)
    cylinder(d = 20, h = 2, $fn = 48);
}

// ---- 电池+座 ----
module battery() {
    color("Gold", 0.6)
    translate([0, 0, -21])
    cube([105, 35, 25], center = true);
    color("SaddleBrown", 0.8) {
        translate([0, 0, -1.25])
        cube([120, 50, 2.5], center = true);
        for (s = [-1, 1])
            translate([s * 58.5, 0, 10])
            cube([3, 40, 20], center = true);
    }
}

// ============================================================
module assembly() {
    // 底层: 电池+座
    battery();
    // 底盘
    chassis_simple();

    // 电机+轮
    motor_mount_simple(); motor_wheel(1);
    motor_mount_simple(); motor_wheel(-1);

    // Pitch舵机 (X=pitch_x, 平放)
    servo([pitch_x, 0, 24.45], [0, 0, 0]);
    horn([pitch_x, 0, 3 + 42.9], [0, 0, 0]);

    // Pitch支架 (底板贴在舵盘上)
    pz = 3 + 42.9 + 2;
    translate([pitch_x, 0, pz]) pitch_bracket_simple();

    // Roll舵机 (横放, 轴朝前)
    ptop = pz + 5 + 45 + 5;
    servo([pitch_x - 8, 0, ptop + 21.45], [0, 90, 0]);
    horn([pitch_x - 8 + 42.9/2, 0, ptop + 21.45], [0, 90, 0]);

    // Roll支架
    translate([pitch_x - 8 + 42.9/2, 0, ptop + 21.45])
    roll_bracket_simple();

    // 平台
    plat_z = ptop + 21.45 + 17 + 2 + 1.5;
    translate([pitch_x - 8 + 42.9/2, 0, plat_z])
    platform_simple();

    // 电子元件示意
    color("Purple", 0.25) translate([-40, 0, 7])    cube([53, 23, 8], center = true);
    color("Red",    0.25) translate([-15, 25, 5.5]) cube([18, 15, 5], center = true);
    color("Green",  0.25) translate([-40, -30, 10]) cube([43, 21, 14], center = true);
    color("Cyan",   0.25) translate([40, 30, 5.5])  cube([37, 16, 5], center = true);
}

assembly();

// ============================================================
// v4 改动要点:
// 1. 电机座: 两段式内孔(Ø13圆+矩形腔), 开口槽从内孔直通外壁
// 2. 底盘: 网格全覆盖无空洞, 舵机孔配底面螺母槽
// 3. Pitch舵机X=20(可调), 改善重心分布
// 4. 所有关键参数可调(pitch_servo_x, arm_offset_x等)
//
// 重心调节:
// - 电池(~180g)在底盘中央 X≈0
// - 云台+平台(~200g)在 X≈20~35
// - 初步COM在 X≈13mm 处
// - 如果自平衡时前倾: 减小pitch_servo_x或增大arm_offset_x
// - 如果后倾: 反向调节, 或在底盘尾部加配重
// ============================================================
