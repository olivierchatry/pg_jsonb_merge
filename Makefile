# PostgreSQL Extension Makefile

# Extension configuration
EXTENSION = jsonb_merge
DATA = sql/$(EXTENSION)--1.0.sql
MODULES = jsonb_merge

# Source files
SRCS = jsonb_merge.c

# PostgreSQL configuration
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Disable LLVM bitcode generation if needed
PG_LLVM_COMPILE =

# Base compiler flags
PG_CFLAGS += -Wall -Wmissing-prototypes -Wpointer-arith -Wdeclaration-after-statement -Wendif-labels -Wmissing-format-attribute -Wformat-security -fno-strict-aliasing -fwrapv -fexcess-precision=standard

# --- Custom Targets ---

# Docker-based testing
test-docker: all
	@echo "Running Docker-based tests..."
	@./test/docker-test.sh


.PHONY: test-docker
