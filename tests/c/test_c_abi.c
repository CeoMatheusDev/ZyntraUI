/* Consumidor C real da ZyntraUI via C-ABI (teste de integração M5).
 * Compilar: zig cc tests/c/test_c_abi.c -Lzig-out/lib -lzyntra_ui -o /tmp/zyntra-c-test
 * (ou contra a lib estática direta). Retorna 0 em sucesso.
 */
#include <assert.h>
#include <stdio.h>
#include "zyntra.h"

#define CHECK(expr) do { \
    ZyntraResult r = (expr); \
    if (r != ZYNTRA_OK) { \
        printf("FAIL %s:%d -> %d\n", __FILE__, __LINE__, (int)r); \
        return 1; \
    } \
} while (0)

int main(void) {
    /* Layout de ABI verificado em tempo de compilação. */
    _Static_assert(sizeof(ZyntraVec2) == 8, "ZyntraVec2 ABI");
    _Static_assert(sizeof(ZyntraRect) == 16, "ZyntraRect ABI");
    _Static_assert(sizeof(ZyntraColor) == 4, "ZyntraColor ABI");
    _Static_assert(ZYNTRA_OK == 0, "ok==0");

    printf("zyntra %u.%u.%u\n",
        zyntra_version_major(), zyntra_version_minor(), zyntra_version_patch());

    ZyntraContext *ctx = NULL;
    ZyntraRect vp = {0, 0, 800, 600};
    CHECK(zyntra_context_create(vp, &ctx));
    assert(ctx != NULL);

    /* Viewport negativo rejeitado sem alocar. */
    {
        ZyntraContext *bad = NULL;
        ZyntraRect neg = {0, 0, -1, 600};
        assert(zyntra_context_create(neg, &bad) == ZYNTRA_INVALID_ARGUMENT);
        assert(bad == NULL);
    }

    CHECK(zyntra_context_begin_frame(ctx));
    assert(zyntra_context_begin_frame(ctx) == ZYNTRA_INVALID_STATE);

    ZyntraVec2 p = {30, 25};
    CHECK(zyntra_context_push_mouse_move(ctx, p));
    CHECK(zyntra_context_push_mouse_button(ctx, 0, true, p));
    assert(zyntra_context_push_mouse_button(ctx, 7, true, p) == ZYNTRA_INVALID_ARGUMENT);

    ZyntraRect btn = {10, 10, 120, 40};
    ZyntraColor red = {200, 0, 0, 255};
    CHECK(zyntra_draw_rect_filled(ctx, btn, red));

    ZyntraRect negw = {0, 0, -1, 5};
    ZyntraColor black = {0, 0, 0, 255};
    assert(zyntra_draw_rect_filled(ctx, negw, black) == ZYNTRA_INVALID_COMMAND);

    size_t events = 0, draws = 0;
    CHECK(zyntra_context_pending_events(ctx, &events));
    CHECK(zyntra_draw_count(ctx, &draws));
    assert(events == 2);
    assert(draws == 1);

    CHECK(zyntra_context_end_frame(ctx));
    assert(zyntra_context_end_frame(ctx) == ZYNTRA_INVALID_STATE);

    uint64_t idx = 0;
    CHECK(zyntra_context_frame_index(ctx, &idx));
    assert(idx == 1);

    /* Nulos nunca crasham. */
    assert(zyntra_context_begin_frame(NULL) == ZYNTRA_INVALID_ARGUMENT);
    assert(zyntra_context_pending_events(ctx, NULL) == ZYNTRA_INVALID_ARGUMENT);
    zyntra_context_destroy(NULL);

    zyntra_context_destroy(ctx);
    printf("C-ABI OK events=%zu draws=%zu frame=%llu\n",
        events, draws, (unsigned long long)idx);
    return 0;
}
