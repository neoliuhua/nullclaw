//! Desktop UI — renders the main application window using dvui (sdl3-standalone).
//!
//! Layout mirrors the screenshot:
//!   - Left sidebar (~180px): nav items + bottom settings
//!   - Top bar: model selector + window controls
//!   - Center: logo + title + subtitle + input box + quick-action chips
//!
//! `frame()` is called once per render loop iteration between win.begin/win.end.
//! Returns false when the user requests quit.

const std = @import("std");
const dvui = @import("dvui");

// ── Palette ───────────────────────────────────────────────────────────────────

const C = struct {
    const bg = dvui.Color{ .r = 0xF2, .g = 0xF3, .b = 0xF7, .a = 0xFF };
    const sidebar = dvui.Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0xFF };
    const sidebar_active = dvui.Color{ .r = 0xE8, .g = 0xF0, .b = 0xFE, .a = 0xFF };
    const sidebar_active_text = dvui.Color{ .r = 0x18, .g = 0x65, .b = 0xF1, .a = 0xFF };
    const text = dvui.Color{ .r = 0x1A, .g = 0x1A, .b = 0x2E, .a = 0xFF };
    const text_dim = dvui.Color{ .r = 0x6B, .g = 0x7A, .b = 0x99, .a = 0xFF };
    const border = dvui.Color{ .r = 0xE2, .g = 0xE8, .b = 0xF0, .a = 0xFF };
    const chip_border = dvui.Color{ .r = 0xD1, .g = 0xD9, .b = 0xE6, .a = 0xFF };
    const send = dvui.Color{ .r = 0x4A, .g = 0x9E, .b = 0xF5, .a = 0xFF };
    const send_hover = dvui.Color{ .r = 0x35, .g = 0x8E, .b = 0xE8, .a = 0xFF };
    const logo_bg = dvui.Color{ .r = 0xE8, .g = 0x3A, .b = 0x2A, .a = 0xFF };
    const icon_bg = dvui.Color{ .r = 0xF0, .g = 0xF4, .b = 0xFA, .a = 0xFF };
    const white = dvui.Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0xFF };
};

// ── State ─────────────────────────────────────────────────────────────────────

pub const AppState = struct {
    active_nav: usize = 0,
    input_buf: [1024]u8 = [_]u8{0} ** 1024,
    model_label: []const u8 = "stepfun/step-3.5-flash:free",
    on_submit: ?*const fn (text: []const u8) void = null,
};

// ── Nav data ──────────────────────────────────────────────────────────────────

const NavItem = struct { icon: []const u8, label: []const u8 };
const nav_items = [_]NavItem{
    .{ .icon = "✎", .label = "新建任务" },
    .{ .icon = "⌕", .label = "搜索任务" },
    .{ .icon = "◷", .label = "定时任务" },
    .{ .icon = "✦", .label = "技能" },
    .{ .icon = "⬡", .label = "MCP" },
    .{ .icon = "≡", .label = "任务记录" },
};
const quick_chips = [_][]const u8{ "制作幻灯片", "数据分析", "教育学习", "创建网站" };

// ── Main frame ────────────────────────────────────────────────────────────────

/// Called once per render frame between win.begin/win.end.
/// Returns false when the user wants to quit.
pub fn frame(state: *AppState) !bool {
    // Check quit events first
    for (dvui.events()) |*e| {
        if (e.evt == .window and e.evt.window.action == .close) return false;
        if (e.evt == .app and e.evt.app.action == .quit) return false;
    }

    // Root horizontal box: sidebar | main
    var root = dvui.box(@src(), .{ .dir = .horizontal }, .{
        .expand = .both,
        .background = true,
        .color_fill = C.bg,
    });
    defer root.deinit();

    try sidebar(state);
    try mainArea(state);

    return true;
}

// ── Sidebar ───────────────────────────────────────────────────────────────────

