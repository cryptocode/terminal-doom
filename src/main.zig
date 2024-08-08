//! SPDX-License-Identifier: GPL-2-0 or MIT
const std = @import("std");
const vaxis = @import("vaxis");
const zigimg = vaxis.zigimg;
const Key = vaxis.Key;

/// The events we want vaxis to deliver
const Event = union(enum) {
    key_press: vaxis.Key,
    key_release: vaxis.Key,
    winsize: vaxis.Winsize,
    mouse: vaxis.Mouse,
};

/// Game state
const State = struct {
    // For each key in the queue, Doom expects a word. The upper byte
    // contains the pressed-flag, the lower byte the Doom-specific keycode.
    key_queue: [32]u16,
    key_queue_write_idx: u5,
    key_queue_read_idx: u5,
    startup: i64,
    loop: vaxis.Loop(Event),
    exit_flag: std.atomic.Value(bool),
    mouse_enabled: bool = true,
    last_mouse_x: f32 = std.math.floatMax(f32),
    last_mouse_y: f32 = std.math.floatMax(f32),
    mouse_dir: u21 = 0,
    scale: bool = true,
};

// We feed mouse events directly to Doom:
//
//    data1: Bitfield of buttons currently held down.
//           (bit 0 = left; bit 1 = right; bit 2 = middle).
//    data2: X axis mouse movement (turn).
//    data3: Y axis mouse movement (forward/backward).
//    data4: Not used
const evtype_t = enum(c_int) { ev_keydown, ev_keyup, ev_mouse, ev_joystick, ev_quit };
const event_t = extern struct {
    t: evtype_t,
    data1: c_int,
    data2: c_int,
    data3: c_int,
    data4: c_int,
};

// We use global state as the Doom callbacks don't allow for userdata to be passed.
var state: State = undefined;

// Called by Doom on startup; not needed in our case
pub export fn DG_Init() callconv(.C) void {}

