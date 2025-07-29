# ==============================================================
# Tempest-SDR — one-shot installer (Linux & Windows, local install)
# ==============================================================

# ---------- OS detection --------------------------------------
UNAME_S := $(shell uname -s)
ifeq ($(OS),Windows_NT)
  TARGET_OS := windows
else ifeq ($(UNAME_S),Linux)
  TARGET_OS := linux
  # Architecture detection for Linux
  UNAME_M := $(shell uname -m)
  ifeq ($(UNAME_M),x86_64)
	LINUX_ARCH := X64
  else ifeq ($(UNAME_M),aarch64)
	LINUX_ARCH := ARM64
  else ifeq ($(UNAME_M),armv7l)
	LINUX_ARCH := ARM
  else
	LINUX_ARCH := $(UNAME_M)
  endif
else
  $(error Unsupported OS)
endif

# ---------- versions & URLs (easily bump here) ----------------
UHD_VER ?= 3.9.4
HRF_VER ?= 2024.02.1

UHD_URL  = https://files.ettus.com/binaries/uhd_stable/uhd_003.009.004-release/uhd_003.009.004-release_Win32_VS2015.exe
HRF_URL  = https://github.com/greatscottgadgets/hackrf/releases/download/v$(HRF_VER)/hackrf-$(HRF_VER).zip