fn sidebar(state: *AppState) !void {
    var sb = dvui.box(@src(), .{ .dir = .vertical }, .{
        .min_size_content = .{ .w = 180 },
        .expand = .vertical,
        .background = true,
        .color_fill = C.sidebar,
        .border = .{ .w = 1 },
        .color_border = C.border,
        .padding = .{ .x = 8, .y = 12, .w = 8, .h = 12 },
    });
    defer sb.deinit();

    // Collapse toggle
    dvui.labelNoFmt(@src(), "⊟", .{}, .{ .color_text = C.text_dim, .font = .{ .size = 16 } });

    dvui.spacer(@src(), .{}, .{ .min_size_content = .{ .h = 8 } });

    // Nav items
    for (nav_items, 0..) |item, i| {
        const active = state.active_nav == i;
        const fg = if (active) C.sidebar_active_text else C.text;
        const fill = if (active) C.sidebar_active else C.sidebar;

        var row = dvui.box(@src(), .{ .dir = .horizontal, .id_extra = i }, .{
            .expand = .horizontal,
            .background = true,
            .color_fill = fill,
            .corner_radius = dvui.Rect.all(6),
            .padding = .{ .x = 10, .y = 6, .w = 10, .h = 6 },
            .margin = .{ .y = 2, .h = 2 },
            .cursor = .hand,
        });
        defer row.deinit();

        // Detect click on the row
        for (dvui.events()) |*e| {
            if (!dvui.eventMatchSimple(e, row.data())) continue;
            if (e.evt == .mouse and e.evt.mouse.action == .press and e.evt.mouse.button == .left) {
                e.handle(@src(), row.data());
                state.active_nav = i;
            }
        }

        dvui.labelNoFmt(@src(), item.icon, .{ .id_extra = i }, .{
            .color_text = fg,
            .font = .{ .size = 13 },
        });
        dvui.spacer(@src(), .{ .id_extra = i }, .{ .min_size_content = .{ .w = 8 } });
        dvui.labelNoFmt(@src(), item.label, .{ .id_extra = i }, .{
            .color_text = fg,
            .font = .{ .size = 13 },
        });
    }

    dvui.spacer(@src(), .{}, .{ .min_size_content = .{ .h = 12 } });

    // Recent task
    {
        var col = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .horizontal,
            .padding = .{ .x = 10, .y = 4, .w = 10, .h = 4 },
        });
        defer col.deinit();
        dvui.labelNoFmt(@src(), "如何每日汇总出最新的AI相...", .{}, .{
            .color_text = C.text,
            .font = .{ .size = 12 },
        });
        dvui.labelNoFmt(@src(), "1d  已完成", .{}, .{
            .color_text = C.text_dim,
            .font = .{ .size = 11 },
        });
    }

    // Push settings to bottom
    dvui.spacer(@src(), .{}, .{ .expand = .vertical });

    // Settings row
    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .expand = .horizontal,
            .padding = .{ .x = 10, .y = 6, .w = 10, .h = 6 },
            .cursor = .hand,
        });
        defer row.deinit();
        dvui.labelNoFmt(@src(), "⚙", .{}, .{ .color_text = C.text_dim, .font = .{ .size = 14 } });
        dvui.spacer(@src(), .{}, .{ .min_size_content = .{ .w = 8 } });
        dvui.labelNoFmt(@src(), "设置", .{}, .{ .color_text = C.text_dim, .font = .{ .size = 13 } });
    }
}

// ── Main area ─────────────────────────────────────────────────────────────────

fn mainArea(state: *AppState) !void {
    var col = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .both,
        .background = true,
        .color_fill = C.bg,
    });
    defer col.deinit();

    try topBar(state);
    try centerContent(state);
}

// ── Top bar ───────────────────────────────────────────────────────────────────

fn topBar(state: *AppState) !void {
    var bar = dvui.box(@src(), .{ .dir = .horizontal }, .{
        .expand = .horizontal,
        .min_size_content = .{ .h = 40 },
        .background = true,
        .color_fill = C.white,
        .border = .{ .h = 1 },
        .color_border = C.border,
        .padding = .{ .x = 16, .y = 0, .w = 16, .h = 0 },
    });
    defer bar.deinit();

    // Model label
    {
        var lbl_buf: [128]u8 = undefined;
        const lbl = std.fmt.bufPrint(&lbl_buf, "{s}  ▾", .{state.model_label}) catch state.model_label;
        dvui.labelNoFmt(@src(), lbl, .{}, .{
            .color_text = C.text,
            .font = .{ .size = 13 },
            .gravity_y = 0.5,
        });
    }

    dvui.spacer(@src(), .{}, .{ .expand = .horizontal });

    // Window control dots (minimize / maximize / close)
    inline for (.{
        dvui.Color{ .r = 0xFF, .g = 0xBD, .b = 0x2E, .a = 0xFF }, // yellow  – minimize
        dvui.Color{ .r = 0x28, .g = 0xC9, .b = 0x40, .a = 0xFF }, // green   – maximize
        dvui.Color{ .r = 0xFF, .g = 0x5F, .b = 0x57, .a = 0xFF }, // red     – close
    }, 0..) |dot_color, di| {
        dvui.spacer(@src(), .{ .id_extra = di }, .{ .min_size_content = .{ .w = 6 } });
        var dot = dvui.box(@src(), .{ .dir = .horizontal, .id_extra = di }, .{
            .min_size_content = .{ .w = 12, .h = 12 },
            .background = true,
            .color_fill = dot_color,
            .corner_radius = dvui.Rect.all(6),
            .gravity_y = 0.5,
            .cursor = .hand,
        });
        dot.deinit();
    }
}

// ── Center content ────────────────────────────────────────────────────────────