// Called by doomgeneric to draw a single frame
pub export fn DG_DrawFrame() callconv(.C) void {
    // We need to have a window size before continuing
    const win = state.loop.vaxis.window();
    if (win.screen.width == 0) {
        while (state.loop.tryEvent()) |event| {
            switch (event) {
                .winsize => |ws| state.loop.vaxis.resize(std.heap.c_allocator, state.loop.tty.anyWriter(), ws) catch unreachable,
                else => {},
            }
        }
        return;
    }
    translateDoomBufferToRGB();

    var pixels = zigimg.Image{
        .width = 640,
        .height = 400,
        .pixels = zigimg.color.PixelStorage.initRawPixels(&DG_ScreenBuffer_Converted, .rgb24) catch unreachable,
    };

    // Write the image pixels using the Kitty image protocol
    const img = state.loop.vaxis.transmitImage(std.heap.c_allocator, state.loop.tty.anyWriter(), &pixels, .rgb) catch unreachable;

    // Image size measured in cells
    const cell_size = img.cellSize(win) catch unreachable;

    const x_pix: f32 = @floatFromInt(win.screen.width_pix);
    const y_pix: f32 = @floatFromInt(win.screen.height_pix);
    const w: f32 = @floatFromInt(win.screen.width);
    const h: f32 = @floatFromInt(win.screen.height);

    const pix_per_col = x_pix / w;
    const pix_per_row = y_pix / h;

    const aspect_ratio = @as(f32, @floatFromInt(img.width)) / @as(f32, @floatFromInt(img.height));

    // Calculate the maximum allowed width and height based on window dimensions
    const max_width_cells = @max(w, @as(f32, @floatFromInt(cell_size.cols)));
    const max_height_cells = h;

    // Calculate the pixel dimensions for the max width and height
    const max_width_pix = max_width_cells * pix_per_col;
    const max_height_pix = max_height_cells * pix_per_row;

    var final_width_pix: f32 = 0;
    var final_height_pix: f32 = 0;

    // Scale according to the most limiting direction
    if (max_width_pix / aspect_ratio <= max_height_pix) {
        final_width_pix = max_width_pix;
        final_height_pix = final_width_pix / aspect_ratio;
    } else {
        final_height_pix = max_height_pix;
        final_width_pix = final_height_pix * aspect_ratio;
    }

    const final_width_cells = final_width_pix / pix_per_col;
    const final_height_cells = final_height_pix / pix_per_row;

    if (state.scale) {
        img.draw(win, .{ .size = .{
            .rows = @intFromFloat(final_height_cells),
            .cols = @intFromFloat(final_width_cells),
        } }) catch unreachable;
    } else {
        img.draw(win, .{}) catch unreachable;
    }

    while (state.loop.tryEvent()) |event| {
        switch (event) {
            .key_press, .key_release => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    state.exit_flag.store(true, .seq_cst);
                } else if (key.codepoint == 'm' and event == .key_release) {
                    state.mouse_enabled = !state.mouse_enabled;
                } else if (key.codepoint == 'u' and event == .key_release) {
                    state.scale = !state.scale;
                } else {
                    enqueueKey(event == .key_press, key);
                }
            },
            .mouse => |mouse| {
                if (state.mouse_enabled) {
                    // Unscaled screen coordinates
                    var abs_x: f32 = @as(f32, @floatFromInt(mouse.col)) * pix_per_col + @as(f32, @floatFromInt(mouse.xoffset));
                    var abs_y: f32 = @as(f32, @floatFromInt(mouse.row)) * pix_per_row + @as(f32, @floatFromInt(mouse.yoffset));

                    // Scaled coordinates
                    const scalex = doom_width / final_width_pix;
                    const scaley = doom_height / final_height_pix;
                    abs_x *= scalex;
                    abs_y *= scaley;

                    var rel_x: c_int = 0;
                    var rel_y: c_int = 0;

                    if (state.last_mouse_x != std.math.floatMax(f32)) {
                        rel_x = @intFromFloat((abs_x - state.last_mouse_x) / scalex);
                    }
                    state.last_mouse_x = abs_x;

                    if (state.last_mouse_y != std.math.floatMax(f32)) {
                        rel_y = @intFromFloat((abs_y - state.last_mouse_y) / scaley);
                    }
                    state.last_mouse_y = abs_y;

                    var button_state: c_int = 0;
                    if (mouse.button == .left) button_state |= 1;
                    if (mouse.button == .right) button_state |= 2;
                    if (mouse.button == .middle) button_state |= 4;

                    var doom_event: event_t = .{
                        .t = .ev_mouse,
                        .data1 = button_state,
                        .data2 = accelerateMouse(rel_x, 16),
                        .data3 = -accelerateMouse(rel_y, 4),
                        .data4 = 0,
                    };

                    D_PostEvent(&doom_event);
                }
            },
            .winsize => |ws| state.loop.vaxis.resize(std.heap.c_allocator, state.loop.tty.anyWriter(), ws) catch unreachable,
        }
    }

    state.loop.vaxis.render(state.loop.tty.anyWriter()) catch unreachable;
}

fn accelerateMouse(delta: c_int, clamp: f32) c_int {
    const dx: f32 = @floatFromInt(delta);
    return @intFromFloat(dx * @min(clamp, 8 * @exp(@abs(dx))));
}

/// Called by Doom when it needs to sleep
pub export fn DG_SleepMs(ms: c_uint) callconv(.C) void {
    std.time.sleep(ms * std.time.ns_per_ms);
}

/// Called by Doom to get milliseconds passed since startup
pub export fn DG_GetTicksMs() callconv(.C) u32 {
    return @intCast(std.time.milliTimestamp() - state.startup);
}

/// Called by Doom to pull a keypress from the queue. Returns 0 if the queue is empty.
pub export fn DG_GetKey(pressed: [*c]c_int, doom_key: [*c]u8) callconv(.C) c_int {
    if (state.key_queue_read_idx != state.key_queue_write_idx) {
        const key_data = state.key_queue[state.key_queue_read_idx];
        state.key_queue_read_idx +%= 1;
        pressed.* = key_data >> 8;
        doom_key.* = @intCast(key_data & 0xff);
        return 1;
    }
    return 0;
}

