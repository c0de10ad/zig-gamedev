const std = @import("std");

const Options = @import("../../build.zig").Options;
const content_dir = "mesh_shader_test_content/";

pub fn build(b: *std.build.Builder, options: Options) *std.build.LibExeObjStep {
    const exe_options = b.addOptions();
    exe_options.addOption(bool, "enable_pix", options.enable_pix);
    exe_options.addOption(bool, "enable_dx_debug", options.enable_dx_debug);
    exe_options.addOption(bool, "enable_dx_gpu_debug", options.enable_dx_gpu_debug);
    exe_options.addOption(bool, "enable_tracy", options.tracy != null);
    exe_options.addOption(bool, "enable_d2d", false);
    exe_options.addOption([]const u8, "content_dir", content_dir);

    const exe = b.addExecutable("mesh_shader_test", thisDir() ++ "/src/mesh_shader_test.zig");
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

    return exe;
}

fn buildShaders(b: *std.build.Builder) *std.build.Step {
    const dxc_step = b.step("mesh_shader_test-dxc", "Build shaders for 'mesh_shader_test' demo");

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
        "src/mesh_shader_test.hlsl",
        "msMain",
        "mesh_shader.ms.cso",
        "ms",
        "PSO__MESH_SHADER",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd(
        "src/mesh_shader_test.hlsl",
        "psMain",
        "mesh_shader.ps.cso",
        "ps",
        "PSO__MESH_SHADER",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd(
        "src/mesh_shader_test.hlsl",
        "vsMain",
        "vertex_shader.vs.cso",
        "vs",
        "PSO__VERTEX_SHADER",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd(
        "src/mesh_shader_test.hlsl",
        "psMain",
        "vertex_shader.ps.cso",
        "ps",
        "PSO__VERTEX_SHADER",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd(
        "src/mesh_shader_test.hlsl",
        "vsMain",
        "vertex_shader_fixed.vs.cso",
        "vs",
        "PSO__VERTEX_SHADER_FIXED",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd(
        "src/mesh_shader_test.hlsl",
        "psMain",
        "vertex_shader_fixed.ps.cso",
        "ps",
        "PSO__VERTEX_SHADER_FIXED",
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
