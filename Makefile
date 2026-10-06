# KwasOS Build System
# Copyright (C) 2026 KwasOS Project
# SPDX-License-Identifier: GPL-3.0-or-later

SHELL   := /bin/bash
LFS     ?= /mnt/lfs
VERSION ?= 1.0
BUILD   ?= $(CURDIR)/build
LOG     ?= $(CURDIR)/logs
FORCE   ?=

export LFS VERSION BUILD LOG FORCE

.PHONY: all help prepare cross chroot system final live clean distclean

all:
	@mkdir -p $(LOG)
	@bash scripts/build.sh all 2>&1 | tee -a $(LOG)/build.log
	@exit $${PIPESTATUS[0]}

help:
	@bash scripts/build.sh

prepare:
	@mkdir -p $(LOG)
	@bash scripts/build.sh prepare 2>&1 | tee -a $(LOG)/build.log
	@exit $${PIPESTATUS[0]}

cross:
	@mkdir -p $(LOG)
	@bash scripts/build.sh cross 2>&1 | tee -a $(LOG)/build.log
	@exit $${PIPESTATUS[0]}

chroot:
	@mkdir -p $(LOG)
	@bash scripts/build.sh chroot 2>&1 | tee -a $(LOG)/build.log
	@exit $${PIPESTATUS[0]}

system:
	@mkdir -p $(LOG)
	@bash scripts/build.sh system 2>&1 | tee -a $(LOG)/build.log
	@exit $${PIPESTATUS[0]}

final:
	@mkdir -p $(LOG)
	@bash scripts/build.sh final 2>&1 | tee -a $(LOG)/build.log
	@exit $${PIPESTATUS[0]}

live:
	@mkdir -p $(LOG)
	@bash scripts/build.sh live 2>&1 | tee -a $(LOG)/build.log
	@exit $${PIPESTATUS[0]}

clean:
	@rm -rf $(LOG) $(LFS)/.stamps
	@echo "Логи и маркеры очищены"

distclean:
	@echo "Удалить $(LFS) и $(BUILD)? [y/N]"; \
	read ans; \
	if [ "$$ans" = "y" ]; then sudo rm -rf $(LFS) $(BUILD); fi