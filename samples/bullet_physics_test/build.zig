const std = @import("std");

const Options = @import("../../build.zig").Options;
const content_dir = "bullet_physics_test_content/";

pub fn build(b: *std.build.Builder, options: Options) *std.build.LibExeObjStep {
    const exe_options = b.addOptions();
    exe_options.addOption(bool, "enable_pix", options.enable_pix);
    exe_options.addOption(bool, "enable_dx_debug", options.enable_dx_debug);
    exe_options.addOption(bool, "enable_dx_gpu_debug", options.enable_dx_gpu_debug);
    exe_options.addOption(bool, "enable_tracy", options.tracy != null);
    exe_options.addOption(bool, "enable_d2d", false);
    exe_options.addOption([]const u8, "content_dir", content_dir);

    const exe = b.addExecutable("bullet_physics_test", thisDir() ++ "/src/bullet_physics_test.zig");
    exe.setBuildMode(options.build_mode);
    exe.setTarget(options.target);
    exe.addOptions("build_options", exe_options);

    const dxc_step = buildShaders(b);
    const install_content_step = b.addInstallDirectory(.{
        .source_dir = thisDir() ++ "/" ++ content_dir,
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/" ++ content_dir,
    });
    install_content_step.step.dependOn(dxc_step);
    exe.step.dependOn(&install_content_step.step);

    // This is needed to export symbols from an .exe file.
    // We export D3D12SDKVersion and D3D12SDKPath symbols which
    // is required by DirectX 12 Agility SDK.
    exe.rdynamic = true;
    exe.want_lto = false;

    const options_pkg = std.build.Pkg{
        .name = "build_options",
        .path = exe_options.getSource(),
    };

    const zwin32_pkg = std.build.Pkg{
        .name = "zwin32",
        .path = .{ .path = thisDir() ++ "/../../libs/zwin32/zwin32.zig" },
    };
    exe.addPackage(zwin32_pkg);

    const ztracy_pkg = std.build.Pkg{
        .name = "ztracy",
        .path = .{ .path = thisDir() ++ "/../../libs/ztracy/src/ztracy.zig" },
        .dependencies = &[_]std.build.Pkg{options_pkg},
    };
    exe.addPackage(ztracy_pkg);
    @import("../../libs/ztracy/build.zig").link(b, exe, .{ .tracy_path = options.tracy });

    const zd3d12_pkg = std.build.Pkg{
        .name = "zd3d12",
        .path = .{ .path = thisDir() ++ "/../../libs/zd3d12/src/zd3d12.zig" },
        .dependencies = &[_]std.build.Pkg{
            zwin32_pkg,
            ztracy_pkg,
            options_pkg,
        },
    };
    exe.addPackage(zd3d12_pkg);
    @import("../../libs/zd3d12/build.zig").link(b, exe);

    const common_pkg = std.build.Pkg{
        .name = "common",
        .path = .{ .path = thisDir() ++ "/../../libs/common/src/common.zig" },
        .dependencies = &[_]std.build.Pkg{
            zwin32_pkg,
            zd3d12_pkg,
            ztracy_pkg,
            options_pkg,
        },
    };
    exe.addPackage(common_pkg);
    @import("../../libs/common/build.zig").link(b, exe);

    const zbullet_pkg = std.build.Pkg{
        .name = "zbullet",
        .path = .{ .path = thisDir() ++ "/../../libs/zbullet/src/zbullet.zig" },
    };
    exe.addPackage(zbullet_pkg);
    @import("../../libs/zbullet/build.zig").link(b, exe);

    // We use 'cbullet' directly so we need to add it to the include path.
    exe.addIncludeDir(thisDir() ++ "/../../libs/zbullet/libs/cbullet");

    return exe;
}

fn buildShaders(b: *std.build.Builder) *std.build.Step {
    const dxc_step = b.step("bullet_physics_test-dxc", "Build shaders for 'bullet_physics_test' demo");

    var dxc_command = makeDxcCmd(
        "../../libs/common/src/hlsl/common.hlsl",
        "vsImGui",
        "imgui.vs.cso",
        "vs",
        "PSO__IMGUI",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd(
        "../../libs/common/src/hlsl/common.hlsl",
        "psImGui",
        "imgui.ps.cso",
        "ps",
        "PSO__IMGUI",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd(
        "src/bullet_physics_test.hlsl",
        "vsPhysicsDebug",
        "physics_debug.vs.cso",
        "vs",
        "PSO__PHYSICS_DEBUG",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd(
        "src/bullet_physics_test.hlsl",
        "psPhysicsDebug",
        "physics_debug.ps.cso",
        "ps",
        "PSO__PHYSICS_DEBUG",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd(
        "src/bullet_physics_test.hlsl",
        "vsSimpleEntity",
        "simple_entity.vs.cso",
        "vs",
        "PSO__SIMPLE_ENTITY",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd(
        "src/bullet_physics_test.hlsl",
        "gsSimpleEntity",
        "simple_entity.gs.cso",
        "gs",
        "PSO__SIMPLE_ENTITY",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd(
        "src/bullet_physics_test.hlsl",
        "psSimpleEntity",
        "simple_entity.ps.cso",
        "ps",
        "PSO__SIMPLE_ENTITY",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd(
        "src/bullet_physics_test.hlsl",
        "psSimpleEntity",
        "simple_entity_with_gs.ps.cso",
        "ps",
        "PSO__SIMPLE_ENTITY_WITH_GS",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    return dxc_step;
}

fn makeDxcCmd(
    comptime input_path: []const u8,
    comptime entry_point: []const u8,
    comptime output_filename: []const u8,
    comptime profile: []const u8,
    comptime define: []const u8,
) [9][]const u8 {
    const shader_ver = "6_6";
    const shader_dir = thisDir() ++ "/" ++ content_dir ++ "shaders/";
    return [9][]const u8{
        thisDir() ++ "/../../libs/zwin32/bin/x64/dxc.exe",
        thisDir() ++ "/" ++ input_path,
        "/E " ++ entry_point,
        "/Fo " ++ shader_dir ++ output_filename,
        "/T " ++ profile ++ "_" ++ shader_ver,
        if (define.len == 0) "" else "/D " ++ define,
        "/WX",
        "/Ges",
        "/O3",
    };
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
