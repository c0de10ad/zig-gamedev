const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const zwin32 = @import("zwin32");
const w32 = zwin32.base;
const d3d12 = zwin32.d3d12;
const hrPanic = zwin32.hrPanic;
const hrPanicOnFail = zwin32.hrPanicOnFail;
const zd3d12 = @import("zd3d12");
const common = @import("common");
const GuiRenderer = common.GuiRenderer;
const c = common.c;
const zm = @import("zmath");
const zbt = @import("zbullet");

pub export const D3D12SDKVersion: u32 = 4;
pub export const D3D12SDKPath: [*:0]const u8 = ".\\d3d12\\";

const content_dir = @import("build_options").content_dir;

const window_name = "zig-gamedev: intro 6";
const window_width = 1920;
const window_height = 1080;

const Pso_DrawConst = struct {
    object_to_world: [16]f32,
};

const Pso_FrameConst = struct {
    world_to_clip: [16]f32,
};

const Pso_Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
};

const DemoState = struct {
    gctx: zd3d12.GraphicsContext,
    guir: GuiRenderer,
    frame_stats: common.FrameStats,

    simple_pso: zd3d12.PipelineHandle,

    vertex_buffer: zd3d12.ResourceHandle,
    index_buffer: zd3d12.ResourceHandle,

    depth_texture: zd3d12.ResourceHandle,
    depth_texture_dsv: d3d12.CPU_DESCRIPTOR_HANDLE,

    mesh_num_vertices: u32,
    mesh_num_indices: u32,

    physics: struct {
        world: *const zbt.World,
        shapes: std.ArrayList(*const zbt.Shape),
    },
    camera: struct {
        position: [3]f32 = .{ 0.0, 10.0, -10.0 },
        forward: [3]f32 = .{ 0.0, 0.0, 1.0 },
        pitch: f32 = 0.25 * math.pi,
        yaw: f32 = 0.0,
    } = .{},
    mouse: struct {
        cursor_prev_x: i32 = 0,
        cursor_prev_y: i32 = 0,
    } = .{},
};

