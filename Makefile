# ==============================================================
# Tempest-SDR — one-shot installer (Linux & Windows, local install)
# ==============================================================

# ---------- OS detection --------------------------------------
UNAME_S := $(shell uname -s)
ifeq ($(OS),Windows_NT)
  TARGET_OS := windows
else ifeq ($(UNAME_S),Linux)
  TARGET_OS := linux
else
  $(error Unsupported OS)
endif

# ---------- versions & URLs (easily bump here) ----------------
UHD_VER ?= 3.9.4              # FPGA images v4 compatible with ExtIO
HRF_VER ?= 2024.02.1

UHD_URL  = https://files.ettus.com/binaries/uhd_$(UHD_VER)-release_x86.exe
HRF_URL  = https://github.com/greatscottgadgets/hackrf/releases/download/v$(HRF_VER)/hackrf_windows_$(HRF_VER).zip

# ---------- SHA-256 (optional – leave empty to disable check)
UHD_SHA  ?=
HRF_SHA  ?=

# ---------- generic vars --------------------------------------
JOBS      ?= $(shell nproc 2>/dev/null || echo 4)
ROOT_DIR   = $(CURDIR)              # folder where this Makefile is located
SRC_DIR    = $(ROOT_DIR)/TempestSDR # repository cloned locally
WIN_PREFIX = $(ROOT_DIR)\TempestSDR # same logic on Windows side

HACKRF_GUI_REPO = https://github.com/neib/HackRF_Transfer-GUI.git
HACKRF_GUI_DIR  = $(SRC_DIR)/HackRF_Transfer-GUI

# ---------- Linux packages ------------------------------------
LINUX_PKGS = build-essential cmake git pkg-config autoconf swig \
             libpthread-stubs0-dev openjdk-17-jdk \
             libusb-1.0-0-dev libhackrf-dev hackrf \
             libboost-all-dev libuhd-dev uhd-host \
             gnuradio-dev gr-osmosdr gqrx-sdr libudev-dev \
             python3 python3-pip python3-tk

.PHONY: all linux windows clean
all: $(TARGET_OS)

