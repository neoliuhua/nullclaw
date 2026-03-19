//! DesktopChannel — native desktop GUI channel (dvui sdl3-standalone).
//!
//! Implements the Channel vtable. `start()` opens the OS window and runs
//! the dvui event loop on the calling thread (blocking until the window
//! is closed). Outbound messages queued via `send()` are picked up by the
//! UI on the next frame.
//!
//! Platform support:
//!   Windows  — Win32 + SDL3
//!   Linux    — SDL3 → X11 or Wayland (GNOME/Mutter compositor)
//!   macOS    — SDL3 + Metal

const builtin = @import("builtin");
const std = @import("std");
const Channel = @import("root.zig").Channel;
const log = std.log.scoped(.desktop_channel);

// ── Config ────────────────────────────────────────────────────────────────────

pub const DesktopConfig = struct {
    title: [:0]const u8 = "nullclaw",
    width: f32 = 1024,
    height: f32 = 680,
    model_label: []const u8 = "stepfun/step-3.5-flash:free",
};

// ── Channel implementation ────────────────────────────────────────────────────

pub const DesktopChannel = struct {
    allocator: std.mem.Allocator,
    config: DesktopConfig,
    pending_mu: std.Thread.Mutex = .{},
    pending: std.ArrayListUnmanaged([]u8) = .empty,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    const vtable = Channel.VTable{
        .start = start,
        .stop = stop,
        .send = send,
        .name = name,
        .healthCheck = healthCheck,
    };

    pub fn init(allocator: std.mem.Allocator, config: DesktopConfig) DesktopChannel {
        return .{ .allocator = allocator, .config = config };
    }

    pub fn deinit(self: *DesktopChannel) void {
        self.pending_mu.lock();
        defer self.pending_mu.unlock();
        for (self.pending.items) |msg| self.allocator.free(msg);
        self.pending.deinit(self.allocator);
    }

    pub fn channel(self: *DesktopChannel) Channel {
        return .{ .ptr = self, .vtable = &vtable };
    }

    // ── vtable ────────────────────────────────────────────────────────────

    fn start(ptr: *anyopaque) anyerror!void {
        const self: *DesktopChannel = @ptrCast(@alignCast(ptr));
        if (builtin.is_test) return;
        self.running.store(true, .release);
        defer self.running.store(false, .release);
        try runEventLoop(self);
    }

    fn stop(ptr: *anyopaque) void {
        const self: *DesktopChannel = @ptrCast(@alignCast(ptr));
        self.running.store(false, .release);
    }

    fn send(ptr: *anyopaque, _: []const u8, message: []const u8, _: []const []const u8) anyerror!void {
        const self: *DesktopChannel = @ptrCast(@alignCast(ptr));
        const copy = try self.allocator.dupe(u8, message);
        self.pending_mu.lock();
        defer self.pending_mu.unlock();
        try self.pending.append(self.allocator, copy);
    }

    fn name(_: *anyopaque) []const u8 {
        return "desktop";
    }

    fn healthCheck(ptr: *anyopaque) bool {
        const self: *DesktopChannel = @ptrCast(@alignCast(ptr));
        return self.running.load(.acquire);
    }
};

// ── Event loop ────────────────────────────────────────────────────────────────

fn runEventLoop(self: *DesktopChannel) !void {
    const dvui = @import("../dvui");
    const SDLBackend = @import("sdl-backend");
    const app_ui = @import("../ui/desktop_app.zig");

    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_instance.deinit();
    const alloc = gpa_instance.allocator();

    var backend = try SDLBackend.initWindow(.{
        .allocator = alloc,
        .size = .{ .w = self.config.width, .h = self.config.height },
        .min_size = .{ .w = 640, .h = 480 },
        .vsync = true,
        .title = self.config.title,
    });
    defer backend.deinit();

    var win = try dvui.Window.init(@src(), alloc, backend.backend(), .{});
    defer win.deinit();

    var state = app_ui.AppState{
        .model_label = self.config.model_label,
    };

    var interrupted = false;

    while (self.running.load(.acquire)) {
        const nstime = win.beginWait(interrupted);
        try win.begin(nstime);
        try backend.addAllEvents(&win);

        _ = SDLBackend.c.SDL_SetRenderDrawColor(backend.renderer, 0xF2, 0xF3, 0xF7, 0xFF);
        _ = SDLBackend.c.SDL_RenderClear(backend.renderer);

        const keep_running = try app_ui.frame(&state);
        if (!keep_running) break;

        const end_micros = try win.end(.{});
        try backend.setCursor(win.cursorRequested());
        try backend.textInputRect(win.textInputRequested());
        try backend.renderPresent();

        const wait_micros = win.waitTime(end_micros);
        interrupted = try backend.waitEventTimeout(wait_micros);
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test "desktop channel name" {
    var ch = DesktopChannel.init(std.testing.allocator, .{});
    defer ch.deinit();
    try std.testing.expectEqualStrings("desktop", ch.channel().name());
}

test "desktop channel send queues message" {
    var ch = DesktopChannel.init(std.testing.allocator, .{});
    defer ch.deinit();
    try ch.channel().send("user", "hello", &.{});
    ch.pending_mu.lock();
    defer ch.pending_mu.unlock();
    try std.testing.expectEqual(@as(usize, 1), ch.pending.items.len);
    try std.testing.expectEqualStrings("hello", ch.pending.items[0]);
}

test "desktop channel health check false before start" {
    var ch = DesktopChannel.init(std.testing.allocator, .{});
    defer ch.deinit();
    try std.testing.expect(!ch.channel().healthCheck());
}
