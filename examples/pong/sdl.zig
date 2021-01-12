const std = @import("std");
const sdl = @This();

// this is technically all we need
pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
// but for convenience, we'll publish some special case wrappers/aliases
// to isolate the quirks of using a C api from zig.

// See https://github.com/zig-lang/zig/issues/565
// SDL_video.h:#define SDL_WINDOWPOS_UNDEFINED         SDL_WINDOWPOS_UNDEFINED_DISPLAY(0)
// SDL_video.h:#define SDL_WINDOWPOS_UNDEFINED_DISPLAY(X)  (SDL_WINDOWPOS_UNDEFINED_MASK|(X))
// SDL_video.h:#define SDL_WINDOWPOS_UNDEFINED_MASK    0x1FFF0000u
pub const SDL_WINDOWPOS_UNDEFINED = @bitCast(c_int, c.SDL_WINDOWPOS_UNDEFINED_MASK);

pub extern fn SDL_PollEvent(event: *c.SDL_Event) c_int;

pub extern fn SDL_RenderCopy(
    renderer: *c.SDL_Renderer,
    texture: *c.SDL_Texture,
    srcrect: ?*const c.SDL_Rect,
    dstrect: ?*const c.SDL_Rect,
) c_int;

pub extern fn SDL_RenderCopyEx(
    renderer: *c.SDL_Renderer,
    texture: *c.SDL_Texture,
    srcrect: ?*const c.SDL_Rect,
    dstrect: ?*const c.SDL_Rect,
    angle: f64,
    center: ?*const c.SDL_Point,
    flip: c_int, // SDL_RendererFlip
) c_int;