fn centerContent(state: *AppState) !void {
    // Outer scroll area so content stays centered even when window is small
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();

    // Vertical centering wrapper
    var outer = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .both,
        .gravity_x = 0.5,
        .gravity_y = 0.5,
    });
    defer outer.deinit();

    dvui.spacer(@src(), .{}, .{ .expand = .vertical });

    // ── Logo ──────────────────────────────────────────────────────────────
    {
        var logo = dvui.box(@src(), .{ .dir = .vertical }, .{
            .min_size_content = .{ .w = 64, .h = 64 },
            .background = true,
            .color_fill = C.logo_bg,
            .corner_radius = dvui.Rect.all(16),
            .padding = dvui.Rect.all(12),
            .gravity_x = 0.5,
            .margin = .{ .h = 16 },
        });
        defer logo.deinit();
        dvui.labelNoFmt(@src(), "🦞", .{}, .{
            .font = .{ .size = 32 },
            .gravity_x = 0.5,
            .gravity_y = 0.5,
        });
    }

    // ── Title ─────────────────────────────────────────────────────────────
    dvui.labelNoFmt(@src(), "开始协作", .{}, .{
        .color_text = C.text,
        .font = .{ .size = 24 },
        .gravity_x = 0.5,
        .margin = .{ .h = 8 },
    });

    // ── Subtitle ──────────────────────────────────────────────────────────
    dvui.labelNoFmt(@src(), "7×24 小时帮你干活的全场景个人助理 Agent", .{}, .{
        .color_text = C.text_dim,
        .font = .{ .size = 13 },
        .gravity_x = 0.5,
        .margin = .{ .h = 24 },
    });

    // ── Input card ────────────────────────────────────────────────────────
    try inputCard(state);

    // ── Quick-action chips ────────────────────────────────────────────────
    dvui.spacer(@src(), .{}, .{ .min_size_content = .{ .h = 16 } });
    try quickChips();

    dvui.spacer(@src(), .{}, .{ .expand = .vertical });
}

// ── Input card ────────────────────────────────────────────────────────────────

fn inputCard(state: *AppState) !void {
    var card = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .horizontal,
        .max_size_content = .{ .w = 560 },
        .gravity_x = 0.5,
        .background = true,
        .color_fill = C.white,
        .corner_radius = dvui.Rect.all(12),
        .border = dvui.Rect.all(1),
        .color_border = C.border,
        .padding = .{ .x = 16, .y = 12, .w = 16, .h = 12 },
    });
    defer card.deinit();

    // Text entry
    var te = dvui.textEntry(@src(), .{
        .text = .{ .buffer = &state.input_buf },
        .placeholder = "分配一个任务或提问任何问题",
    }, .{
        .expand = .horizontal,
        .min_size_content = .{ .h = 48 },
        .border = .{},
        .background = false,
        .color_text = C.text,
        .color_text_hint = C.text_dim,
        .font = .{ .size = 14 },
    });
    te.deinit();

    // Toolbar row
    {
        var toolbar = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .expand = .horizontal,
            .padding = .{ .y = 8 },
        });
        defer toolbar.deinit();

        // Left icon buttons
        inline for (.{ "▤", "⊕", "☺" }, 0..) |icon, ii| {
            if (dvui.button(@src(), icon, .{ .id_extra = ii }, .{
                .min_size_content = .{ .w = 28, .h = 28 },
                .corner_radius = dvui.Rect.all(6),
                .color_fill = C.icon_bg,
                .color_fill_hover = dvui.Color{ .r = 0xE2, .g = 0xE8, .b = 0xF5, .a = 0xFF },
                .color_text = C.text_dim,
                .border = .{},
                .font = .{ .size = 14 },
                .margin = .{ .w = 4 },
            })) {}
        }

        dvui.spacer(@src(), .{}, .{ .expand = .horizontal });

        // Send button
        if (dvui.button(@src(), "▶", .{}, .{
            .min_size_content = .{ .w = 32, .h = 32 },
            .corner_radius = dvui.Rect.all(8),
            .color_fill = C.send,
            .color_fill_hover = C.send_hover,
            .color_text = C.white,
            .border = .{},
            .font = .{ .size = 14 },
        })) {
            if (state.on_submit) |cb| {
                const len = std.mem.indexOfScalar(u8, &state.input_buf, 0) orelse state.input_buf.len;
                cb(state.input_buf[0..len]);
            }
            @memset(&state.input_buf, 0);
        }
    }
}

// ── Quick-action chips ────────────────────────────────────────────────────────

fn quickChips() !void {
    var row = dvui.box(@src(), .{ .dir = .horizontal }, .{
        .gravity_x = 0.5,
    });
    defer row.deinit();

    inline for (quick_chips, 0..) |chip, ci| {
        if (ci > 0) dvui.spacer(@src(), .{ .id_extra = ci }, .{ .min_size_content = .{ .w = 8 } });
        _ = dvui.button(@src(), chip, .{ .id_extra = ci }, .{
            .corner_radius = dvui.Rect.all(20),
            .color_fill = C.white,
            .color_fill_hover = dvui.Color{ .r = 0xF0, .g = 0xF4, .b = 0xFF, .a = 0xFF },
            .color_text = C.text,
            .border = dvui.Rect.all(1),
            .color_border = C.chip_border,
            .font = .{ .size = 13 },
            .padding = .{ .x = 14, .y = 7, .w = 14, .h = 7 },
        });
    }
}