fn init(allocator: std.mem.Allocator) !DemoState {
    const window = try common.initWindow(allocator, window_name, window_width, window_height);

    var arena_allocator_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator_state.deinit();
    const arena_allocator = arena_allocator_state.allocator();

    var gctx = zd3d12.GraphicsContext.init(allocator, window);

    // Enable vsync.
    gctx.present_flags = 0;
    gctx.present_interval = 1;

    const simple_pso = blk: {
        const input_layout_desc = [_]d3d12.INPUT_ELEMENT_DESC{
            d3d12.INPUT_ELEMENT_DESC.init("POSITION", 0, .R32G32B32_FLOAT, 0, 0, .PER_VERTEX_DATA, 0),
            d3d12.INPUT_ELEMENT_DESC.init("_Normal", 0, .R32G32B32_FLOAT, 0, 12, .PER_VERTEX_DATA, 0),
        };

        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = &input_layout_desc,
            .NumElements = input_layout_desc.len,
        };
        pso_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        pso_desc.NumRenderTargets = 1;
        pso_desc.DSVFormat = .D32_FLOAT;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        break :blk gctx.createGraphicsShaderPipeline(
            arena_allocator,
            &pso_desc,
            content_dir ++ "shaders/intro3.vs.cso",
            content_dir ++ "shaders/intro3.ps.cso",
        );
    };

    // Load a mesh from file and store the data in temporary arrays.
    var mesh_indices = std.ArrayList(u32).init(arena_allocator);
    var mesh_positions = std.ArrayList([3]f32).init(arena_allocator);
    var mesh_normals = std.ArrayList([3]f32).init(arena_allocator);
    {
        const data = common.parseAndLoadGltfFile(content_dir ++ "cube.gltf");
        defer c.cgltf_free(data);
        common.appendMeshPrimitive(data, 0, 0, &mesh_indices, &mesh_positions, &mesh_normals, null, null);
    }
    const mesh_num_indices = @intCast(u32, mesh_indices.items.len);
    const mesh_num_vertices = @intCast(u32, mesh_positions.items.len);

    const vertex_buffer = gctx.createCommittedResource(
        .DEFAULT,
        d3d12.HEAP_FLAG_NONE,
        &d3d12.RESOURCE_DESC.initBuffer(mesh_num_vertices * @sizeOf(Pso_Vertex)),
        d3d12.RESOURCE_STATE_COPY_DEST,
        null,
    ) catch |err| hrPanic(err);

    const index_buffer = gctx.createCommittedResource(
        .DEFAULT,
        d3d12.HEAP_FLAG_NONE,
        &d3d12.RESOURCE_DESC.initBuffer(mesh_num_indices * @sizeOf(u32)),
        d3d12.RESOURCE_STATE_COPY_DEST,
        null,
    ) catch |err| hrPanic(err);

    const depth_texture = gctx.createCommittedResource(
        .DEFAULT,
        d3d12.HEAP_FLAG_NONE,
        &blk: {
            var desc = d3d12.RESOURCE_DESC.initTex2d(.D32_FLOAT, gctx.viewport_width, gctx.viewport_height, 1);
            desc.Flags = d3d12.RESOURCE_FLAG_ALLOW_DEPTH_STENCIL | d3d12.RESOURCE_FLAG_DENY_SHADER_RESOURCE;
            break :blk desc;
        },
        d3d12.RESOURCE_STATE_DEPTH_WRITE,
        &d3d12.CLEAR_VALUE.initDepthStencil(.D32_FLOAT, 1.0, 0),
    ) catch |err| hrPanic(err);

    const depth_texture_dsv = gctx.allocateCpuDescriptors(.DSV, 1);
    gctx.device.CreateDepthStencilView(
        gctx.lookupResource(depth_texture).?,
        null,
        depth_texture_dsv,
    );

    const physics_world = try zbt.World.init(.{});

    //var physics_debug = allocator.create(zbt.DebugDrawer) catch unreachable;
    //physics_debug.* = zbt.DebugDrawer.init(allocator);

    //physics_world.setDebugDrawer(&physics_debug.getDebugDraw());
    //physics_world.setDebugMode(zbt.dbgmode_draw_wireframe);

    const physics_shapes = blk: {
        var shapes = std.ArrayList(*const zbt.Shape).init(allocator);

        const box_shape = try zbt.BoxShape.init(&.{ 0.5, 0.5, 0.5 });
        try shapes.append(box_shape.asShape());

        const ground_shape = try zbt.BoxShape.init(&.{ 100.0, 0.2, 100.0 });
        try shapes.append(ground_shape.asShape());

        const box_body = try zbt.Body.init(
            1.0,
            &zm.mat43ToArray(zm.translation(0.0, 3.0, 0.0)),
            box_shape.asShape(),
        );
        physics_world.addBody(box_body);

        const ground_body = try zbt.Body.init(
            0.0,
            &zm.mat43ToArray(zm.identity()),
            ground_shape.asShape(),
        );
        physics_world.addBody(ground_body);

        break :blk shapes;
    };

    gctx.beginFrame();

    var guir = GuiRenderer.init(arena_allocator, &gctx, 1, content_dir);

    // Fill vertex buffer with vertex data.
    {
        const verts = gctx.allocateUploadBufferRegion(Pso_Vertex, mesh_num_vertices);
        for (mesh_positions.items) |_, i| {
            verts.cpu_slice[i].position = mesh_positions.items[i];
            verts.cpu_slice[i].normal = mesh_normals.items[i];
        }

        gctx.cmdlist.CopyBufferRegion(
            gctx.lookupResource(vertex_buffer).?,
            0,
            verts.buffer,
            verts.buffer_offset,
            verts.cpu_slice.len * @sizeOf(@TypeOf(verts.cpu_slice[0])),
        );
    }

    // Fill index buffer with index data.
    {
        const indices = gctx.allocateUploadBufferRegion(u32, mesh_num_indices);
        for (mesh_indices.items) |_, i| {
            indices.cpu_slice[i] = mesh_indices.items[i];
        }

        gctx.cmdlist.CopyBufferRegion(
            gctx.lookupResource(index_buffer).?,
            0,
            indices.buffer,
            indices.buffer_offset,
            indices.cpu_slice.len * @sizeOf(@TypeOf(indices.cpu_slice[0])),
        );
    }

    gctx.addTransitionBarrier(vertex_buffer, d3d12.RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER);
    gctx.addTransitionBarrier(index_buffer, d3d12.RESOURCE_STATE_INDEX_BUFFER);
    gctx.flushResourceBarriers();

    gctx.endFrame();
    gctx.finishGpuCommands();

    return DemoState{
        .gctx = gctx,
        .guir = guir,
        .frame_stats = common.FrameStats.init(),
        .simple_pso = simple_pso,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .depth_texture = depth_texture,
        .depth_texture_dsv = depth_texture_dsv,
        .mesh_num_vertices = mesh_num_vertices,
        .mesh_num_indices = mesh_num_indices,
        .physics = .{
            .world = physics_world,
            .shapes = physics_shapes,
        },
    };
}

