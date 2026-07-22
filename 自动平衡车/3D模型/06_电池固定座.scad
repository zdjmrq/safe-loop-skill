// ============================================================
// 06_电池固定座.scad — 通用电池绑带托盘 v4
// ============================================================
// 设计：底板 + 前后挡块 + 多道扎带槽
//       托盘放在底盘下方, 电池放在托盘上
//       扎带从底盘上面穿过底盘槽→托盘槽→绕过电池→回到上面收紧
//       一层扎带同时固定托盘和电池, 不需要螺丝
//       适配: 长80~120mm, 宽30~40mm 的各种锂电
// ============================================================

/* [全局参数] */
base_length  = 120;   // 底板长
base_width   = 50;    // 底板宽
base_thick   = 2.5;   // 底板厚

// 挡块
block_width  = 40;    // 挡块宽
block_height = 20;    // 挡块高
block_thick  = 3;     // 挡块厚

// 扎带槽 (与底盘扎带槽大致对齐即可)
strap_w      = 4;     // 槽宽
strap_step   = 15;    // 槽间距

// ============================================================
module battery_holder() {
    difference() {
        union() {
            // 底板
            translate([0, 0, -base_thick/2])
            cube([base_length, base_width, base_thick], center = true);

            // 前挡块
            translate([base_length/2 - block_thick/2, 0, block_height/2])
            cube([block_thick, block_width, block_height], center = true);

            // 后挡块
            translate([-base_length/2 + block_thick/2, 0, block_height/2])
            cube([block_thick, block_width, block_height], center = true);

            // 底板加强筋
            for (x = [-30, 0, 30])
                translate([x, 0, -base_thick/2 + 0.5])
                cube([2, base_width - 6, 1], center = true);
        }

        // ===== 横向扎带槽 (多道, 与底盘槽协同) =====
        for (x = [-base_length/2 + 15 : strap_step : base_length/2 - 15])
            translate([x, 0, -base_thick/2 - 0.5])
            cube([strap_w, base_width + 10, base_thick + 1], center = true);

        // ===== 纵向槽 (防侧滑) =====
        translate([0, 0, -base_thick/2 - 0.5])
        cube([base_length + 10, strap_w, base_thick + 1], center = true);

        // ===== 减重底孔 =====
        for (x = [-40, -20, 0, 20, 40])
            translate([x, 0, -base_thick/2 - 0.5])
            cylinder(d = 12, h = base_thick + 1, center = true, $fn = 6);
    }
}

battery_holder();

// ============================================================
// 安装方式:
// 1. 托盘放在底盘正下方, 电池放在托盘上(压在前后挡块之间)
// 2. 4根扎带从底盘上面往下穿:
//    底盘网格孔/扎带槽 → 托盘槽 → 绕过电池底部 → 另一侧上来
// 3. 收紧扎带 → 电池被压在托盘上, 托盘被压在底盘下
//    一层扎带同时固定两样东西
//
// 如果电池比挡块间距短: 垫泡沫/EVA棉
// 如果电池比挡块间距长: 把挡块切掉一个, 靠扎带限位
//
// 打印: 层高0.2, 填充20%, 底板朝下, ~1.5h
// ============================================================
