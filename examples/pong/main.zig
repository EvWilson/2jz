const std = @import("std");
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const sdl = @import("./sdl.zig");
const c = sdl.c;
const ecs = @import("ecs");

const check = sdl.assertZero;

fn renderBlack(renderer: *c.SDL_Renderer) void {
    check(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
}
fn renderWhite(renderer: *c.SDL_Renderer) void {
    check(c.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255));
}

pub fn main() !void {
    // Game constants
    const BALL_WIDTH = 10;
    const BALL_HEIGHT = 10;
    const PADDLE_WIDTH = 5;
    const PADDLE_HEIGHT = 50;
    const SCREEN_WIDTH = 712;
    const SCREEN_HEIGHT = 512;
    // Ensure screen width and height are even or things have the potential to
    // be wonky
    std.debug.assert(SCREEN_WIDTH % 2 == 0 and SCREEN_HEIGHT % 2 == 0);

    // SDL initialization
    // SDL handling SIGINT blocks propagation to child threads.
    if (!(c.SDL_SetHintWithPriority(c.SDL_HINT_NO_SIGNAL_HANDLERS, "1", c.SDL_HintPriority.SDL_HINT_OVERRIDE) != c.SDL_bool.SDL_FALSE)) {
        std.debug.panic("failed to disable sdl signal handlers\n", .{});
    }
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        std.debug.panic("SDL_Init failed: {}\n", .{c.SDL_GetError()});
    }
    defer c.SDL_Quit();

    // Create the game screen and renderer
    const screen: *c.SDL_Window = c.SDL_CreateWindow(
        "Pong",
        sdl.SDL_WINDOWPOS_UNDEFINED,
        sdl.SDL_WINDOWPOS_UNDEFINED,
        SCREEN_WIDTH,
        SCREEN_HEIGHT,
        c.SDL_WINDOW_RESIZABLE,
    ) orelse {
        std.debug.panic("SDL_CreateWindow failed: {}\n", .{c.SDL_GetError()});
    };
    defer c.SDL_DestroyWindow(screen);
    const renderer: *c.SDL_Renderer = c.SDL_CreateRenderer(screen, -1, 0) orelse {
        std.debug.panic("SDL_CreateRenderer failed: {}\n", .{c.SDL_GetError()});
    };
    defer c.SDL_DestroyRenderer(renderer);

    // Component type declarations
    const Movespeed = struct { speed: u32 };
    const Position = struct { x: u32, y: u32 };
    const Size = struct { w: u32, h: u32 };
    const Velocity = struct { dx: u32, dy: u32 };
    // ECS initialization
    var gpa = GeneralPurposeAllocator(.{}){};
    var allocator = &gpa.allocator;
    var world = try ecs.World.init(allocator, .{ Movespeed, Position, Size, Velocity });
    defer world.deinit();

    // Spawn our entities into the world
    // First paddle
    const pos1: Position = .{ .x = 10, .y = 20 };
    const size1: Size = .{ .w = PADDLE_WIDTH, .h = PADDLE_HEIGHT };
    const speed: Movespeed = .{ .speed = 10 };
    var ent1 = try world.spawn(.{ speed, pos1, size1 });
    // Second paddle
    const pos2: Position = .{ .x = SCREEN_WIDTH - 10, .y = 20 };
    const size2: Size = .{ .w = PADDLE_WIDTH, .h = PADDLE_HEIGHT };
    var ent2 = try world.spawn(.{ speed, pos2, size2 });
    // Ball
    const pos3: Position = .{ .x = SCREEN_WIDTH / 2, .y = SCREEN_HEIGHT / 2 };
    const size3: Size = .{ .w = BALL_WIDTH, .h = BALL_HEIGHT };
    const ball_velocity: Velocity = .{ .dx = 5, .dy = 5 };
    var ent3 = try world.spawn(.{ pos3, size3, ball_velocity });

    doMainLoop(world, renderer);
}

// Yay main loop time!
fn doMainLoop(world: ecs.World, renderer: *c.SDL_Renderer) void {
    // Helper struct to hold button states
    const ButtonStates = struct { w: bool, s: bool, up: bool, down: bool };
    var states: ButtonStates = .{ .w = false, .s = false, .up = false, .down = false };

    var event: c.SDL_Event = undefined;
    while (true) {
        // Poll events
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => return,
                else => {},
            }
        }

        renderBlack(renderer);
        check(c.SDL_RenderClear(renderer));

        doSystems(&world);

        c.SDL_RenderPresent(renderer);
        c.SDL_Delay(16);
    }
}

fn doSystems(world: *ecs.World) void {
    // TODO
}
