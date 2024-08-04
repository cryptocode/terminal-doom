//! SPDX-License-Identifier: GPL-2-0 or MIT
const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vaxis = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });

    const doom = b.addExecutable(.{
        .name = "terminal-doom",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    doom.root_module.addImport("vaxis", vaxis.module("vaxis"));

    const sound = b.option(bool, "sound", "If set to true, compile sound support using miniaudio. Default is true.") orelse true;

    const cflags_sound = if (sound) [_][]const u8{ "-DFEATURE_SOUND", "-Isrc/doomgeneric" } else [_][]const u8{ "", "" };
    const cflags = [_][]const u8{ "-D_THREADSAFE", "-fno-sanitize=undefined" } ++ cflags_sound;

    const sourcefiles = [_][]const u8{
        "src/doomgeneric/dummy.c",
        "src/doomgeneric/am_map.c",
        "src/doomgeneric/doomdef.c",
        "src/doomgeneric/doomstat.c",
        "src/doomgeneric/dstrings.c",
        "src/doomgeneric/d_event.c",
        "src/doomgeneric/d_items.c",
        "src/doomgeneric/d_iwad.c",
        "src/doomgeneric/d_loop.c",
        "src/doomgeneric/d_main.c",
        "src/doomgeneric/d_mode.c",
        "src/doomgeneric/d_net.c",
        "src/doomgeneric/f_finale.c",
        "src/doomgeneric/f_wipe.c",
        "src/doomgeneric/g_game.c",
        "src/doomgeneric/hu_lib.c",
        "src/doomgeneric/hu_stuff.c",
        "src/doomgeneric/info.c",
        "src/doomgeneric/i_cdmus.c",
        "src/doomgeneric/i_endoom.c",
        "src/doomgeneric/i_joystick.c",
        "src/doomgeneric/i_scale.c",
        "src/doomgeneric/i_sound.c",
        "src/doomgeneric/i_system.c",
        "src/doomgeneric/i_timer.c",
        "src/doomgeneric/memio.c",
        "src/doomgeneric/m_argv.c",
        "src/doomgeneric/m_bbox.c",
        "src/doomgeneric/m_cheat.c",
        "src/doomgeneric/m_config.c",
        "src/doomgeneric/m_controls.c",
        "src/doomgeneric/m_fixed.c",
        "src/doomgeneric/m_menu.c",
        "src/doomgeneric/m_misc.c",
        "src/doomgeneric/m_random.c",
        "src/doomgeneric/p_ceilng.c",
        "src/doomgeneric/p_doors.c",
        "src/doomgeneric/p_enemy.c",
        "src/doomgeneric/p_floor.c",
        "src/doomgeneric/p_inter.c",
        "src/doomgeneric/p_lights.c",
        "src/doomgeneric/p_map.c",
        "src/doomgeneric/p_maputl.c",
        "src/doomgeneric/p_mobj.c",
        "src/doomgeneric/p_plats.c",
        "src/doomgeneric/p_pspr.c",
        "src/doomgeneric/p_saveg.c",
        "src/doomgeneric/p_setup.c",
        "src/doomgeneric/p_sight.c",
        "src/doomgeneric/p_spec.c",
        "src/doomgeneric/p_switch.c",
        "src/doomgeneric/p_telept.c",
        "src/doomgeneric/p_tick.c",
        "src/doomgeneric/p_user.c",
        "src/doomgeneric/r_bsp.c",
        "src/doomgeneric/r_data.c",
        "src/doomgeneric/r_draw.c",
        "src/doomgeneric/r_main.c",
        "src/doomgeneric/r_plane.c",
        "src/doomgeneric/r_segs.c",
        "src/doomgeneric/r_sky.c",
        "src/doomgeneric/r_things.c",
        "src/doomgeneric/sha1.c",
        "src/doomgeneric/sounds.c",
        "src/doomgeneric/statdump.c",
        "src/doomgeneric/st_lib.c",
        "src/doomgeneric/st_stuff.c",
        "src/doomgeneric/s_sound.c",
        "src/doomgeneric/tables.c",
        "src/doomgeneric/v_video.c",
        "src/doomgeneric/wi_stuff.c",
        "src/doomgeneric/w_checksum.c",
        "src/doomgeneric/w_file.c",
        "src/doomgeneric/w_main.c",
        "src/doomgeneric/w_wad.c",
        "src/doomgeneric/z_zone.c",
        "src/doomgeneric/w_file_stdc.c",
        "src/doomgeneric/i_input.c",
        "src/doomgeneric/i_video.c",
        "src/doomgeneric/doomgeneric.c",
    };

    const sourcefiles_sound = [_][]const u8{"src/miniaudio/doom_miniaudio_sound_bridge.c"};

    inline for (sourcefiles) |src| {
        doom.addCSourceFile(.{ .file = b.path(src), .flags = &cflags });
    }

    if (sound) {
        inline for (sourcefiles_sound) |src| {
            doom.addCSourceFile(.{ .file = b.path(src), .flags = &cflags });
        }
    }

    doom.linkLibC();
    b.installArtifact(doom);
}
