const std = @import("std");
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const sdl = @import("./sdl.zig");
const c = sdl.c;

const ecs = @import("ecs");

// Starting width and height of the game screen
const WIDTH = 712;
const HEIGHT = 512;

pub fn main() !void {
    // SDL initialization
    // SDL handling SIGINT blocks propagation to child threads.
    if (!(sdl.c.SDL_SetHintWithPriority(sdl.c.SDL_HINT_NO_SIGNAL_HANDLERS, "1", sdl.c.SDL_HintPriority.SDL_HINT_OVERRIDE) != sdl.c.SDL_bool.SDL_FALSE)) {
        std.debug.panic("failed to disable sdl signal handlers\n", .{});
    }
    if (sdl.c.SDL_Init(sdl.c.SDL_INIT_VIDEO) != 0) {
        std.debug.panic("SDL_Init failed: {}\n", .{sdl.c.SDL_GetError()});
    }
    defer sdl.c.SDL_Quit();

    // Create the game screen and renderer
    const screen = sdl.c.SDL_CreateWindow(
        "Pong",
        sdl.SDL_WINDOWPOS_UNDEFINED,
        sdl.SDL_WINDOWPOS_UNDEFINED,
        WIDTH,
        HEIGHT,
        sdl.c.SDL_WINDOW_RESIZABLE,
    ) orelse {
        std.debug.panic("SDL_CreateWindow failed: {}\n", .{sdl.c.SDL_GetError()});
    };
    defer sdl.c.SDL_DestroyWindow(screen);
    const renderer: *sdl.Renderer = sdl.c.SDL_CreateRenderer(screen, -1, 0) orelse {
        std.debug.panic("SDL_CreateRenderer failed: {}\n", .{sdl.c.SDL_GetError()});
    };
    defer sdl.c.SDL_DestroyRenderer(renderer);

    // ECS initialization
    const Position = struct { x: u32, y: u32 };
    var gpa = GeneralPurposeAllocator(.{}){};
    var allocator = &gpa.allocator;
    var world = try ecs.World.init(allocator, .{Position});
    defer world.deinit();

    doMainLoop(world);
}

// Yay main loop time!
fn doMainLoop(world: ecs.World) void {
    var event: c.SDL_Event = undefined;
    while (true) {
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                c.SDL_QUIT => return,
                else => {},
            }
        }
    }
}
