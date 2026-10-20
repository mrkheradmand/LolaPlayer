// Runtime inspection uses only public libmpv/FFmpeg APIs, loaded dynamically.
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
static void json_string(const char *s) {
    putchar('"');
    for (; s && *s; ++s) {
        if (*s == '"' || *s == '\\') { putchar('\\'); putchar(*s); }
        else if ((unsigned char)*s < 32) printf("\\u%04x", (unsigned char)*s);
        else putchar(*s);
    }
    putchar('"');
}
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!lib) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    const char *(*ffversion)(void) = dlsym(lib, "av_version_info");
    const char *(*config)(void) = dlsym(lib, "avcodec_configuration");
    void *(*decoder)(const char *) = dlsym(lib, "avcodec_find_decoder_by_name");
    void *(*demuxer)(const char *) = dlsym(lib, "av_find_input_format");
    void *(*create)(void) = dlsym(lib, "mpv_create");
    int (*option)(void *, const char *, const char *) = dlsym(lib, "mpv_set_option_string");
    int (*initialize)(void *) = dlsym(lib, "mpv_initialize");
    char *(*get)(void *, const char *) = dlsym(lib, "mpv_get_property_string");
    void (*release)(void *) = dlsym(lib, "mpv_free");
    void (*destroy)(void *) = dlsym(lib, "mpv_terminate_destroy");
    if (!ffversion || !config || !decoder || !demuxer || !create || !option || !initialize || !get || !release || !destroy) return 3;
    void *mpv = create(); if (!mpv) return 4;
    option(mpv,"config","no"); option(mpv,"terminal","no"); option(mpv,"vo","null"); option(mpv,"ao","null");
    int dvd = option(mpv,"dvd-device","") >= 0;
    int bluray = option(mpv,"bluray-device","") >= 0;
    if (initialize(mpv) < 0) return 5;
    char *version = get(mpv,"mpv-version");
    printf("{\"mpv\":"); json_string(version);
    printf(",\"ffmpeg\":"); json_string(ffversion());
    printf(",\"configuration\":"); json_string(config());
    printf(",\"vvc\":%s", decoder("vvc") || decoder("libvvdec") ? "true" : "false");
    printf(",\"prores_raw\":%s", decoder("prores_raw") ? "true" : "false");
    printf(",\"aac\":%s", decoder("aac") ? "true" : "false");
    printf(",\"tracker\":%s", demuxer("libopenmpt") || demuxer("libmodplug") ? "true" : "false");
    printf(",\"dvd\":%s,\"bluray\":%s", dvd ? "true" : "false", bluray ? "true" : "false");
    printf("}\n");
    if (version) release(version);
    destroy(mpv);
    return 0;
}
