// ============================================================
// 03_云台_Pitch轴.scad — Pitch俯仰支架 v3
// ============================================================
// 连接Pitch舵机(MG996R) → Roll舵机
// - 底板用4×M2.5固定在舵机自带圆形舵盘上 (14mm圆)
// - 顶部4×M3固定Roll舵机的安装耳 (48×10mm)
// - 简化几何，减少支撑需求
// ============================================================

/* [全局参数] */
// 舵盘接口
horn_circle   = 14;    // 舵盘螺丝圆直径
horn_hole     = 2.6;   // M2.5通孔
center_hole   = 3.2;   // M3舵盘中心螺丝

// 支架几何
base_dia      = 30;    // 底圆盘直径
base_thick    = 5;
arm_offset_x  = -8;    // 臂相对舵盘中心的X偏移 (负=向后, 使平台重心后移)
arm_height    = 45;    // 臂高
arm_width     = 24;    // 臂宽
arm_thick     = 6;     // 臂厚

// Roll舵机座 (MG996R标准安装耳 48×10mm)
servo_mount_l = 48;    // 长孔距
servo_mount_w = 10;    // 宽孔距
servo_hole    = 3.2;   // M3

// ============================================================
module pitch_bracket() {
    difference() {
        union() {
            // 底圆盘
            cylinder(d = base_dia, h = base_thick, $fn = 64);

            // 竖直臂
            translate([arm_offset_x, 0, base_thick + arm_height/2])
            cube([arm_width, arm_thick, arm_height], center = true);

            // 臂根三角加强
            for (s = [-1, 1])
                translate([arm_offset_x, s * (arm_thick/2 + 2), base_thick])
                rotate([0, 90, 0])
                linear_extrude(height = arm_width, center = true)
                polygon([[0,0], [30,0], [0,30]]);

            // 顶部舵机座板
            translate([arm_offset_x, 0, base_thick + arm_height + 2.5])
            cube([servo_mount_l + 12, arm_thick + 14, 5], center = true);

            // 安装耳垫高
            for (x = [-servo_mount_l/2, servo_mount_l/2])
                for (y = [-servo_mount_w/2, servo_mount_w/2])
                    translate([arm_offset_x + x, y, base_thick + arm_height + 5 + 2])
                    cylinder(d = 8, h = 4, $fn = 24);
        }

        // 舵盘中心孔
        translate([0, 0, -0.01])
        cylinder(d = center_hole, h = base_thick + 0.02, $fn = 32);

        // 舵盘4×M2.5
        for (a = [0:90:270])
            translate([horn_circle/2 * cos(a), horn_circle/2 * sin(a), -0.01])
            cylinder(d = horn_hole, h = base_thick + 0.02, $fn = 24);

        // 舵盘嵌入槽
        translate([0, 0, base_thick - 2.5])
        cylinder(d = 22, h = 3, $fn = 64);

        // Roll舵机安装孔
        for (x = [-servo_mount_l/2, servo_mount_l/2])
            for (y = [-servo_mount_w/2, servo_mount_w/2])
                translate([arm_offset_x + x, y, base_thick + arm_height + 5 + 2 - 0.01])
                cylinder(d = servo_hole, h = 20, $fn = 32);

        // 减重孔
        translate([arm_offset_x, 0, base_thick + arm_height/2])
        cube([arm_width - 10, arm_thick + 2, arm_height - 16], center = true);
    }
}

pitch_bracket();

// ============================================================
// 装配：舵盘→M3中心螺丝锁在舵机轴上→此件用4×M2.5锁在舵盘上
//       Roll舵机→用随舵机附带的橡胶垫+铜套+4×M3锁在顶部
// 打印：填充35%+, 底圆盘朝下, 臂朝上, 需支撑, ~1h
// ============================================================
