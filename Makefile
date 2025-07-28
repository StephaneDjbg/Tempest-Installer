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
	Write-Host '>>> Installing Chocolatey (if needed)';\
	if(-not(Get-Command choco -EA SilentlyContinue)){\
		[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;\
		iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'));\
		$$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User');\
	};\
	if(-not(Get-Command choco -EA SilentlyContinue)){\
		$$env:PATH += ';C:\\ProgramData\\chocolatey\\bin';\
	};\
	Write-Host '>>> Installing base packages';\
	choco upgrade -y git cmake python vcredist140 vcredist2008;\
	Write-Host '>>> Installing Java 32-bit (required for TempestSDR)';\
	choco upgrade -y temurin8jre --x86;\
	Write-Host '>>> Adding Java 32-bit to PATH with alias';\
	$$javaPath = Get-ChildItem 'C:\\Program Files (x86)\\Eclipse Adoptium\\' -Directory | Where-Object {$$_.Name -like 'jre-8*'} | Select-Object -First 1 -ExpandProperty FullName;\
    if($$javaPath) {\
        $$javaBinPath = Join-Path $$javaPath 'bin';\
        $$currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User');\
        if($$currentPath -notlike \"*$$javaBinPath*\"){\
            [Environment]::SetEnvironmentVariable('PATH', $$currentPath + ';' + $$javaBinPath, 'User');\
            $$env:PATH += ';' + $$javaBinPath;\
        };\
        Write-Host \"Java 32-bit added to PATH: $$javaBinPath\";\
        Copy-Item (Join-Path $$javaBinPath 'java.exe') -Dest (Join-Path $$javaBinPath 'java32.exe') -Force;\
        Write-Host 'Created java32.exe alias for 32-bit Java';\
    } else {\
        Write-Host 'Warning: Could not find Java 32-bit installation path';\
    };\
    Write-Host '>>> Installing Zadig (USB drivers)';\
	choco upgrade -y zadig;\
	Write-Host '>>> Creating TempestSDR directory';\
	$$root='$(WIN_PREFIX)'; New-Item -ItemType Directory -Force -Path $$root\\JavaGUI | Out-Null;\
	New-Item -ItemType Directory -Force -Path $$root\\JavaGUI\\lib\\WINDOWS\\X86 | Out-Null;\
	New-Item -ItemType Directory -Force -Path $$root\\ExtIO | Out-Null;\
	Write-Host '>>> Downloading TempestSDR JAR (precompiled)';\
	if(-not(Test-Path $$root\\JavaGUI\\JTempestSDR.jar)) {\
		Write-Host 'Downloading JTempestSDR.jar...';\
		Invoke-WebRequest 'https://github.com/martinmarinov/TempestSDR/raw/master/Release/JavaGUI/JTempestSDR.jar' -OutFile $$root\\JavaGUI\\JTempestSDR.jar;\
	} else {\
		Write-Host 'JTempestSDR.jar already exists, skipping download';\
	};\
	Write-Host '>>> Downloading TempestSDR plugins (Windows X86)';\
    $$plugins=@('TSDRLibraryNDK.dll','TSDRPlugin_ExtIO.dll','TSDRPlugin_Mirics.dll','TSDRPlugin_RawFile.dll');\
    foreach($$dll in $$plugins){\
        $$dllPath = \"$$root\\JavaGUI\\lib\\WINDOWS\\X86\\$$dll\";\
        if(-not(Test-Path $$dllPath)) {\
            try {\
                Write-Host \"Downloading $$dll...\";\
                Invoke-WebRequest \"https://github.com/martinmarinov/TempestSDR/raw/master/Release/dlls/WINDOWS/X86/$$dll\" -OutFile $$dllPath;\
            } catch {\
                Write-Host \"Plugin $$dll not found\";\
            }\
        } else {\
            Write-Host \"$$dll already exists, skipping download\";\
        }\
    };\
	Write-Host '>>> Installing UHD 3.9.4 (USRP drivers and tools - FPGA v4 compatible)';\
    $$uExe=$$env:TEMP+'\\uhd.exe'; Invoke-WebRequest '$(UHD_URL)' -OutFile $$uExe;\
    Start-Process $$uExe -ArgumentList '/S' -Wait;\
    Write-Host 'Searching for UHD installation and libusb-1.0.dll...';\
    $$uhdPaths = @(\
        'C:\\Program Files\\UHD\\bin\\libusb-1.0.dll',\
        'C:\\Program Files (x86)\\UHD\\bin\\libusb-1.0.dll',\
        'C:\\Program Files\\UHD\\lib\\libusb-1.0.dll',\
        'C:\\Program Files (x86)\\UHD\\lib\\libusb-1.0.dll'\
    );\
    $$uhdFound = $$false;\
    foreach($$path in $$uhdPaths) {\
        if(Test-Path $$path) {\
            Copy-Item $$path -Dest $$root\\JavaGUI\\lib\\WINDOWS\\X86 -Force;\
            Write-Host \"Found UHD libusb at: $$path\";\
            $$uhdFound = $$true;\
            break;\
        }\
    };\
    if(-not $$uhdFound) { \
        Write-Host 'UHD libusb-1.0.dll not found, trying to download standalone version...';\
        try {\
            Invoke-WebRequest 'https://github.com/libusb/libusb/releases/download/v1.0.26/libusb-1.0.26-binaries.7z' -OutFile $$env:TEMP\\libusb.7z;\
            Write-Host 'Downloaded standalone libusb (extract manually if needed)';\
        } catch { Write-Host 'Warning: Could not find or download libusb-1.0.dll' }\
    };\
	Write-Host '>>> Installing HackRF (drivers and tools)';\
    if(-not(Test-Path $$env:TEMP\\hr\\hackrf_info.exe)) {\
        Write-Host 'Downloading HackRF tools...';\
        $$z=$$env:TEMP+'\\hackrf.zip'; Invoke-WebRequest '$(HRF_URL)' -OutFile $$z;\
        Expand-Archive $$z -Dest $$env:TEMP\\hr -Force;\
    } else {\
        Write-Host 'HackRF tools already downloaded, skipping...';\
    };\
    $$hrFiles = Get-ChildItem -Path $$env:TEMP\\hr -Recurse -Name '*hackrf*.dll';\
    foreach($$file in $$hrFiles) {\
        $$fullPath = Join-Path $$env:TEMP\\hr $$file;\
        Copy-Item $$fullPath -Dest $$root\\JavaGUI\\lib\\WINDOWS\\X86 -Force;\
        Write-Host \"Copied: $$file\";\
    };\
	New-Item -ItemType Directory -Force -Path $$root\\tools | Out-Null;\
	$$hrExes = Get-ChildItem -Path $$env:TEMP\\hr -Recurse -Name 'hackrf*.exe';\
	foreach($$exe in $$hrExes) {\
		$$fullPath = Join-Path $$env:TEMP\\hr $$exe;\
		Copy-Item $$fullPath -Dest $$root\\tools -Force;\
		Write-Host \"Copied tool: $$exe\";\
	};\
	Write-Host '>>> Downloading ExtIO drivers';\
    if(-not(Test-Path $$root\\ExtIO\\ExtIO_HackRF.dll)) {\
        try {\
            Write-Host 'Downloading ExtIO_HackRF.dll...';\
            Invoke-WebRequest 'https://github.com/jocover/ExtIO_HackRF/releases/download/v1.0/ExtIO_HackRF.dll' -OutFile $$root\\ExtIO\\ExtIO_HackRF.dll;\
        } catch { Write-Host 'ExtIO_HackRF.dll download failed' };\
    } else {\
        Write-Host 'ExtIO_HackRF.dll already exists, skipping download';\
    };\
    if(-not(Test-Path $$root\\ExtIO\\ExtIO_USRP.dll)) {\
        Write-Host 'Downloading ExtIO package (USRP + others)';\
        try {\
            $$extioZip=$$env:TEMP+'\\extio_package.zip';\
            Invoke-WebRequest 'http://spench.net/drupal/files/ExtIO_USRP+FCD+RTL2832U+BorIP_Setup.zip' -OutFile $$extioZip;\
            Expand-Archive $$extioZip -Dest $$env:TEMP\\extio_temp -Force;\
            if(Test-Path $$env:TEMP\\extio_temp\\ExtIO_USRP.dll) { Copy-Item $$env:TEMP\\extio_temp\\ExtIO_USRP.dll -Dest $$root\\ExtIO\\ -Force };\
            if(Test-Path $$env:TEMP\\extio_temp\\*\\ExtIO_USRP.dll) { Copy-Item $$env:TEMP\\extio_temp\\*\\ExtIO_USRP.dll -Dest $$root\\ExtIO\\ -Force };\
            Write-Host 'ExtIO_USRP.dll extracted successfully';\
        } catch { Write-Host 'ExtIO package download/extraction failed' };\
    } else {\
        Write-Host 'ExtIO_USRP.dll already exists, skipping download';\
    };\
	Write-Host '>>> Adding tools to system PATH';\
    $$currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User');\
    $$uhdPath = if(Test-Path 'C:\\Program Files\\UHD\\bin') { 'C:\\Program Files\\UHD\\bin' } else { 'C:\\Program Files (x86)\\UHD\\bin' };\
    $$hackrfPath = $$root + '\\tools';\
    $$extioPath = $$root + '\\ExtIO';\
    if($$currentPath -notlike \"*$$uhdPath*\"){\
        [Environment]::SetEnvironmentVariable('PATH', $$currentPath + ';' + $$uhdPath, 'User');\
        $$env:PATH += ';' + $$uhdPath;\
    };\
	if($$currentPath -notlike \"*$$hackrfPath*\"){\
		[Environment]::SetEnvironmentVariable('PATH', [Environment]::GetEnvironmentVariable('PATH', 'User') + ';' + $$hackrfPath, 'User');\
		$$env:PATH += ';' + $$hackrfPath;\
	};\
	if($$currentPath -notlike \"*$$extioPath*\"){\
		[Environment]::SetEnvironmentVariable('PATH', [Environment]::GetEnvironmentVariable('PATH', 'User') + ';' + $$extioPath, 'User');\
		$$env:PATH += ';' + $$extioPath;\
	};\
	Write-Host '';\
	Write-Host '=== INSTALLATION COMPLETE ===';\
	Write-Host '';\
	Write-Host 'STEP 1: Install USB drivers';\
	Write-Host '  Run Zadig and install drivers for HackRF/USRP';\
	Write-Host '';\
	Write-Host 'STEP 2: Test your devices';\
	Write-Host '  UHD/USRP : uhd_find_devices';\
	Write-Host '  HackRF   : hackrf_info';\
	Write-Host '';\
	Write-Host 'STEP 3: Launch TempestSDR';\
	Write-Host '  java32 -jar $$root\\JavaGUI\\JTempestSDR.jar';\
	Write-Host '  OR: java -jar $$root\\JavaGUI\\JTempestSDR.jar';\
	Write-Host '';\
	Write-Host 'ExtIO files available in: $$root\\ExtIO\\';\
	Write-Host 'TempestSDR will auto-load ExtIO_HackRF.dll and ExtIO_USRP.dll';\
	Write-Host '';\
	Write-Host 'NOTE: UHD 3.9.4 installed for FPGA v4 compatibility with ExtIO_USRP';\
	Write-Host 'NOTE: Restart terminal to use new PATH variables';\
	Write-Host 'NOTE: Use java32 command for guaranteed 32-bit Java execution';\
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
