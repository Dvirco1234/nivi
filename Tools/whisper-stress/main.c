// Mimics one Nivi recording exactly: a run of streaming passes (timestamps on, an
// audio_ctx sized to a growing window) followed by the final pass (timestamps off,
// audio_ctx 0 = the model's full 1500), all on ONE whisper context, over and over,
// the way RecognizerCache hands the same context to every recording.
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "whisper.h"

#define SR 16000

static float *audio;

static int run(struct whisper_context *ctx, int n, int audio_ctx, bool timestamps) {
    struct whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    p.language = "he";
    p.n_threads = 8;
    p.no_timestamps = !timestamps;
    p.audio_ctx = audio_ctx;
    p.print_progress = false;
    p.print_realtime = false;
    p.print_special = false;
    p.suppress_blank = true;
    return whisper_full(ctx, p, audio, n);
}

int main(int argc, char **argv) {
    struct whisper_context_params cp = whisper_context_default_params();
    cp.use_gpu = true;
    struct whisper_context *ctx = whisper_init_from_file_with_params(argv[1], cp);
    if (!ctx) { fprintf(stderr, "model load failed\n"); return 1; }

    int maxSamples = SR * 15;
    audio = malloc(sizeof(float) * maxSamples);
    srand(4321);
    for (int i = 0; i < maxSamples; i++)
        audio[i] = 0.10f * sinf(i * 0.011f) + 0.05f * ((rand() / (float)RAND_MAX) - 0.5f);

    for (int recording = 0; recording < 40; recording++) {
        int spoken = 3 + (recording % 10);           // how long this "dictation" lasts
        for (int s = 2; s <= spoken; s++) {          // the streaming loop, window growing
            int n = SR * s;
            int c = 1500 * n / (SR * 30) + 128;
            c = ((c + 3) / 4) * 4;
            if (c < 256) c = 256;
            if (c > 1500) c = 1500;
            printf("rec %2d stream %2ds ctx=%4d ... ", recording, s, c); fflush(stdout);
            printf("rc=%d\n", run(ctx, n, c, true)); fflush(stdout);
        }
        printf("rec %2d FINAL    %2ds ctx=   0 ... ", recording, spoken); fflush(stdout);
        printf("rc=%d\n", run(ctx, SR * spoken, 0, false)); fflush(stdout);
    }
    whisper_free(ctx);
    printf("SURVIVED\n");
    return 0;
}
