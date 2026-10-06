# KwasOS Build System
# Copyright (C) 2026 KwasOS Project
# SPDX-License-Identifier: GPL-3.0-or-later

LFS     ?= /mnt/lfs
VERSION ?= 1.0
BUILD   ?= $(CURDIR)/build
LOG     ?= $(CURDIR)/logs
FORCE   ?=

export LFS VERSION BUILD LOG FORCE

.PHONY: all help prepare cross chroot system final live clean distclean

all:
	@$(MAKE) --no-print-directory _stage S=all

help:
	@bash scripts/build.sh

prepare:
	@$(MAKE) --no-print-directory _stage S=prepare

cross:
	@$(MAKE) --no-print-directory _stage S=cross

chroot:
	@$(MAKE) --no-print-directory _stage S=chroot

system:
	@$(MAKE) --no-print-directory _stage S=system

final:
	@$(MAKE) --no-print-directory _stage S=final

live:
	@$(MAKE) --no-print-directory _stage S=live

clean:
	@bash scripts/build.sh clean

distclean:
	@echo "Удалить $(LFS) и build? [y/N]"; \
	read ans; [ "$$ans" = "y" ] && sudo rm -rf $(LFS) $(BUILD)

_stage:
	@bash scripts/build.sh $(S) 2>&1 | tee -a $(LOG)/build.log; \
	exit $${PIPESTATUS[0]}