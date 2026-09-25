CC ?= cc
CFLAGS ?= -std=c99 -O2 -Wall -Wextra -Wpedantic -Werror -Wconversion -Wshadow -Wcast-qual -Wstrict-prototypes
SANITIZE ?= -fsanitize=address,undefined -fno-omit-frame-pointer

BUILD := build
FIXTURES := ../Fixtures/golden/primitives.txt

.PHONY: all test clean

all: $(BUILD)/test_blaze_binary

$(BUILD)/test_blaze_binary: src/blaze_binary.c tests/test_blaze_binary.c include/blaze_binary.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(SANITIZE) -Iinclude src/blaze_binary.c tests/test_blaze_binary.c -o $@

test: $(BUILD)/test_blaze_binary
	$(BUILD)/test_blaze_binary $(FIXTURES)

clean:
	rm -rf $(BUILD)
