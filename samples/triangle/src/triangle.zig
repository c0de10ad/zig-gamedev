const std = @import("std");
const zwin32 = @import("zwin32");
const w = zwin32.base;
const d3d12 = zwin32.d3d12;
const hrPanic = zwin32.hrPanic;
const hrPanicOnFail = zwin32.hrPanicOnFail;
const zd3d12 = @import("zd3d12");
const common = @import("common");
const c = common.c;
const vm = common.vectormath;
const GuiRenderer = common.GuiRenderer;

pub export const D3D12SDKVersion: u32 = 4;
pub export const D3D12SDKPath: [*:0]const u8 = ".\\d3d12\\";

const content_dir = @import("build_options").content_dir;

pub fn main() !void {
    const window_name = "zig-gamedev: triangle";
    const window_width = 900;
    const window_height = 900;

    common.init();
    defer common.deinit();

    var gpa_allocator_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa_allocator_state.deinit();
        std.debug.assert(leaked == false);
    }
    const gpa_allocator = gpa_allocator_state.allocator();

    var arena_allocator_state = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena_allocator_state.deinit();
    const arena_allocator = arena_allocator_state.allocator();

    const window = common.initWindow(gpa_allocator, window_name, window_width, window_height) catch unreachable;
    defer common.deinitWindow(gpa_allocator);

    var grfx = zd3d12.GraphicsContext.init(gpa_allocator, window);
    defer grfx.deinit(gpa_allocator);

    const pipeline = blk: {
        const input_layout_desc = [_]d3d12.INPUT_ELEMENT_DESC{
            d3d12.INPUT_ELEMENT_DESC.init("POSITION", 0, .R32G32B32_FLOAT, 0, 0, .PER_VERTEX_DATA, 0),
        };
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.DepthStencilState.DepthEnable = w.FALSE;
        pso_desc.InputLayout = .{
            .pInputElementDescs = &input_layout_desc,
            .NumElements = input_layout_desc.len,
        };
        pso_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        pso_desc.NumRenderTargets = 1;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        break :blk grfx.createGraphicsShaderPipeline(
            arena_allocator,
            &pso_desc,
            content_dir ++ "shaders/triangle.vs.cso",
            content_dir ++ "shaders/triangle.ps.cso",
        );
    };

    const vertex_buffer = grfx.createCommittedResource(
        .DEFAULT,
        d3d12.HEAP_FLAG_NONE,
        &d3d12.RESOURCE_DESC.initBuffer(3 * @sizeOf(vm.Vec3)),
        d3d12.RESOURCE_STATE_COPY_DEST,
        null,
    ) catch |err| hrPanic(err);

    const index_buffer = grfx.createCommittedResource(
        .DEFAULT,
        d3d12.HEAP_FLAG_NONE,
        &d3d12.RESOURCE_DESC.initBuffer(3 * @sizeOf(u32)),
        d3d12.RESOURCE_STATE_COPY_DEST,
        null,
    ) catch |err| hrPanic(err);

    grfx.beginFrame();

    var gui = GuiRenderer.init(arena_allocator, &grfx, 1, content_dir);
    defer gui.deinit(&grfx);

    const upload_verts = grfx.allocateUploadBufferRegion(vm.Vec3, 3);
    upload_verts.cpu_slice[0] = vm.Vec3.init(-0.7, -0.7, 0.0);
    upload_verts.cpu_slice[1] = vm.Vec3.init(0.0, 0.7, 0.0);
    upload_verts.cpu_slice[2] = vm.Vec3.init(0.7, -0.7, 0.0);

    grfx.cmdlist.CopyBufferRegion(
        grfx.lookupResource(vertex_buffer).?,
        0,
        upload_verts.buffer,
        upload_verts.buffer_offset,
        upload_verts.cpu_slice.len * @sizeOf(vm.Vec3),
    );

    const upload_indices = grfx.allocateUploadBufferRegion(u32, 3);
    upload_indices.cpu_slice[0] = 0;
    upload_indices.cpu_slice[1] = 1;
    upload_indices.cpu_slice[2] = 2;

    grfx.cmdlist.CopyBufferRegion(
        grfx.lookupResource(index_buffer).?,
        0,
        upload_indices.buffer,
        upload_indices.buffer_offset,
        upload_indices.cpu_slice.len * @sizeOf(u32),
    );

    grfx.addTransitionBarrier(vertex_buffer, d3d12.RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER);
    grfx.addTransitionBarrier(index_buffer, d3d12.RESOURCE_STATE_INDEX_BUFFER);
    grfx.flushResourceBarriers();

    grfx.endFrame();
    grfx.finishGpuCommands();

    var triangle_color = vm.Vec3.init(0.0, 1.0, 0.0);

    var stats = common.FrameStats.init();

    while (true) {
        var message = std.mem.zeroes(w.user32.MSG);
        const has_message = w.user32.peekMessageA(&message, null, 0, 0, w.user32.PM_REMOVE) catch unreachable;
        if (has_message) {
            _ = w.user32.translateMessage(&message);
            _ = w.user32.dispatchMessageA(&message);
            if (message.message == w.user32.WM_QUIT) {
                break;
            }
        } else {
            stats.update(window, window_name);
            common.newImGuiFrame(stats.delta_time);

            c.igSetNextWindowPos(.{ .x = 10.0, .y = 10.0 }, c.ImGuiCond_FirstUseEver, .{ .x = 0.0, .y = 0.0 });
            c.igSetNextWindowSize(c.ImVec2{ .x = 600.0, .y = 0.0 }, c.ImGuiCond_FirstUseEver);
            _ = c.igBegin(
                "Demo Settings",
                null,
                c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoResize | c.ImGuiWindowFlags_NoSavedSettings,
            );
            _ = c.igColorEdit3("Triangle color", &triangle_color.c, c.ImGuiColorEditFlags_None);
            c.igEnd();

            grfx.beginFrame();

            const back_buffer = grfx.getBackBuffer();

            grfx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATE_RENDER_TARGET);
            grfx.flushResourceBarriers();

            grfx.cmdlist.OMSetRenderTargets(
                1,
                &[_]d3d12.CPU_DESCRIPTOR_HANDLE{back_buffer.descriptor_handle},
                w.TRUE,
                null,
            );
            grfx.cmdlist.ClearRenderTargetView(
                back_buffer.descriptor_handle,
                &[4]f32{ 0.2, 0.4, 0.8, 1.0 },
                0,
                null,
            );
            grfx.setCurrentPipeline(pipeline);
            grfx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
            grfx.cmdlist.IASetVertexBuffers(0, 1, &[_]d3d12.VERTEX_BUFFER_VIEW{.{
                .BufferLocation = grfx.lookupResource(vertex_buffer).?.GetGPUVirtualAddress(),
                .SizeInBytes = 3 * @sizeOf(vm.Vec3),
                .StrideInBytes = @sizeOf(vm.Vec3),
            }});
            grfx.cmdlist.IASetIndexBuffer(&.{
                .BufferLocation = grfx.lookupResource(index_buffer).?.GetGPUVirtualAddress(),
                .SizeInBytes = 3 * @sizeOf(u32),
                .Format = .R32_UINT,
            });
            grfx.cmdlist.SetGraphicsRoot32BitConstant(
                0,
                c.igColorConvertFloat4ToU32(
                    .{ .x = triangle_color.c[0], .y = triangle_color.c[1], .z = triangle_color.c[2], .w = 1.0 },
                ),
                0,
            );
            grfx.cmdlist.DrawIndexedInstanced(3, 1, 0, 0, 0);

            gui.draw(&grfx);

            grfx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATE_PRESENT);
            grfx.flushResourceBarriers();

            grfx.endFrame();
        }
    }

    grfx.finishGpuCommands();
}
