# KwasOS Build System
# Copyright (C) 2026 KwasOS Project
# SPDX-License-Identifier: GPL-3.0-or-later

LFS      ?= /mnt/lfs
VERSION  ?= 1.0
BUILD    ?= $(CURDIR)/build
NPROC    := $(shell nproc)
LOG      := $(CURDIR)/logs

.PHONY: all help prepare cross chroot system final live clean distclean

all:
	@$(MAKE) prepare && \
	 $(MAKE) cross && \
	 $(MAKE) chroot && \
	 $(MAKE) system && \
	 $(MAKE) final && \
	 $(MAKE) live && \
	 echo "" && \
	 echo "=========================================" && \
	 echo " KwasOS $(VERSION) собран успешно!" && \
	 echo " ISO: $(BUILD)/kwasos-$(VERSION).iso" && \
	 echo "========================================="

help:
	@echo "KwasOS Build System"
	@echo ""
	@echo "Цели:"
	@echo "  make all       - Полная сборка (prepare + cross + chroot + system + final + live)"
	@echo "  make prepare   - Скачать пакеты и создать структуру"
	@echo "  make cross     - Собрать кросс-тулчейн (главы 5-6)"
	@echo "  make chroot    - Временные инструменты (глава 7)"
	@echo "  make system    - Базовая система (глава 8)"
	@echo "  make final     - Ядро и финальная настройка (главы 9-11)"
	@echo "  make live      - Собрать Live ISO"
	@echo "  make clean     - Очистить логи"
	@echo "  make distclean - Удалить всё (ОСТОРОЖНО!)"

prepare:
	@echo "[1/6] Подготовка..."
	@mkdir -p $(LOG) $(BUILD)
	@bash scripts/build.sh prepare 2>&1 | tee $(LOG)/prepare.log

cross:
	@echo "[2/6] Кросс-тулчейн..."
	@bash scripts/build.sh cross 2>&1 | tee $(LOG)/cross.log

chroot:
	@echo "[3/6] Chroot-инструменты..."
	@bash scripts/build.sh chroot 2>&1 | tee $(LOG)/chroot.log

system:
	@echo "[4/6] Базовая система..."
	@bash scripts/build.sh system 2>&1 | tee $(LOG)/system.log

final:
	@echo "[5/6] Ядро и настройка..."
	@bash scripts/build.sh final 2>&1 | tee $(LOG)/final.log

live:
	@echo "[6/6] Сборка Live ISO..."
	@bash scripts/build.sh live 2>&1 | tee $(LOG)/live.log

clean:
	@rm -rf $(LOG)
	@echo "Логи очищены."

distclean:
	@echo "ВНИМАНИЕ: Это удалит $(LFS) полностью!"
	@read -p "Продолжить? [y/N] " ans; \
	if [ "$$ans" = "y" ]; then \
		sudo rm -rf $(LFS) $(BUILD); \
		echo "Очищено."; \
	fi