# ==============================================================
# L I N U X
# ==============================================================
linux:
	@echo ">>> install packages (APT)"
	sudo apt update && sudo apt -y upgrade
	sudo apt install -y $(LINUX_PKGS)

	@echo ">>> udev rules (HackRF / USRP)"
	@if [ ! -f /etc/udev/rules.d/53-hackrf.rules ]; then \
	    sudo curl -sSL https://raw.githubusercontent.com/greatscottgadgets/hackrf/master/host/libhackrf/53-hackrf.rules \
	         -o /etc/udev/rules.d/53-hackrf.rules ; fi
	sudo groupadd -f usrp
	sudo usermod -aG usrp $${USER}
	echo "@usrp - rtprio 99" | sudo tee /etc/security/limits.d/90-usrp.conf >/dev/null
	sudo udevadm control --reload-rules

	@echo ">>> clone / update TempestSDR to $(SRC_DIR)"
	@if [ ! -d $(SRC_DIR) ]; then \
	     git clone --recursive https://github.com/martinmarinov/TempestSDR.git $(SRC_DIR); \
	else \
	     cd $(SRC_DIR) && git pull && git submodule update --init --recursive; \
	fi

	@echo ">>> build native libs  (make -j$(JOBS))"
	$(MAKE) -C $(SRC_DIR) -j$(JOBS)

	@echo ">>> build Java GUI     (make -j$(JOBS))"
	$(MAKE) -C $(SRC_DIR)/JavaGUI -j$(JOBS)

	@echo ">>> duplicate libs to lib/LINUX/X64 && refresh JAR"
	@mkdir -p $(SRC_DIR)/JavaGUI/lib/LINUX/X64
	@cp -f $(SRC_DIR)/JavaGUI/lib/LINUX/*.so $(SRC_DIR)/JavaGUI/lib/LINUX/X64/
	@cd $(SRC_DIR)/JavaGUI && \
	     find lib/LINUX/X64 -type f -print0 | xargs -0 jar uf JTempestSDR.jar

	@echo ">>> clone / update HackRF_Transfer-GUI"
	@if [ ! -d $(HACKRF_GUI_DIR) ]; then \
	     git clone --depth 1 $(HACKRF_GUI_REPO) $(HACKRF_GUI_DIR); \
	else \
	     cd $(HACKRF_GUI_DIR) && git pull; \
	fi

	@echo; echo "=== INSTALL COMPLETE ==="
	@echo "TempestSDR  : java -jar $(SRC_DIR)/JavaGUI/JTempestSDR.jar"
	@echo "HackRF rec. : python3 $(HACKRF_GUI_DIR)/HackRF_Recorder.py"
	@echo
	@touch $@

# ==============================================================
# W I N D O W S
# ==============================================================

windows:
	@echo ">>> Windows automated install (PowerShell)"
	powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "\
	$ErrorActionPreference='Stop';\
	Function Verify-SHA { param([string]\$f,[string]\$e); if(-not \$e){return};\
	    \$h=(Get-FileHash -Algo SHA256 \$f).Hash.ToLower(); if(\$h -ne \$e.ToLower()){Throw 'SHA mismatch'}};\
	# 1. choco \
	if(-not(Get-Command choco -EA SilentlyContinue)){iex ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'));};\
	choco upgrade -y git cmake python temurin17jre vcredist140;\
	# 2. TempestSDR source \
	\$root='$(WIN_PREFIX)'; if(-not(Test-Path \$root)){git clone --depth 1 https://github.com/martinmarinov/TempestSDR.git \$root};\
	New-Item -ItemType Directory -Force -Path \$root\\JavaGUI\\lib\\WINDOWS\\X86 | Out-Null;\
	Copy-Item \$root\\Release\\WIN32\\*.dll -Dest \$root\\JavaGUI\\lib\\WINDOWS\\X86 -Force;\
	# 3. UHD 3.9.4 + SHA \
	\$uExe=\$env:TEMP+'\\uhd.exe'; Invoke-WebRequest '$(UHD_URL)' -OutFile \$uExe; Verify-SHA \$uExe '$(UHD_SHA)';\
	Start-Process \$uExe -ArgumentList '/S' -Wait;\
	Copy-Item 'C:\\Program Files (x86)\\UHD\\bin\\libusb-1.0.dll' -Dest \$root\\JavaGUI\\lib\\WINDOWS\\X86 -Force;\
	# 4. HackRF zip + SHA \
	\$z=\$env:TEMP+'\\hackrf.zip'; Invoke-WebRequest '$(HRF_URL)' -OutFile \$z; Verify-SHA \$z '$(HRF_SHA)';\
	Expand-Archive \$z -Dest \$env:TEMP\\hr -Force;\
	Copy-Item \$env:TEMP\\hr\\*libhackrf.dll -Dest \$root\\JavaGUI\\lib\\WINDOWS\\X86 -Force;\
	Copy-Item \$env:TEMP\\hr\\hackrf_transfer.exe -Dest \$root -Force;\
	# 5. Done \
	Write-Host '--- INSTALL COMPLETE ---';\
	Write-Host 'Launch TempestSDR with:';\
	Write-Host '  \"C:\\Program Files (x86)\\Java\\jre-17\\bin\\java\" -jar '+\$root+'\\JavaGUI\\JTempestSDR.jar';\
	"; \
	@touch $@

# --------------------------------------------------------------
# CLEAN
# --------------------------------------------------------------
clean:
	@if [ -d $(SRC_DIR) ]; then \
	    $(MAKE) -k -C $(SRC_DIR) clean; \
	    rm -rf $(SRC_DIR)/JavaGUI/lib/LINUX/X64; \
	fi
	@rm -rf $(HACKRF_GUI_DIR)
