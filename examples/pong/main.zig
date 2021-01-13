const std = @import("std");
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const ecs = @import("ecs");

// Some minimal boilerplate to get access to SDL
pub const SDL_WINDOWPOS_UNDEFINED = @bitCast(c_int, c.SDL_WINDOWPOS_UNDEFINED_MASK);
pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

// Component type declarations
const Id = struct { id: u32 };
const Movespeed = struct { speed: u32 };
const Position = struct { x: i32, y: i32 };
const Size = struct { w: i32, h: i32 };
const Velocity = struct { dx: i32, dy: i32 };

// Used to pack button information later
const ButtonStates = struct { w: i8, s: i8, up: i8, down: i8 };

// Game constants
const SCREEN_WIDTH = 1280;
const SCREEN_HEIGHT = 720;
const BALL_WIDTH = SCREEN_WIDTH / 20;
const BALL_HEIGHT = SCREEN_WIDTH / 20;
const PADDLE_WIDTH = SCREEN_WIDTH / 30;
const PADDLE_HEIGHT = SCREEN_HEIGHT / 5;
const PADDLE_SPEED: i32 = 10;
const MAX_SCORE: usize = 5;
const SCORE_WIDTH = SCREEN_WIDTH / 10;
const SCORE_HEIGHT = SCREEN_HEIGHT / 5;

var PLAYER1_SCORE: usize = 0;
var PLAYER2_SCORE: usize = 0;

pub fn main() !void {
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
    // Init and load our font
    if (c.TTF_Init() != 0) {
        std.debug.panic("TTF_Init failed: {}\n", .{c.TTF_GetError()});
    }
    defer c.TTF_Quit();
    const font: *c.TTF_Font = c.TTF_OpenFont("font.ttf", 25).?;
    defer c.TTF_CloseFont(font);

    // Create the game screen and renderer
    const screen: *c.SDL_Window = c.SDL_CreateWindow(
        "Pong",
        SDL_WINDOWPOS_UNDEFINED,
        SDL_WINDOWPOS_UNDEFINED,
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

    // ECS initialization
    var gpa = GeneralPurposeAllocator(.{}){};
    var allocator = &gpa.allocator;
    var world: *ecs.World = &(try ecs.World.init(allocator, .{ Id, Movespeed, Position, Size, Velocity }));
    defer world.deinit();

    // Spawn our entities into the world
    // First paddle
    const id1: Id = .{ .id = 1 };
    const pos1: Position = .{ .x = PADDLE_WIDTH / 2, .y = SCREEN_HEIGHT / 2 };
    const size1: Size = .{ .w = PADDLE_WIDTH, .h = PADDLE_HEIGHT };
    const speed: Movespeed = .{ .speed = PADDLE_SPEED };
    var paddle1_ent = try world.spawn(.{ id1, speed, pos1, size1 });

    // Second paddle
    const id2: Id = .{ .id = 2 };
    const pos2: Position = .{ .x = SCREEN_WIDTH - (PADDLE_WIDTH * 1.5), .y = (SCREEN_HEIGHT / 2) - (PADDLE_HEIGHT / 2) };
    const size2: Size = .{ .w = PADDLE_WIDTH, .h = PADDLE_HEIGHT };
    var paddle2_ent = try world.spawn(.{ id2, speed, pos2, size2 });

    // Ball
    const pos3: Position = .{ .x = SCREEN_WIDTH / 2, .y = (SCREEN_HEIGHT / 2) - (PADDLE_HEIGHT / 2) };
    const size3: Size = .{ .w = BALL_WIDTH, .h = BALL_HEIGHT };
    const ball_velocity: Velocity = .{ .dx = 5, .dy = 5 };
    var ball_ent = try world.spawn(.{ pos3, size3, ball_velocity });

    doMainLoop(world, renderer, font);
}

// Yay main loop time!
fn doMainLoop(world: *ecs.World, renderer: *c.SDL_Renderer, font: *c.TTF_Font) void {
    // Helper struct to hold button states
    var states: ButtonStates = .{ .w = 0, .s = 0, .up = 0, .down = 0 };
    var paused: bool = false;

    var event: c.SDL_Event = undefined;
    while (true) {
        // Poll events
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                // Handle inputs
                c.SDL_KEYUP => {
                    switch (@enumToInt(event.key.keysym.scancode)) {
                        c.SDL_SCANCODE_W => states.w = 0,
                        c.SDL_SCANCODE_S => states.s = 0,
                        c.SDL_SCANCODE_UP => states.up = 0,
                        c.SDL_SCANCODE_DOWN => states.down = 0,
                        else => {},
                    }
                },
                c.SDL_KEYDOWN => {
                    switch (@enumToInt(event.key.keysym.scancode)) {
                        c.SDL_SCANCODE_W => states.w = 1,
                        c.SDL_SCANCODE_S => states.s = 1,
                        c.SDL_SCANCODE_UP => states.up = 1,
                        c.SDL_SCANCODE_DOWN => states.down = 1,
                        c.SDL_SCANCODE_SPACE => paused = !paused,
                        else => {},
                    }
                },
                // Handle game exit
                c.SDL_QUIT => return,
                else => {},
            }
        }

        if (!paused) {
            renderBlack(renderer);
            check(c.SDL_RenderClear(renderer));

            doSystems(world, renderer, &states, font);

            // Finish when we reach score limit
            if (PLAYER1_SCORE == MAX_SCORE or PLAYER2_SCORE == MAX_SCORE) {
                break;
            }

            c.SDL_RenderPresent(renderer);
        }

        c.SDL_Delay(16);
    }

    // Log winner
    if (PLAYER1_SCORE == MAX_SCORE) {
        std.debug.print("Player 1 wins!\n", .{});
    } else {
        std.debug.print("Player 2 wins!\n", .{});
    }
}