fn deinit(demo: *DemoState, allocator: std.mem.Allocator) void {
    demo.gctx.finishGpuCommands();
    {
        var i = demo.physics.world.getNumBodies() - 1;
        while (i >= 0) : (i -= 1) {
            const body = demo.physics.world.getBody(i);
            demo.physics.world.removeBody(body);
            body.deinit();
        }
    }
    for (demo.physics.shapes.items) |shape|
        shape.deinit();
    demo.physics.shapes.deinit();
    demo.physics.world.deinit();
    demo.guir.deinit(&demo.gctx);
    demo.gctx.deinit(allocator);
    common.deinitWindow(allocator);
    demo.* = undefined;
}

fn update(demo: *DemoState) void {
    demo.frame_stats.update(demo.gctx.window, window_name);
    const dt = demo.frame_stats.delta_time;

    _ = demo.physics.world.stepSimulation(dt, .{});

    common.newImGuiFrame(dt);

    c.igSetNextWindowPos(
        .{ .x = @intToFloat(f32, demo.gctx.viewport_width) - 600.0 - 20, .y = 20.0 },
        c.ImGuiCond_FirstUseEver,
        .{ .x = 0.0, .y = 0.0 },
    );
    c.igSetNextWindowSize(.{ .x = 600.0, .y = -1 }, c.ImGuiCond_Always);

    _ = c.igBegin(
        "Demo Settings",
        null,
        c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoResize | c.ImGuiWindowFlags_NoSavedSettings,
    );
    c.igBulletText("", "");
    c.igSameLine(0, -1);
    c.igTextColored(.{ .x = 0, .y = 0.8, .z = 0, .w = 1 }, "Right Mouse Button + drag", "");
    c.igSameLine(0, -1);
    c.igText(" :  rotate camera", "");

    c.igBulletText("", "");
    c.igSameLine(0, -1);
    c.igTextColored(.{ .x = 0, .y = 0.8, .z = 0, .w = 1 }, "W, A, S, D", "");
    c.igSameLine(0, -1);
    c.igText(" :  move camera", "");

    c.igEnd();

    // Handle camera rotation with mouse.
    {
        var pos: w32.POINT = undefined;
        _ = w32.GetCursorPos(&pos);
        const delta_x = @intToFloat(f32, pos.x) - @intToFloat(f32, demo.mouse.cursor_prev_x);
        const delta_y = @intToFloat(f32, pos.y) - @intToFloat(f32, demo.mouse.cursor_prev_y);
        demo.mouse.cursor_prev_x = pos.x;
        demo.mouse.cursor_prev_y = pos.y;

        if (w32.GetAsyncKeyState(w32.VK_RBUTTON) < 0) {
            demo.camera.pitch += 0.0025 * delta_y;
            demo.camera.yaw += 0.0025 * delta_x;
            demo.camera.pitch = math.min(demo.camera.pitch, 0.48 * math.pi);
            demo.camera.pitch = math.max(demo.camera.pitch, -0.48 * math.pi);
            demo.camera.yaw = zm.modAngle(demo.camera.yaw);
        }
    }

    // Handle camera movement with 'WASD' keys.
    {
        const speed = zm.f32x4s(10.0);
        const delta_time = zm.f32x4s(demo.frame_stats.delta_time);
        const transform = zm.mul(zm.rotationX(demo.camera.pitch), zm.rotationY(demo.camera.yaw));
        var forward = zm.normalize3(zm.mul(zm.f32x4(0.0, 0.0, 1.0, 0.0), transform));

        zm.store(demo.camera.forward[0..], forward, 3);

        const right = speed * delta_time * zm.normalize3(zm.cross3(zm.f32x4(0.0, 1.0, 0.0, 0.0), forward));
        forward = speed * delta_time * forward;

        var cpos = zm.load(demo.camera.position[0..], zm.Vec, 3);

        if (w32.GetAsyncKeyState('W') < 0) {
            cpos += forward;
        } else if (w32.GetAsyncKeyState('S') < 0) {
            cpos -= forward;
        }
        if (w32.GetAsyncKeyState('D') < 0) {
            cpos += right;
        } else if (w32.GetAsyncKeyState('A') < 0) {
            cpos -= right;
        }

        zm.store(demo.camera.position[0..], cpos, 3);
    }
}

