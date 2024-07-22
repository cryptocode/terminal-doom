//! SPDX-License-Identifier: GPL-2-0 or MIT
#include "config.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <ctype.h>

#include "doomtype.h"

#include "deh_str.h"
#include "i_sound.h"
#include "i_system.h"
#include "i_swap.h"
#include "m_argv.h"
#include "m_misc.h"
#include "w_wad.h"
#include "z_zone.h"

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

static boolean sound_initialized = false;
static int mixer_freq;
static uint16_t mixer_format;
static int mixer_channels;
static boolean use_sfx_prefix;

// These are expected to exist by i_sound.h
int use_libsamplerate = 0;
float libsamplerate_scale = 0.65f;

// The miniaudio engine
static ma_engine gma_engine;
static ma_engine_config gma_config;
static ma_sound gma_current_music;
static boolean gma_music_playing = false;

static boolean I_MINI_AUDIO_InitSound(boolean _use_sfx_prefix)
{
    use_sfx_prefix = _use_sfx_prefix;
    gma_config = ma_engine_config_init();

    // Initialize miniaudio
    ma_result result;
    result = ma_engine_init(&gma_config, &gma_engine);
    if (result != MA_SUCCESS) {
        fprintf(stderr, "minisound initialization failed: %d\n", result);
        return -1;
    } else {
        // fprintf(stderr, "Playback device: '%s'", engine.pDevice->playback.name);
    }

    sound_initialized = true;
    return true;
}

static void I_MINI_AUDIO_ShutdownSound(void)
{    
    if (!sound_initialized)
    {
        return;
    }

    // Release Miniaudio resources
    ma_engine_uninit(&gma_engine);
    sound_initialized = false;
}

static void GetSfxLumpName(sfxinfo_t *sfx, char *buf, size_t buf_len)
{
    // Linked sfx lumps? Get the lump number for the sound linked to.
    if (sfx->link != NULL)
    {
        sfx = sfx->link;
    }

    // Doom adds a DS* prefix to sound lumps; Heretic and Hexen don't do this.
    if (use_sfx_prefix)
    {
        M_snprintf(buf, buf_len, "ds%s", DEH_String(sfx->name));
    }
    else
    {
        M_StringCopy(buf, DEH_String(sfx->name), buf_len);
    }
}

// Retrieve the raw data lump index for a given SFX name.
// The Doom framework calls this, but the lump number is not used in
// our implementation; instead we map sfx name to wav file.
static int I_MINI_AUDIO_GetSfxLumpNum(sfxinfo_t *sfx)
{
    char namebuf[9];
    GetSfxLumpName(sfx, namebuf, sizeof(namebuf));
    return W_GetNumForName(namebuf);
}

static boolean I_MINI_AUDIO_SoundIsPlaying(int handle)
{
    if (!sound_initialized || handle < 0)
    {
        return false;
    }

   // TODO: miniaudio equivalent: check playing status of an ma_sound
   return false;
}

static void I_MINI_AUDIO_UpdateSound(void)
{
}

static void I_MINI_AUDIO_UpdateSoundParams(int handle, int vol, int sep)
{
}

static int I_MINI_AUDIO_StartSound(sfxinfo_t *sfxinfo, int channel, int vol, int sep)
{
    char name[64];
    snprintf(name, 64, "sound/ds%s.wav", sfxinfo->name);
    ma_engine_play_sound(&gma_engine, name, NULL);

    return 0;
}

static void I_MINI_AUDIO_StopSound(int handle) {}
static void I_MINI_AUDIO_PrecacheSounds(sfxinfo_t *sounds, int num_sounds) {}

static snddevice_t sound_sdl_devices[] = 
{
    SNDDEVICE_SB,
    SNDDEVICE_PAS,
    SNDDEVICE_GUS,
    SNDDEVICE_WAVEBLASTER,
    SNDDEVICE_SOUNDCANVAS,
    SNDDEVICE_AWE32,
};

