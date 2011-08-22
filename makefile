CC=gcc
CFLAGS=-O2 -fPIC
# -O3 and -ftree-vectorize don't seem to make any difference

# Guess a platform
UNAME=$(shell uname -s)
ifneq (,$(findstring Darwin,$(UNAME)))
  # OS X
  SO_SUFFIX=dylib
  SHARED=-bundle -undefined dynamic_lookup
else
  # Linux
  SO_SUFFIX=so
  SHARED=-shared
endif

rsm.$(SO_SUFFIX): c/rsm.c c/rsm.h
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@

