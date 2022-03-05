const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL.h");
    @cInclude("SDL_image.h");
});

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

    const image = sdl.IMG_Load(args[1]);
    if (image == null) {
        std.log.err("IMG_Load failed: {s}", .{sdl.IMG_GetError()});
        return;
    }
    defer sdl.SDL_FreeSurface(image);

    const window = sdl.SDL_CreateWindow(
        "Image Viewer",
        sdl.SDL_WINDOWPOS_UNDEFINED,
        sdl.SDL_WINDOWPOS_UNDEFINED,
        image.*.w,
        image.*.h,
        sdl.SDL_WINDOW_RESIZABLE);
    defer sdl.SDL_DestroyWindow(window);

    const renderer = sdl.SDL_CreateRenderer(window, -1, 0);
    defer sdl.SDL_DestroyRenderer(renderer);

    const texture = sdl.SDL_CreateTextureFromSurface(renderer, image);
    defer sdl.SDL_DestroyTexture(texture);

    var rendered: bool = false;

    // loop until window is close
    mainloop: while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => break :mainloop,
                else => {},
            }
        }

        if (!rendered) {
            _ = sdl.SDL_RenderCopy(renderer, texture, null, null);
            _ = sdl.SDL_RenderPresent(renderer);
            rendered = false;
        }

        sdl.SDL_Delay(@divTrunc(1000, 60));
    }
}