sound_module_t DG_sound_module = 
{
    sound_sdl_devices,
    arrlen(sound_sdl_devices),
    I_MINI_AUDIO_InitSound,
    I_MINI_AUDIO_ShutdownSound,
    I_MINI_AUDIO_GetSfxLumpNum,
    I_MINI_AUDIO_UpdateSound,
    I_MINI_AUDIO_UpdateSoundParams,
    I_MINI_AUDIO_StartSound,
    I_MINI_AUDIO_StopSound,
    I_MINI_AUDIO_SoundIsPlaying,
    I_MINI_AUDIO_PrecacheSounds,
};

// Initialize music subsystem
static boolean I_MINI_AUDIO_InitMusic(void) {
    return true;
}

static void I_MINI_AUDIO_ShutdownMusic(void) {}

// Music volume 0-127
static void I_MINI_AUDIO_SetMusicVolume(int volume) {
    if (gma_music_playing) {
        if (ma_sound_is_playing(&gma_current_music)) {
            float converted = ma_volume_linear_to_db(1.0f - (volume / 127.0f));
            ma_sound_set_volume(&gma_current_music, converted);
        }
    }
}

static void I_MINI_AUDIO_PauseSong(void) {}
static void I_MINI_AUDIO_ResumeSong(void) {}

// Map name to handle
static void *I_MINI_AUDIO_RegisterSong(void *data, int len) {
    char* name = data;
    size_t str_len = strlen(name);
    char* copy = malloc(str_len+1);
    int res = ma_strcpy_s(copy, str_len+1, name);
    return copy;
}

static void I_MINI_AUDIO_UnRegisterSong(void *handle) {
    free(handle);
}

// Stop currently playing sound
static void I_MINI_AUDIO_StopSong(void) {

    if (gma_music_playing) {
        if (ma_sound_is_playing(&gma_current_music)) {
            ma_sound_stop(&gma_current_music);
        }
        ma_sound_uninit(&gma_current_music);

        gma_music_playing = false;
    }
}

static void I_MINI_AUDIO_PlaySong(void *handle, boolean looping) {
    I_MINI_AUDIO_StopSong();
    
    char name[64];
    snprintf(name, 64, "sound/%s.mp3", (char*)handle);

    // Miniaudio
    ma_result result;
    result = ma_sound_init_from_file(&gma_engine, name, 0, NULL, NULL, &gma_current_music);
    if (result != MA_SUCCESS) {
        // Uncomment this to see which music tracks are missing
        // fprintf(stderr, "Music not found: %s\n", name);
        return;
    }
    ma_sound_set_looping(&gma_current_music, looping);
    result = ma_sound_start(&gma_current_music);
    if (result != MA_SUCCESS) {
        fprintf(stderr, "Could not play song: %s: %d\n", name, result);
        return;
    }
    gma_music_playing = true;    
}

static boolean I_MINI_AUDIO_MusicIsPlaying(void) {
    return gma_music_playing;
}

// Poll music position; if we have passed the loop point end position
// then we need to go back.
static void I_MINI_AUDIO_PollMusic(void) {}

static snddevice_t music_sdl_devices[] =
{
    SNDDEVICE_PAS,
    SNDDEVICE_GUS,
    SNDDEVICE_WAVEBLASTER,
    SNDDEVICE_SOUNDCANVAS,
    SNDDEVICE_GENMIDI,
    SNDDEVICE_AWE32,
};

music_module_t DG_music_module =
{
    music_sdl_devices,
    arrlen(music_sdl_devices),
    I_MINI_AUDIO_InitMusic,
    I_MINI_AUDIO_ShutdownMusic,
    I_MINI_AUDIO_SetMusicVolume,
    I_MINI_AUDIO_PauseSong,
    I_MINI_AUDIO_ResumeSong,
    I_MINI_AUDIO_RegisterSong,
    I_MINI_AUDIO_UnRegisterSong,
    I_MINI_AUDIO_PlaySong,
    I_MINI_AUDIO_StopSong,
    I_MINI_AUDIO_MusicIsPlaying,
    I_MINI_AUDIO_PollMusic,
};