// Perform all of our lovely ECS-related systems
fn doSystems(world: *ecs.World, renderer: *c.SDL_Renderer, buttons: *const ButtonStates, font: *c.TTF_Font) void {
    movementSystem(world, buttons);
    transformSystem(world);
    collisionSystem(world);
    scoreSystem(world);
    renderSystem(world, renderer, font);
}

// Move the paddles
fn movementSystem(world: *ecs.World, buttons: *const ButtonStates) void {
    var query = world.query(.{ Id, Position }) catch |err| std.debug.panic("Failed to create movement query, error: {}\n", .{err});
    while (query.next()) {
        const id = query.data(Id).id;
        var pos = query.dataMut(Position);

        switch (id) {
            1 => pos.y += @as(@TypeOf(pos.y), (buttons.s - buttons.w) * PADDLE_SPEED),
            2 => pos.y += @as(@TypeOf(pos.y), (buttons.down - buttons.up) * PADDLE_SPEED),
            else => {},
        }

        if (pos.y < 0) {
            pos.y = 0;
        } else if (pos.y > SCREEN_HEIGHT - PADDLE_HEIGHT) {
            pos.y = SCREEN_HEIGHT - PADDLE_HEIGHT;
        }
    }
}

// Move the ball
fn transformSystem(world: *ecs.World) void {
    var query = world.query(.{ Position, Size, Velocity }) catch |err| std.debug.panic("Failed to create transform query, error: {}\n", .{err});
    while (query.next()) {
        var pos = query.dataMut(Position);
        var velocity = query.dataMut(Velocity);

        // Rebound off the top and bottom
        if (pos.y < 0) {
            pos.y = 0;
            velocity.dy *= -1;
        }
        if (pos.y > SCREEN_HEIGHT - BALL_HEIGHT) {
            pos.y = SCREEN_HEIGHT - BALL_HEIGHT;
            velocity.dy *= -1;
        }

        pos.x += velocity.dx;
        pos.y += velocity.dy;
    }
}

