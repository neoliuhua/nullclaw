//! Desktop application entrypoint — sdl3-standalone mode.
//! Build: zig build desktop
//!
//! Linux: SDL3 works with both X11 and Wayland (GNOME/Mutter).
//!        Set SDL_VIDEODRIVER=wayland or x11 to force one.

const std = @import("std");
const dvui = @import("dvui");
const SDLBackend = @import("sdl-backend");
const app_ui = @import("ui/desktop_app.zig");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

var g_state: app_ui.AppState = .{};

pub fn main() !void {
    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");

    // init SDL backend (creates and owns the OS window)
    var backend = try SDLBackend.initWindow(.{
        .allocator = gpa,
        .size = .{ .w = 1024.0, .h = 680.0 },
        .min_size = .{ .w = 640.0, .h = 480.0 },
        .vsync = true,
        .title = "nullclaw",
    });
    defer backend.deinit();

    // init dvui Window (maps onto the OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    var interrupted = false;

    main_loop: while (true) {
        const nstime = win.beginWait(interrupted);
        try win.begin(nstime);

        try backend.addAllEvents(&win);

        // clear background
        _ = SDLBackend.c.SDL_SetRenderDrawColor(backend.renderer, 0xF2, 0xF3, 0xF7, 0xFF);
        _ = SDLBackend.c.SDL_RenderClear(backend.renderer);

        const keep_running = try app_ui.frame(&g_state);
        if (!keep_running) break :main_loop;

        const end_micros = try win.end(.{});

        try backend.setCursor(win.cursorRequested());
        try backend.textInputRect(win.textInputRequested());
        try backend.renderPresent();

        const wait_event_micros = win.waitTime(end_micros);
        interrupted = try backend.waitEventTimeout(wait_event_micros);
    }
}
