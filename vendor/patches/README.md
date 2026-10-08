# Patches applied to whisper.cpp

`vendor/whisper.cpp` is a git submodule pinned to v1.7.2. `make vendor` applies
every `.patch` in this folder to it before building, and says which ones it
applied. Running it twice is safe: a patch that is already in place is reported
and skipped.

Keep these few and keep each one explained. A patch is the right answer when a
bug hurts Nivi today and moving the pin would cost more than it is worth. If the
list ever grows past two or three, move the pin instead.

## 0001-ggml-alloc-guard-stale-buffer-id.patch

**What it fixes:** Nivi crashing with `SIGSEGV` in the middle of a dictation.

`ggml_gallocr_node_needs_realloc` decided whether a tensor still fits the buffer
it was given last time:

```c
size_t node_size = (node->data || node->view_src) ? 0 : ggml_backend_buft_get_alloc_size(galloc->bufts[talloc->buffer_id], node);
```

The test on the left asks about the tensor in the **new** graph. The
`talloc->buffer_id` on the right came from the **old** one, where the allocator
writes `-1` for anything that was a view or already had data. So a tensor that
was a view last time and is not one now reads `galloc->bufts[-1]`, which is
`NULL`, and then reads `NULL->iface.get_alloc_size`. That field is the fifth
function pointer in the struct, which is why the crash report always said:

    KERN_INVALID_ADDRESS at 0x0000000000000020

**Why Nivi hits it and most callers do not.** Nivi asks one whisper context for
two differently shaped graphs, over and over. Each streaming pass sets
`audio_ctx` to fit the growing live window and asks for timestamps; the final
pass at the end of every dictation asks for no timestamps and the model's full
context. Alternating those two reshapes the decode graph constantly, which is
what it takes to make a tensor's view-ness flip between passes.

**Proof.** A harness that alternates the two passes on one context crashed on the
12th simulated dictation, with the same fault address and the same five stack
frames as the real crash reports. With the patch it ran 40 dictations and 300
passes on Metal without a fault. `bash Tools/whisper-stress/run.sh` repeats it,
and refuses to pass if whisper fell back to the CPU.

**Upstream.** This is the fix ggml made later. When the submodule pin moves past
a release that contains it, delete this patch and this section.

## 0002-metal-embed-works-in-paths-with-spaces.patch

**What it fixes:** whisper running on the CPU instead of the GPU, about three times
slower, with no error anywhere Nivi can see.

The Metal shaders are compiled when the app starts, from one source file the build
glues together: `ggml-metal.metal` with `ggml-common.h` pasted in where it is
included. The paste is a `sed` command, and its file name sat inside single quotes.
CMake escapes a space in a path as `\ `, but inside single quotes the shell keeps
that backslash, so `sed` looked for a file called `Mobile\ Documents/...`, did not
find it, and pasted nothing. `sed` is silent about a missing file by design.

This repo lives under `~/Library/Mobile Documents/`, so any `make vendor` run from
that path produced broken shaders. Run from `~/personal/dictato`, which has no
spaces, it worked. That is why it went unnoticed until 24 September 2026. The app
then logged nothing useful; whisper printed
`ggml_metal_init: error: ... unknown type name 'block_q4_0'` to a stderr nobody
reads and carried on on the CPU. A 2 second clip took 1.9 s instead of 0.6 s.

The patch matches the include line by file name alone, `/ggml-common[.]h/`, so
there are no quotes left for the shell to mangle, and passes the whole expression
as one CMake argument. `make vendor` now also checks that the glued file contains
the header and fails if it does not.