/// Called by Doom to set window title. Not used.
pub export fn DG_SetWindowTitle(title: [*c]const u8) callconv(.C) void {
    _ = title;
}

fn translateDoomBufferToRGB() void {
    var rgb_index: usize = 0;
    for (0..doom_frame_buffer_size / 3) |i| {
        const pixel: u32 = DG_ScreenBuffer[i];
        DG_ScreenBuffer_Converted[rgb_index] = @intCast((pixel >> 16) & @as(u32, 0xFF));
        rgb_index += 1;
        DG_ScreenBuffer_Converted[rgb_index] = @intCast((pixel >> 8) & @as(u32, 0xFF));
        rgb_index += 1;
        DG_ScreenBuffer_Converted[rgb_index] = @intCast((pixel >> 0) & @as(u32, 0xFF));
        rgb_index += 1;
    }
}

/// Sets up libvaxis for terminal- and keyboard handling. Finally it
/// enters the Doom game-loop.
pub fn main() !void {
    // Use the C allocator for speed
    const alloc = std.heap.c_allocator;
    const envmap = try std.process.getEnvMap(alloc);
    if (envmap.get("TMUX")) |_| {
        try std.io.getStdErr().writer().print("Terminal Doom can not run under tmux\n", .{});
        std.process.exit(1);
    }

    var tty = try vaxis.Tty.init();
    defer tty.deinit();

    var vx = try vaxis.init(alloc, .{ .kitty_keyboard_flags = .{ .report_events = true } });
    defer vx.deinit(alloc, tty.anyWriter());

    state = .{
        .key_queue = [_]u16{0} ** 32,
        .key_queue_write_idx = 0,
        .key_queue_read_idx = 0,
        .startup = std.time.milliTimestamp(),
        .exit_flag = std.atomic.Value(bool).init(false),
        .loop = .{
            .tty = &tty,
            .vaxis = &vx,
        },
    };

    try state.loop.init();
    try state.loop.start();
    defer state.loop.stop();

    try vx.enterAltScreen(tty.anyWriter());
    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);
    try vx.setMouseMode(tty.anyWriter(), true);

    const args = try std.process.argsAlloc(alloc);

    // Initialize Doom-generic and enter the game loop
    doomgeneric_Create(@intCast(args.len), @ptrCast(args.ptr));
    while (state.exit_flag.load(.seq_cst) == false) {
        doomgeneric_Tick();
    }
}

// Doomgeneric provides the screen buffer which we render when `DG_DrawFrame` is called.
pub extern var DG_ScreenBuffer: [*c]u32;
var DG_ScreenBuffer_Converted: [doom_frame_buffer_size]u8 = undefined;
pub extern fn doomgeneric_Create(argc: c_int, argv: [*c][*c]u8) void;
pub extern fn doomgeneric_Tick() void;
pub extern fn D_PostEvent(ev: *event_t) void;

const doom_width: usize = 640;
const doom_height: usize = 400;
const doom_frame_buffer_size: usize = doom_width * doom_height * 3;

/// Map from codepoints to Doom keys
fn enqueueKey(pressed: bool, key: vaxis.Key) void {
    const doom_key: u8 = switch (key.codepoint) {
        Key.enter => KEY_ENTER,
        Key.escape => KEY_ESCAPE,
        Key.left, 'j' => KEY_LEFTARROW,
        Key.right, 'l' => KEY_RIGHTARROW,
        Key.up, 'w' => KEY_UPARROW,
        Key.down, 'k', 's' => KEY_DOWNARROW,
        Key.left_control, Key.right_control, 'f', 'i' => KEY_FIRE,
        Key.space => KEY_USE,
        Key.left_alt, Key.right_alt => KEY_LALT,
        Key.left_shift, Key.right_shift => KEY_RSHIFT,
        Key.f2 => KEY_F2,
        Key.f3 => KEY_F3,
        Key.f4 => KEY_F4,
        Key.f5 => KEY_F5,
        Key.f6 => KEY_F6,
        Key.f7 => KEY_F7,
        Key.f8 => KEY_F8,
        Key.f9 => KEY_F9,
        Key.f10 => KEY_F10,
        Key.f11 => KEY_F11,
        Key.kp_equal, '=', '+' => KEY_EQUALS,
        '-' => KEY_MINUS,
        'a' => KEY_STRAFE_L,
        'd' => KEY_STRAFE_R,
        else => std.ascii.toLower(@intCast(key.codepoint)),
    };

    const key_data: u16 = (@as(u16, @intCast(@intFromBool(pressed))) << 8) | doom_key;
    state.key_queue[state.key_queue_write_idx] = key_data;
    state.key_queue_write_idx +%= 1;
}