// Perform collision checking between the ball and paddles
// When a collision occurs, reverse the ball's direction
fn collisionSystem(world: *ecs.World) void {
    var ball = world.query(.{ Position, Size, Velocity }) catch |err| std.debug.panic("Failed to create ball collision query, error: {}\n", .{err});
    std.testing.expect(ball.next());

    var paddle = world.query(.{ Id, Position, Size }) catch |err| std.debug.panic("Failed to create paddle collision query, error: {}\n", .{err});
    while (paddle.next()) {
        if (isColliding(ball.data(Position), ball.data(Size), paddle.data(Position), paddle.data(Size))) {
            var ball_pos = ball.data(Position);
            if (paddle.data(Id).id == 1) {
                ball_pos.x = paddle.data(Position).x + PADDLE_WIDTH + 1;
            } else {
                ball_pos.x = paddle.data(Position).x - BALL_WIDTH - 1;
            }
            var ball_velocity = ball.dataMut(Velocity);
            ball_velocity.dx *= -1;
        }
    }
}
// Helper function for collision system
fn isColliding(pos1: Position, size1: Size, pos2: Position, size2: Size) bool {
    switch (@enumToInt(c.SDL_HasIntersection(&makeRect(pos1, size1), &makeRect(pos2, size2)))) {
        c.SDL_TRUE => return true,
        c.SDL_FALSE => return false,
        else => std.debug.panic("SDL_HasIntersection returned unhandled case\n", .{}),
    }
}

// Update scores and reset ball
fn scoreSystem(world: *ecs.World) void {
    var query = world.query(.{ Position, Velocity }) catch |err| std.debug.panic("Failed to create score query. error: {}\n", .{err});
    while (query.next()) {
        var pos = query.dataMut(Position);

        if (pos.x + BALL_WIDTH < 0) {
            pos.x = SCREEN_WIDTH / 2;
            pos.y = SCREEN_HEIGHT / 2;
            // Player 2 scores
            PLAYER2_SCORE += 1;
        } else if (pos.x > SCREEN_WIDTH) {
            pos.x = SCREEN_WIDTH / 2;
            pos.y = SCREEN_HEIGHT / 2;
            // Player 1 scores
            PLAYER1_SCORE += 1;
        }
    }
}

// Renders all entities with Position and Size components
fn renderSystem(world: *ecs.World, renderer: *c.SDL_Renderer, font: *c.TTF_Font) void {
    renderWhite(renderer);
    var query = world.query(.{ Position, Size }) catch |err| std.debug.panic("Failed to create query, error: {}\n", .{err});
    while (query.next()) {
        const pos = query.data(Position);
        const size = query.data(Size);

        const rect: *c.SDL_Rect = &makeRect(pos, size);
        check(c.SDL_RenderDrawRect(renderer, rect));
    }

    // Scores
    drawScore(renderer, font, PLAYER1_SCORE, Position{ .x = SCREEN_WIDTH * 0.25, .y = SCREEN_HEIGHT / 20 });
    drawScore(renderer, font, PLAYER2_SCORE, Position{ .x = SCREEN_WIDTH * 0.75, .y = SCREEN_HEIGHT / 20 });
}

// General helper/shorthand functions
fn check(ret: c_int) void {
    if (ret == 0) return;
    std.debug.panic("SDL function returned an error: {}\n", .{c.SDL_GetError()});
}
fn renderBlack(renderer: *c.SDL_Renderer) void {
    check(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255));
}
fn renderWhite(renderer: *c.SDL_Renderer) void {
    check(c.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255));
}
// Icky yucky casting to SDL's C types
fn makeRect(pos: Position, size: Size) c.SDL_Rect {
    return c.SDL_Rect{
        .x = @intCast(c_int, pos.x),
        .y = @intCast(c_int, pos.y),
        .w = @intCast(c_int, size.w),
        .h = @intCast(c_int, size.h),
    };
}
fn drawScore(renderer: *c.SDL_Renderer, font: *c.TTF_Font, score: usize, pos: Position) void {
    var color = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const score_slice = &[_]u8{@intCast(u8, score) + 48};
    var surface: *c.SDL_Surface = c.TTF_RenderText_Solid(font, score_slice, color);
    defer c.SDL_FreeSurface(surface);

    var font_tex: *c.SDL_Texture = c.SDL_CreateTextureFromSurface(renderer, surface).?;
    defer c.SDL_DestroyTexture(font_tex);

    check(c.SDL_RenderCopy(renderer, font_tex, null, &makeRect(Position{ .x = pos.x - SCORE_WIDTH / 2, .y = pos.y - SCORE_HEIGHT / 2 }, Size{ .w = SCORE_WIDTH, .h = SCORE_HEIGHT })));
}