fn draw(demo: *DemoState) void {
    var gctx = &demo.gctx;

    const cam_world_to_view = zm.lookToLh(
        zm.load(demo.camera.position[0..], zm.Vec, 3),
        zm.load(demo.camera.forward[0..], zm.Vec, 3),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );
    const cam_view_to_clip = zm.perspectiveFovLh(
        0.25 * math.pi,
        @intToFloat(f32, gctx.viewport_width) / @intToFloat(f32, gctx.viewport_height),
        0.01,
        200.0,
    );
    const cam_world_to_clip = zm.mul(cam_world_to_view, cam_view_to_clip);

    gctx.beginFrame();

    const back_buffer = gctx.getBackBuffer();
    gctx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATE_RENDER_TARGET);
    gctx.flushResourceBarriers();

    gctx.cmdlist.OMSetRenderTargets(
        1,
        &[_]d3d12.CPU_DESCRIPTOR_HANDLE{back_buffer.descriptor_handle},
        w32.TRUE,
        &demo.depth_texture_dsv,
    );
    gctx.cmdlist.ClearRenderTargetView(
        back_buffer.descriptor_handle,
        &.{ 0.1, 0.1, 0.1, 1.0 },
        0,
        null,
    );
    gctx.cmdlist.ClearDepthStencilView(demo.depth_texture_dsv, d3d12.CLEAR_FLAG_DEPTH, 1.0, 0, 0, null);

    // Set input assembler (IA) state.
    gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
    gctx.cmdlist.IASetVertexBuffers(0, 1, &[_]d3d12.VERTEX_BUFFER_VIEW{.{
        .BufferLocation = gctx.lookupResource(demo.vertex_buffer).?.GetGPUVirtualAddress(),
        .SizeInBytes = demo.mesh_num_vertices * @sizeOf(Pso_Vertex),
        .StrideInBytes = @sizeOf(Pso_Vertex),
    }});
    gctx.cmdlist.IASetIndexBuffer(&.{
        .BufferLocation = gctx.lookupResource(demo.index_buffer).?.GetGPUVirtualAddress(),
        .SizeInBytes = demo.mesh_num_indices * @sizeOf(u32),
        .Format = .R32_UINT,
    });

    gctx.setCurrentPipeline(demo.simple_pso);

    // Upload per-frame constant data (camera xform).
    {
        const mem = gctx.allocateUploadMemory(Pso_FrameConst, 1);
        zm.storeMat(mem.cpu_slice[0].world_to_clip[0..], zm.transpose(cam_world_to_clip));

        gctx.cmdlist.SetGraphicsRootConstantBufferView(1, mem.gpu_base);
    }

    // For each object, upload per-draw constant data (object to world xform) and draw.
    {
        const body = demo.physics.world.getBody(0);

        // Get transform matrix from the physics simulator.
        const object_to_world = blk: {
            var transform: [12]f32 = undefined;
            body.getGraphicsWorldTransform(&transform);
            break :blk zm.loadMat43(transform[0..]);
        };

        const mem = gctx.allocateUploadMemory(Pso_DrawConst, 1);
        zm.storeMat(mem.cpu_slice[0].object_to_world[0..], zm.transpose(object_to_world));

        gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);
        gctx.cmdlist.DrawIndexedInstanced(demo.mesh_num_indices, 1, 0, 0, 0);
    }

    demo.guir.draw(gctx);

    //demo.physics.world.drawDebug();

    gctx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATE_PRESENT);
    gctx.flushResourceBarriers();

    gctx.endFrame();
}

pub fn main() !void {
    common.init();
    defer common.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Init zbullet library.
    zbt.init();
    defer zbt.deinit();

    var demo = try init(allocator);
    defer deinit(&demo, allocator);

    while (common.handleWindowEvents()) {
        update(&demo);
        draw(&demo);
    }
}