// Doom key definitions
const KEY_RIGHTARROW: u8 = 0xae;
const KEY_LEFTARROW: u8 = 0xac;
const KEY_UPARROW: u8 = 0xad;
const KEY_DOWNARROW: u8 = 0xaf;
const KEY_STRAFE_L: u8 = 0xa0;
const KEY_STRAFE_R: u8 = 0xa1;
const KEY_USE: u8 = 0xa2;
const KEY_FIRE: u8 = 0xa3;
const KEY_ESCAPE: u8 = 27;
const KEY_ENTER: u8 = 13;
const KEY_TAB: u8 = 9;
const KEY_F1: u8 = (0x80 + 0x3b);
const KEY_F2: u8 = (0x80 + 0x3c);
const KEY_F3: u8 = (0x80 + 0x3d);
const KEY_F4: u8 = (0x80 + 0x3e);
const KEY_F5: u8 = (0x80 + 0x3f);
const KEY_F6: u8 = (0x80 + 0x40);
const KEY_F7: u8 = (0x80 + 0x41);
const KEY_F8: u8 = (0x80 + 0x42);
const KEY_F9: u8 = (0x80 + 0x43);
const KEY_F10: u8 = (0x80 + 0x44);
const KEY_F11: u8 = (0x80 + 0x57);
const KEY_F12: u8 = (0x80 + 0x58);
const KEY_BACKSPACE: u8 = 0x7f;
const KEY_PAUSE: u8 = 0xff;
const KEY_EQUALS: u8 = 0x3d;
const KEY_MINUS: u8 = 0x2d;
const KEY_RSHIFT: u8 = (0x80 + 0x36);
const KEY_RCTRL: u8 = (0x80 + 0x1d);
const KEY_RALT: u8 = (0x80 + 0x38);
const KEY_LALT: u8 = KEY_RALT;
const KEY_CAPSLOCK: u8 = (0x80 + 0x3a);
const KEY_NUMLOCK: u8 = (0x80 + 0x45);
const KEY_SCRLCK: u8 = (0x80 + 0x46);
const KEY_PRTSCR: u8 = (0x80 + 0x59);
const KEY_HOME: u8 = (0x80 + 0x47);
const KEY_END: u8 = (0x80 + 0x4f);
const KEY_PGUP: u8 = (0x80 + 0x49);
const KEY_PGDN: u8 = (0x80 + 0x51);
const KEY_INS: u8 = (0x80 + 0x52);
const KEY_DEL: u8 = (0x80 + 0x53);
const KEYP_0: u8 = 0;
const KEYP_1: u8 = KEY_END;
const KEYP_2: u8 = KEY_DOWNARROW;
const KEYP_3: u8 = KEY_PGDN;
const KEYP_4: u8 = KEY_LEFTARROW;
const KEYP_5: u8 = '5';
const KEYP_6: u8 = KEY_RIGHTARROW;
const KEYP_7: u8 = KEY_HOME;
const KEYP_8: u8 = KEY_UPARROW;
const KEYP_9: u8 = KEY_PGUP;
const KEYP_DIVIDE: u8 = '/';
const KEYP_PLUS: u8 = '+';
const KEYP_MINUS: u8 = '-';
const KEYP_MULTIPLY: u8 = '*';
const KEYP_PERIOD: u8 = 0;
const KEYP_EQUALS: u8 = KEY_EQUALS;
const KEYP_ENTER: u8 = KEY_ENTER;