# ---------- generic vars --------------------------------------
JOBS      ?= $(shell nproc 2>/dev/null || echo 4)
ROOT_DIR   = $(CURDIR)
SRC_DIR    = $(ROOT_DIR)/TempestSDR
WIN_PREFIX = $(ROOT_DIR)\TempestSDR

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
		 echo "Cloning TempestSDR repository..."; \
		 git clone --recursive https://github.com/martinmarinov/TempestSDR.git $(SRC_DIR); \
	else \
		 echo "TempestSDR already exists, updating..."; \
		 cd $(SRC_DIR) && git pull && git submodule update --init --recursive; \
	fi

	@echo ">>> configure JAVA_HOME"
	@export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

	@echo ">>> build native libs  (make -j$(JOBS)) for $(LINUX_ARCH)"
	JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 $(MAKE) -C $(SRC_DIR) -j$(JOBS)

	@echo ">>> build Java GUI     (make -j$(JOBS)) for $(LINUX_ARCH)"
	JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 $(MAKE) -C $(SRC_DIR)/JavaGUI -j$(JOBS)

	@echo ">>> refresh JAR with native libraries ($(LINUX_ARCH))"
	@cd $(SRC_DIR)/JavaGUI && \
		 find lib/LINUX/$(LINUX_ARCH) -type f -print0 | xargs -0 jar uf JTempestSDR.jar

	@echo ">>> clone / update HackRF_Transfer-GUI"
	@if [ ! -d $(HACKRF_GUI_DIR) ]; then \
		 echo "Cloning HackRF_Transfer-GUI repository..."; \
		 git clone --depth 1 $(HACKRF_GUI_REPO) $(HACKRF_GUI_DIR); \
	else \
		 echo "HackRF_Transfer-GUI already exists, updating..."; \
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
	$$ErrorActionPreference='Stop';\
	Write-Host '=== TEMPEST SDR INSTALLATION START ===' -ForegroundColor Green;\
	Write-Host '[STEP 1/10] Checking Chocolatey...' -ForegroundColor Yellow;\
	if(-not(Get-Command choco -EA SilentlyContinue)){\
		Write-Host '  -> Chocolatey not found, installing...' -ForegroundColor Cyan;\
		[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;\
		Write-Host '  -> Downloading Chocolatey script...' -ForegroundColor Cyan;\
		iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'));\
		Write-Host '  -> Updating PATH for Chocolatey...' -ForegroundColor Cyan;\
		$$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User');\
		Write-Host '  -> Chocolatey installed successfully!' -ForegroundColor Green;\
	} else {\
		Write-Host '  -> Chocolatey already installed, proceeding...' -ForegroundColor Green;\
	};\
	if(-not(Get-Command choco -EA SilentlyContinue)){\
		Write-Host '  -> Adding Chocolatey PATH manually...' -ForegroundColor Yellow;\
		$$env:PATH += ';C:\\ProgramData\\chocolatey\\bin';\
	};\
	Write-Host '[STEP 2/10] Installing base packages...' -ForegroundColor Yellow;\
	Write-Host '  -> Installing: git, cmake, python, vcredist (may take 5-10 min)...' -ForegroundColor Cyan;\
	choco upgrade -y git cmake python vcredist140 vcredist2008;\
	Write-Host '  -> Base packages installed!' -ForegroundColor Green;\
	Write-Host '[STEP 3/10] Installing Java 32-bit...' -ForegroundColor Yellow;\
	Write-Host '  -> Downloading Java 8 JRE 32-bit (may take 3-5 min)...' -ForegroundColor Cyan;\
	choco upgrade -y temurin8jre --x86;\
	Write-Host '  -> Java 32-bit installed!' -ForegroundColor Green;\
	Write-Host '[STEP 4/10] Configuring Java PATH and alias...' -ForegroundColor Yellow;\
	$$javaPath = Get-ChildItem 'C:\\Program Files (x86)\\Eclipse Adoptium\\' -Directory | Where-Object {$$_.Name -like 'jre-8*'} | Select-Object -First 1 -ExpandProperty FullName;\
	if($$javaPath) {\
		Write-Host \"  -> Java found in: $$javaPath\" -ForegroundColor Cyan;\
		$$javaBinPath = Join-Path $$javaPath 'bin';\
		$$currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User');\
		if($$currentPath -notlike \"*$$javaBinPath*\"){\
			Write-Host '  -> Adding Java to user PATH...' -ForegroundColor Cyan;\
			[Environment]::SetEnvironmentVariable('PATH', $$currentPath + ';' + $$javaBinPath, 'User');\
			$$env:PATH += ';' + $$javaBinPath;\
		};\
		Write-Host \"  -> Java 32-bit added to PATH: $$javaBinPath\" -ForegroundColor Green;\
		Write-Host '  -> Creating java32.exe alias...' -ForegroundColor Cyan;\
		Copy-Item (Join-Path $$javaBinPath 'java.exe') -Dest (Join-Path $$javaBinPath 'java32.exe') -Force;\
		Write-Host '  -> java32.exe alias created successfully!' -ForegroundColor Green;\
	} else {\
		Write-Host '  -> WARNING: Java 32-bit not found!' -ForegroundColor Red;\
	};\
	Write-Host '[STEP 5/10] Installing Zadig (USB drivers)...' -ForegroundColor Yellow;\
	Write-Host '  -> Installing Zadig...' -ForegroundColor Cyan;\
	choco upgrade -y zadig;\
	Write-Host '  -> Zadig installed!' -ForegroundColor Green;\
	Write-Host '[STEP 6/10] Creating TempestSDR directory structure...' -ForegroundColor Yellow;\
	$$root='$(WIN_PREFIX)';\
	Write-Host \"  -> Creating directories in: $$root\" -ForegroundColor Cyan;\
	New-Item -ItemType Directory -Force -Path $$root\\JavaGUI | Out-Null;\
	New-Item -ItemType Directory -Force -Path $$root\\JavaGUI\\lib\\WINDOWS\\X86 | Out-Null;\
	New-Item -ItemType Directory -Force -Path $$root\\ExtIO | Out-Null;\
	Write-Host '  -> Directory structure created!' -ForegroundColor Green;\
	Write-Host '[STEP 7/10] Downloading TempestSDR JAR...' -ForegroundColor Yellow;\
	if(-not(Test-Path $$root\\JavaGUI\\JTempestSDR.jar)) {\
		Write-Host '  -> Downloading JTempestSDR.jar (may take 2-3 min)...' -ForegroundColor Cyan;\
		Invoke-WebRequest 'https://github.com/martinmarinov/TempestSDR/raw/master/Release/JavaGUI/JTempestSDR.jar' -OutFile $$root\\JavaGUI\\JTempestSDR.jar;\
		Write-Host '  -> JTempestSDR.jar downloaded!' -ForegroundColor Green;\
	} else {\
		Write-Host '  -> JTempestSDR.jar already present, skipping...' -ForegroundColor Green;\
	};\
	Write-Host '[STEP 7b/10] Downloading TempestSDR plugins...' -ForegroundColor Yellow;\
	$$plugins=@('TSDRPlugin_RawFile.dll','TSDRPlugin_ExtIO.dll');\
	foreach($$dll in $$plugins){\
		$$dllPath = \"$$root\\JavaGUI\\lib\\WINDOWS\\X86\\$$dll\";\
		if(-not(Test-Path $$dllPath)) {\
			try {\
				Write-Host \"  -> Downloading $$dll...\" -ForegroundColor Cyan;\
				Invoke-WebRequest \"https://github.com/martinmarinov/TempestSDR/raw/master/Release/dlls/WINDOWS/X86/$$dll\" -OutFile $$dllPath;\
				Write-Host \"  -> $$dll downloaded!\" -ForegroundColor Green;\
			} catch {\
				Write-Host \"  -> WARNING: Plugin $$dll not found\" -ForegroundColor Red;\
			}\
		} else {\
			Write-Host \"  -> $$dll already present\" -ForegroundColor Green;\
		}\
	};\
	Write-Host '[STEP 8/10] Installing UHD 3.9.4 (USRP)...' -ForegroundColor Yellow;\
	Write-Host '  -> Downloading UHD installer (90MB, may take 5-10 min)...' -ForegroundColor Cyan;\
	$$uExe=$$env:TEMP+'\\uhd.exe'; Invoke-WebRequest '$(UHD_URL)' -OutFile $$uExe;\
	Write-Host '  -> UHD download complete, installing silently...' -ForegroundColor Cyan;\
	Start-Process $$uExe -ArgumentList '/S' -Wait;\
	Write-Host '  -> UHD installed! Searching for libusb-1.0.dll...' -ForegroundColor Green;\
	$$uhdPaths = @(\
		'C:\\Program Files\\UHD\\bin\\libusb-1.0.dll',\
		'C:\\Program Files (x86)\\UHD\\bin\\libusb-1.0.dll',\
		'C:\\Program Files\\UHD\\lib\\libusb-1.0.dll',\
		'C:\\Program Files (x86)\\UHD\\lib\\libusb-1.0.dll'\
	);\
	$$uhdFound = $$false;\
	foreach($$path in $$uhdPaths) {\
		Write-Host \"  -> Checking: $$path\" -ForegroundColor Cyan;\
		if(Test-Path $$path) {\
			Copy-Item $$path -Dest $$root\\JavaGUI\\lib\\WINDOWS\\X86 -Force;\
			Write-Host \"  -> Found and copied: $$path\" -ForegroundColor Green;\
			$$uhdFound = $$true;\
			break;\
		}\
	};\
	if(-not $$uhdFound) { \
		Write-Host '  -> UHD libusb-1.0.dll not found, downloading standalone version...' -ForegroundColor Yellow;\
		try {\
			Invoke-WebRequest 'https://github.com/libusb/libusb/releases/download/v1.0.26/libusb-1.0.26-binaries.7z' -OutFile $$env:TEMP\\libusb.7z;\
			Write-Host '  -> Standalone libusb downloaded (manual extraction required)' -ForegroundColor Yellow;\
		} catch { Write-Host '  -> WARNING: Failed to download libusb-1.0.dll' -ForegroundColor Red }\
	};\
	Write-Host '[STEP 9/10] Installing HackRF...' -ForegroundColor Yellow;\
	if(-not(Test-Path $$env:TEMP\\hr\\hackrf_info.exe)) {\
		Write-Host '  -> Downloading HackRF tools (may take 3-5 min)...' -ForegroundColor Cyan;\
		$$z=$$env:TEMP+'\\hackrf.zip';\
		try {\
			Remove-Item $$z -Force -ErrorAction SilentlyContinue;\
			Invoke-WebRequest '$(HRF_URL)' -OutFile $$z;\
			Write-Host '  -> Verifying file size...' -ForegroundColor Cyan;\
			if((Get-Item $$z).Length -lt 1000) {\
				throw 'Downloaded file too small';\
			};\
			Write-Host '  -> Extracting HackRF archive...' -ForegroundColor Cyan;\
			Expand-Archive $$z -Dest $$env:TEMP\\hr -Force;\
			Write-Host '  -> HackRF downloaded and extracted!' -ForegroundColor Green;\
		} catch {\
			Write-Host '  -> HackRF download failed, trying alternative URL...' -ForegroundColor Yellow;\
			try {\
				Remove-Item $$z -Force -ErrorAction SilentlyContinue;\
				Invoke-WebRequest 'https://github.com/greatscottgadgets/hackrf/releases/download/v$(HRF_VER)/hackrf-$(HRF_VER).zip' -OutFile $$z;\
				Expand-Archive $$z -Dest $$env:TEMP\\hr -Force;\
				Write-Host '  -> HackRF downloaded via alternative URL!' -ForegroundColor Green;\
			} catch {\
				Write-Host '  -> ERROR: Both HackRF URLs failed. Manual download required.' -ForegroundColor Red;\
			}\
		};\
	} else {\
		Write-Host '  -> HackRF tools already downloaded' -ForegroundColor Green;\
	};\
	Write-Host '[STEP 10/10] Downloading ExtIO drivers...' -ForegroundColor Yellow;\
	if(-not(Test-Path $$root\\ExtIO\\ExtIO_HackRF.dll)) {\
		try {\
			Write-Host '  -> Downloading ExtIO_HackRF.dll...' -ForegroundColor Cyan;\
			Invoke-WebRequest 'https://github.com/jocover/ExtIO_HackRF/releases/download/v1.0/ExtIO_HackRF.dll' -OutFile $$root\\ExtIO\\ExtIO_HackRF.dll;\
			Write-Host '  -> ExtIO_HackRF.dll downloaded!' -ForegroundColor Green;\
		} catch { Write-Host '  -> WARNING: ExtIO_HackRF.dll download failed' -ForegroundColor Red };\
	} else {\
		Write-Host '  -> ExtIO_HackRF.dll already present' -ForegroundColor Green;\
	};\
	if(-not(Test-Path $$root\\ExtIO\\ExtIO_USRP.dll)) {\
		Write-Host '  -> Downloading ExtIO package (USRP + others)...' -ForegroundColor Cyan;\
		try {\
			$$extioZip=$$env:TEMP+'\\extio_package.zip';\
			Invoke-WebRequest 'http://spench.net/drupal/files/ExtIO_USRP+FCD+RTL2832U+BorIP_Setup.zip' -OutFile $$extioZip;\
			Write-Host '  -> Extracting ExtIO package...' -ForegroundColor Cyan;\
			Expand-Archive $$extioZip -Dest $$env:TEMP\\extio_temp -Force;\
			if(Test-Path $$env:TEMP\\extio_temp\\ExtIO_USRP.dll) { Copy-Item $$env:TEMP\\extio_temp\\ExtIO_USRP.dll -Dest $$root\\ExtIO\\ -Force };\
			if(Test-Path $$env:TEMP\\extio_temp\\*\\ExtIO_USRP.dll) { Copy-Item $$env:TEMP\\extio_temp\\*\\ExtIO_USRP.dll -Dest $$root\\ExtIO\\ -Force };\
			Write-Host '  -> ExtIO_USRP.dll extracted successfully!' -ForegroundColor Green;\
		} catch { Write-Host '  -> WARNING: ExtIO package download/extraction failed' -ForegroundColor Red };\
	} else {\
		Write-Host '  -> ExtIO_USRP.dll already present' -ForegroundColor Green;\
	};\
	Write-Host '[FINALIZATION] Adding tools to system PATH...' -ForegroundColor Yellow;\
	$$currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User');\
	$$uhdPath = if(Test-Path 'C:\\Program Files\\UHD\\bin') { 'C:\\Program Files\\UHD\\bin' } else { 'C:\\Program Files (x86)\\UHD\\bin' };\
	$$hackrfPath = $$root + '\\tools';\
	$$extioPath = $$root + '\\ExtIO';\
	Write-Host \"  -> Configuring UHD PATH: $$uhdPath\" -ForegroundColor Cyan;\
	if($$currentPath -notlike \"*$$uhdPath*\"){\
		[Environment]::SetEnvironmentVariable('PATH', $$currentPath + ';' + $$uhdPath, 'User');\
		$$env:PATH += ';' + $$uhdPath;\
		Write-Host '  -> UHD added to PATH' -ForegroundColor Green;\
	} else {\
		Write-Host '  -> UHD already in PATH' -ForegroundColor Green;\
	};\
	Write-Host \"  -> Configuring HackRF PATH: $$hackrfPath\" -ForegroundColor Cyan;\
	if($$currentPath -notlike \"*$$hackrfPath*\"){\
		[Environment]::SetEnvironmentVariable('PATH', [Environment]::GetEnvironmentVariable('PATH', 'User') + ';' + $$hackrfPath, 'User');\
		$$env:PATH += ';' + $$hackrfPath;\
		Write-Host '  -> HackRF added to PATH' -ForegroundColor Green;\
	} else {\
		Write-Host '  -> HackRF already in PATH' -ForegroundColor Green;\
	};\
	Write-Host \"  -> Configuring ExtIO PATH: $$extioPath\" -ForegroundColor Cyan;\
	if($$currentPath -notlike \"*$$extioPath*\"){\
		[Environment]::SetEnvironmentVariable('PATH', [Environment]::GetEnvironmentVariable('PATH', 'User') + ';' + $$extioPath, 'User');\
		$$env:PATH += ';' + $$extioPath;\
		Write-Host '  -> ExtIO added to PATH' -ForegroundColor Green;\
	} else {\
		Write-Host '  -> ExtIO already in PATH' -ForegroundColor Green;\
	};\
	Write-Host '';\
	Write-Host '=== INSTALLATION COMPLETE ===' -ForegroundColor Green;\
	Write-Host '';\
	Write-Host 'STEP 1: Install USB drivers' -ForegroundColor Yellow;\
	Write-Host '  Run Zadig and install drivers for HackRF/USRP';\
	Write-Host '';\
	Write-Host 'STEP 2: Test your devices' -ForegroundColor Yellow;\
	Write-Host '  UHD/USRP : uhd_find_devices';\
	Write-Host '  HackRF   : hackrf_info';\
	Write-Host '';\
	Write-Host 'STEP 3: Launch TempestSDR' -ForegroundColor Yellow;\
	Write-Host \"  java32 -jar $$root\\JavaGUI\\JTempestSDR.jar\";\
	Write-Host \"  OR: java -jar $$root\\JavaGUI\\JTempestSDR.jar\";\
	Write-Host '';\
	Write-Host \"ExtIO files available in: $$root\\ExtIO\\\" -ForegroundColor Cyan;\
	Write-Host 'TempestSDR will auto-load ExtIO_HackRF.dll and ExtIO_USRP.dll';\
	Write-Host '';\
	Write-Host 'NOTE: UHD 3.9.4 installed for FPGA v4 compatibility with ExtIO_USRP' -ForegroundColor Gray;\
	Write-Host 'NOTE: Restart terminal to use new PATH variables' -ForegroundColor Gray;\
	Write-Host 'NOTE: Use java32 command for guaranteed 32-bit Java execution' -ForegroundColor Gray;\
	"
	@echo windows > windows

# --------------------------------------------------------------
# CLEAN
# --------------------------------------------------------------
.PHONY: clean clean-linux clean-windows

clean: clean-$(TARGET_OS)

clean-linux:
	@echo ">>> cleaning Linux build artifacts"
	@if [ -d $(SRC_DIR) ]; then \
		$(MAKE) -k -C $(SRC_DIR) clean 2>/dev/null || true; \
		rm -rf $(SRC_DIR)/JavaGUI/lib/LINUX/*; \
		rm -f $(SRC_DIR)/JavaGUI/JTempestSDR.jar; \
	fi
	@rm -rf $(HACKRF_GUI_DIR)
	@rm -f linux
	@echo "Linux artifacts cleaned"

clean-windows:
	@echo ">>> cleaning Windows build artifacts"
	powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "\
	if (Test-Path '$(WIN_PREFIX)') { \
		if (Test-Path '$(WIN_PREFIX)\\JavaGUI\\lib\\WINDOWS\\X86') { \
			Remove-Item -Recurse -Force '$(WIN_PREFIX)\\JavaGUI\\lib\\WINDOWS\\X86' -ErrorAction SilentlyContinue; \
		} \
		if (Test-Path '$(WIN_PREFIX)\\JavaGUI\\JTempestSDR.jar') { \
			Remove-Item -Force '$(WIN_PREFIX)\\JavaGUI\\JTempestSDR.jar' -ErrorAction SilentlyContinue; \
		} \
	}; \
	if (Test-Path 'windows') { Remove-Item -Force 'windows' -ErrorAction SilentlyContinue }; \
	Write-Host 'Windows artifacts cleaned'"
