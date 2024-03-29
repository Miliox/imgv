const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL.h");
    @cInclude("SDL_image.h");
    @cInclude("SDL_syswm.h");
});

const assert = std.debug.assert;

const FitMode = enum { FitIn, FitOut, Stretch };

fn fit_rect(fit_mode: FitMode, window_width: i32, window_height: i32, image_width: i32, image_height: i32) sdl.SDL_Rect {
    switch (fit_mode) {
        FitMode.Stretch => {
            return sdl.SDL_Rect{ .x = 0, .y = 0, .w = window_width, .h = window_height };
        },
        FitMode.FitIn, FitMode.FitOut => {
            const win_width = @intToFloat(f64, window_width);
            const win_height = @intToFloat(f64, window_height);

            const img_width = @intToFloat(f64, image_width);
            const img_height = @intToFloat(f64, image_height);
            const img_ratio = img_width / img_height;

            const img_width_to_fit_window_height = @floatToInt(i32, win_height * img_ratio);
            const img_height_to_fit_window_width = @floatToInt(i32, win_width / img_ratio);

            var is_image_anchor_image_to_window_width_otherwise_window_height = img_height_to_fit_window_width <= window_height;

            if (fit_mode == FitMode.FitOut) {
                is_image_anchor_image_to_window_width_otherwise_window_height =
                    !is_image_anchor_image_to_window_width_otherwise_window_height;
            }

            const fit_width: i32 = if (is_image_anchor_image_to_window_width_otherwise_window_height)
                window_width
            else
                img_width_to_fit_window_height;

            const fit_height: i32 = if (is_image_anchor_image_to_window_width_otherwise_window_height)
                img_height_to_fit_window_width
            else
                window_height;

            return sdl.SDL_Rect{
                .x = @divTrunc((window_width - fit_width), 2),
                .y = @divTrunc((window_height - fit_height), 2),
                .w = fit_width,
                .h = fit_height,
            };
        },
    }
}

pub fn main() anyerror!void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_instance.deinit();

    const arena = arena_instance.allocator();
    const args = try std.process.argsAlloc(arena);

    if (args.len != 2) {
        std.log.info("Usage: {s} IMAGE_FILE", .{args[0]});
        return;
    }

    const sdl_init_result: c_int = sdl.SDL_Init(sdl.SDL_INIT_VIDEO);
    defer sdl.SDL_Quit();

    if (sdl_init_result != 0) {
        std.log.err("SDL_Init failed: {s}", .{sdl.SDL_GetError()});
        return;
    }

    const img_init_flags = sdl.IMG_INIT_JPG | sdl.IMG_INIT_PNG;
    const img_init_result = sdl.IMG_Init(img_init_flags);
    defer sdl.IMG_Quit();

    if ((img_init_result & img_init_flags) != img_init_flags) {
        std.log.err("IMG_Init failed: {s}", .{sdl.IMG_GetError()});
        return;
    }

    const image = sdl.IMG_Load(@ptrCast([*c]u8, args[1]));
    if (image == null) {
        std.log.err("IMG_Load failed: {s}", .{sdl.IMG_GetError()});
        return;
    }
    defer sdl.SDL_FreeSurface(image);

    const last_directory_separator_in_path: ?usize = std.mem.lastIndexOf(u8, args[1], "/");

    const filename: [:0]u8 = if (last_directory_separator_in_path != null)
        args[1][(last_directory_separator_in_path.? + 1)..]
    else
        args[1];

    // other configurations
    assert(1 == sdl.SDL_SetHint(sdl.SDL_HINT_RENDER_SCALE_QUALITY, "best"));
    assert(1 == sdl.SDL_SetHint(sdl.SDL_HINT_RENDER_VSYNC, "1"));
    assert(1 == sdl.SDL_SetHint(sdl.SDL_HINT_VIDEO_ALLOW_SCREENSAVER, "1"));

    const window = sdl.SDL_CreateWindow(@ptrCast([*c]u8, filename), sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED, image.*.w, image.*.h, sdl.SDL_WINDOW_RESIZABLE);
    defer sdl.SDL_DestroyWindow(window);

    const renderer_flags = sdl.SDL_RENDERER_ACCELERATED | sdl.SDL_RENDERER_PRESENTVSYNC;
    const renderer = sdl.SDL_CreateRenderer(window, -1, renderer_flags);
    defer sdl.SDL_DestroyRenderer(renderer);

    const texture = sdl.SDL_CreateTextureFromSurface(renderer, image);
    defer sdl.SDL_DestroyTexture(texture);

    var info = sdl.SDL_SysWMinfo{ .version = sdl.SDL_version{ .major = sdl.SDL_MAJOR_VERSION, .minor = sdl.SDL_MINOR_VERSION, .patch = sdl.SDL_PATCHLEVEL }, .subsystem = 0, .info = .{ .cocoa = .{ .window = null } } };

    // Retrieve NSWindow
    assert(1 == sdl.SDL_GetWindowWMInfo(window, &info));
    assert(sdl.SDL_SYSWM_COCOA == info.subsystem);
    std.log.info("SDL_GetWindowWMInfo: version:{?}.{?}.{?}, window:{?}", .{ info.version.major, info.version.minor, info.version.patch, info.info.cocoa.window });

    var redraw = true;
    var fit_mode = FitMode.FitIn;

    // loop until window is close
    mainloop: while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => break :mainloop,
                sdl.SDL_WINDOWEVENT => {
                    switch (event.window.event) {
                        sdl.SDL_WINDOWEVENT_RESIZED, sdl.SDL_WINDOWEVENT_SIZE_CHANGED, sdl.SDL_WINDOWEVENT_EXPOSED => {
                            redraw = true;
                        },
                        else => {},
                    }
                },
                sdl.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        sdl.SDLK_i => {
                            fit_mode = FitMode.FitIn;
                            redraw = true;
                        },
                        sdl.SDLK_o => {
                            fit_mode = FitMode.FitOut;
                            redraw = true;
                        },
                        sdl.SDLK_s => {
                            fit_mode = FitMode.Stretch;
                            redraw = true;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        if (redraw) {
            var window_width: c_int = 0;
            var window_height: c_int = 0;
            sdl.SDL_GetWindowSize(window, &window_width, &window_height);

            const dst_rect = fit_rect(fit_mode, window_width, window_height, image.*.w, image.*.h);

            assert(0 == sdl.SDL_RenderClear(renderer));
            assert(0 == sdl.SDL_RenderCopy(renderer, texture, null, &dst_rect));
            sdl.SDL_RenderPresent(renderer);
            redraw = false;
        }

        sdl.SDL_Delay(@divTrunc(1000, 60));
    }
}
