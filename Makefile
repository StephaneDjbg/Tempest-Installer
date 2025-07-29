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
    Write-Host '=== DEBUT INSTALLATION TEMPEST SDR ===' -ForegroundColor Green;\
    Write-Host '[ETAPE 1/10] Verification Chocolatey...' -ForegroundColor Yellow;\
    if(-not(Get-Command choco -EA SilentlyContinue)){\
        Write-Host '  -> Chocolatey non trouve, installation en cours...' -ForegroundColor Cyan;\
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;\
        Write-Host '  -> Telechargement script Chocolatey...' -ForegroundColor Cyan;\
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'));\
        Write-Host '  -> Mise a jour PATH pour Chocolatey...' -ForegroundColor Cyan;\
        $$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User');\
        Write-Host '  -> Chocolatey installe avec succes!' -ForegroundColor Green;\
    } else {\
        Write-Host '  -> Chocolatey deja installe, passage a l''etape suivante' -ForegroundColor Green;\
    };\
    if(-not(Get-Command choco -EA SilentlyContinue)){\
        Write-Host '  -> Ajout manuel du PATH Chocolatey...' -ForegroundColor Yellow;\
        $$env:PATH += ';C:\\ProgramData\\chocolatey\\bin';\
    };\
    Write-Host '[ETAPE 2/10] Installation packages de base...' -ForegroundColor Yellow;\
    Write-Host '  -> Installation: git, cmake, python, vcredist (peut prendre 5-10 min)...' -ForegroundColor Cyan;\
    choco upgrade -y git cmake python vcredist140 vcredist2008;\
    Write-Host '  -> Packages de base installes!' -ForegroundColor Green;\
    Write-Host '[ETAPE 3/10] Installation Java 32-bit...' -ForegroundColor Yellow;\
    Write-Host '  -> Telechargement Java 8 JRE 32-bit (peut prendre 3-5 min)...' -ForegroundColor Cyan;\
    choco upgrade -y temurin8jre --x86;\
    Write-Host '  -> Java 32-bit installe!' -ForegroundColor Green;\
    Write-Host '[ETAPE 4/10] Configuration Java PATH et alias...' -ForegroundColor Yellow;\
    $$javaPath = Get-ChildItem 'C:\\Program Files (x86)\\Eclipse Adoptium\\' -Directory | Where-Object {$$_.Name -like 'jre-8*'} | Select-Object -First 1 -ExpandProperty FullName;\
    if($$javaPath) {\
        Write-Host \"  -> Java trouve dans: $$javaPath\" -ForegroundColor Cyan;\
        $$javaBinPath = Join-Path $$javaPath 'bin';\
        $$currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User');\
        if($$currentPath -notlike \"*$$javaBinPath*\"){\
            Write-Host '  -> Ajout Java au PATH utilisateur...' -ForegroundColor Cyan;\
            [Environment]::SetEnvironmentVariable('PATH', $$currentPath + ';' + $$javaBinPath, 'User');\
            $$env:PATH += ';' + $$javaBinPath;\
        };\
        Write-Host \"  -> Java 32-bit ajoute au PATH: $$javaBinPath\" -ForegroundColor Green;\
        Write-Host '  -> Creation alias java32.exe...' -ForegroundColor Cyan;\
        Copy-Item (Join-Path $$javaBinPath 'java.exe') -Dest (Join-Path $$javaBinPath 'java32.exe') -Force;\
        Write-Host '  -> Alias java32.exe cree avec succes!' -ForegroundColor Green;\
    } else {\
        Write-Host '  -> ATTENTION: Java 32-bit non trouve!' -ForegroundColor Red;\
    };\
    Write-Host '[ETAPE 5/10] Installation Zadig (drivers USB)...' -ForegroundColor Yellow;\
    Write-Host '  -> Installation Zadig...' -ForegroundColor Cyan;\
    choco upgrade -y zadig;\
    Write-Host '  -> Zadig installe!' -ForegroundColor Green;\
    Write-Host '[ETAPE 6/10] Creation structure TempestSDR...' -ForegroundColor Yellow;\
    $$root='$(WIN_PREFIX)';\
    Write-Host \"  -> Creation dossiers dans: $$root\" -ForegroundColor Cyan;\
    New-Item -ItemType Directory -Force -Path $$root\\JavaGUI | Out-Null;\
    New-Item -ItemType Directory -Force -Path $$root\\JavaGUI\\lib\\WINDOWS\\X86 | Out-Null;\
    New-Item -ItemType Directory -Force -Path $$root\\ExtIO | Out-Null;\
    Write-Host '  -> Structure de dossiers creee!' -ForegroundColor Green;\
    Write-Host '[ETAPE 7/10] Telechargement TempestSDR JAR...' -ForegroundColor Yellow;\
    if(-not(Test-Path $$root\\JavaGUI\\JTempestSDR.jar)) {\
        Write-Host '  -> Telechargement JTempestSDR.jar (peut prendre 2-3 min)...' -ForegroundColor Cyan;\
        Invoke-WebRequest 'https://github.com/martinmarinov/TempestSDR/raw/master/Release/JavaGUI/JTempestSDR.jar' -OutFile $$root\\JavaGUI\\JTempestSDR.jar;\
        Write-Host '  -> JTempestSDR.jar telecharge!' -ForegroundColor Green;\
    } else {\
        Write-Host '  -> JTempestSDR.jar deja present, passage a l''etape suivante' -ForegroundColor Green;\
    };\
    Write-Host '[ETAPE 7b/10] Telechargement plugins TempestSDR...' -ForegroundColor Yellow;\
    $$plugins=@('TSDRPlugin_RawFile.dll','TSDRPlugin_ExtIO.dll');\
    foreach($$dll in $$plugins){\
        $$dllPath = \"$$root\\JavaGUI\\lib\\WINDOWS\\X86\\$$dll\";\
        if(-not(Test-Path $$dllPath)) {\
            try {\
                Write-Host \"  -> Telechargement $$dll...\" -ForegroundColor Cyan;\
                Invoke-WebRequest \"https://github.com/martinmarinov/TempestSDR/raw/master/Release/dlls/WINDOWS/X86/$$dll\" -OutFile $$dllPath;\
                Write-Host \"  -> $$dll telecharge!\" -ForegroundColor Green;\
            } catch {\
                Write-Host \"  -> ATTENTION: Plugin $$dll introuvable\" -ForegroundColor Red;\
            }\
        } else {\
            Write-Host \"  -> $$dll deja present\" -ForegroundColor Green;\
        }\
    };\
    Write-Host '[ETAPE 8/10] Installation UHD 3.9.4 (USRP)...' -ForegroundColor Yellow;\
    Write-Host '  -> Telechargement UHD installer (90MB, peut prendre 5-10 min)...' -ForegroundColor Cyan;\
    $$uExe=$$env:TEMP+'\\uhd.exe'; Invoke-WebRequest '$(UHD_URL)' -OutFile $$uExe;\
    Write-Host '  -> Telechargement UHD termine, installation silencieuse...' -ForegroundColor Cyan;\
    Start-Process $$uExe -ArgumentList '/S' -Wait;\
    Write-Host '  -> UHD installe! Recherche libusb-1.0.dll...' -ForegroundColor Green;\
    $$uhdPaths = @(\
        'C:\\Program Files\\UHD\\bin\\libusb-1.0.dll',\
        'C:\\Program Files (x86)\\UHD\\bin\\libusb-1.0.dll',\
        'C:\\Program Files\\UHD\\lib\\libusb-1.0.dll',\
        'C:\\Program Files (x86)\\UHD\\lib\\libusb-1.0.dll'\
    );\
    $$uhdFound = $$false;\
    foreach($$path in $$uhdPaths) {\
        Write-Host \"  -> Verification: $$path\" -ForegroundColor Cyan;\
        if(Test-Path $$path) {\
            Copy-Item $$path -Dest $$root\\JavaGUI\\lib\\WINDOWS\\X86 -Force;\
            Write-Host \"  -> Trouve et copie: $$path\" -ForegroundColor Green;\
            $$uhdFound = $$true;\
            break;\
        }\
    };\
    if(-not $$uhdFound) { \
        Write-Host '  -> libusb-1.0.dll UHD non trouve, telechargement version standalone...' -ForegroundColor Yellow;\
        try {\
            Invoke-WebRequest 'https://github.com/libusb/libusb/releases/download/v1.0.26/libusb-1.0.26-binaries.7z' -OutFile $$env:TEMP\\libusb.7z;\
            Write-Host '  -> libusb standalone telecharge (extraction manuelle requise)' -ForegroundColor Yellow;\
        } catch { Write-Host '  -> ATTENTION: Echec telechargement libusb-1.0.dll' -ForegroundColor Red }\
    };\
    Write-Host '[ETAPE 9/10] Installation HackRF...' -ForegroundColor Yellow;\
    if(-not(Test-Path $$env:TEMP\\hr\\hackrf_info.exe)) {\
        Write-Host '  -> Telechargement outils HackRF (peut prendre 3-5 min)...' -ForegroundColor Cyan;\
        $$z=$$env:TEMP+'\\hackrf.zip';\
        try {\
            Remove-Item $$z -Force -ErrorAction SilentlyContinue;\
            Invoke-WebRequest '$(HRF_URL)' -OutFile $$z;\
            Write-Host '  -> Verification taille fichier...' -ForegroundColor Cyan;\
            if((Get-Item $$z).Length -lt 1000) {\
                throw 'Downloaded file too small';\
            };\
            Write-Host '  -> Extraction archive HackRF...' -ForegroundColor Cyan;\
            Expand-Archive $$z -Dest $$env:TEMP\\hr -Force;\
            Write-Host '  -> HackRF telecharge et extrait!' -ForegroundColor Green;\
        } catch {\
            Write-Host '  -> Echec telechargement HackRF, tentative URL alternative...' -ForegroundColor Yellow;\
            try {\
                Remove-Item $$z -Force -ErrorAction SilentlyContinue;\
                Invoke-WebRequest 'https://github.com/greatscottgadgets/hackrf/releases/download/v$(HRF_VER)/hackrf-$(HRF_VER).zip' -OutFile $$z;\
                Expand-Archive $$z -Dest $$env:TEMP\\hr -Force;\
                Write-Host '  -> HackRF telecharge via URL alternative!' -ForegroundColor Green;\
            } catch {\
                Write-Host '  -> ERREUR: Echec des deux URLs HackRF. Telechargement manuel requis.' -ForegroundColor Red;\
            }\
        };\
    } else {\
        Write-Host '  -> Outils HackRF deja telecharges' -ForegroundColor Green;\
    };\
    Write-Host '[ETAPE 10/10] Telechargement drivers ExtIO...' -ForegroundColor Yellow;\
    if(-not(Test-Path $$root\\ExtIO\\ExtIO_HackRF.dll)) {\
        try {\
            Write-Host '  -> Telechargement ExtIO_HackRF.dll...' -ForegroundColor Cyan;\
            Invoke-WebRequest 'https://github.com/jocover/ExtIO_HackRF/releases/download/v1.0/ExtIO_HackRF.dll' -OutFile $$root\\ExtIO\\ExtIO_HackRF.dll;\
            Write-Host '  -> ExtIO_HackRF.dll telecharge!' -ForegroundColor Green;\
        } catch { Write-Host '  -> ATTENTION: Echec telechargement ExtIO_HackRF.dll' -ForegroundColor Red };\
    } else {\
        Write-Host '  -> ExtIO_HackRF.dll deja present' -ForegroundColor Green;\
    };\
    if(-not(Test-Path $$root\\ExtIO\\ExtIO_USRP.dll)) {\
        Write-Host '  -> Telechargement package ExtIO (USRP + autres)...' -ForegroundColor Cyan;\
        try {\
            $$extioZip=$$env:TEMP+'\\extio_package.zip';\
            Invoke-WebRequest 'http://spench.net/drupal/files/ExtIO_USRP+FCD+RTL2832U+BorIP_Setup.zip' -OutFile $$extioZip;\
            Write-Host '  -> Extraction package ExtIO...' -ForegroundColor Cyan;\
            Expand-Archive $$extioZip -Dest $$env:TEMP\\extio_temp -Force;\
            if(Test-Path $$env:TEMP\\extio_temp\\ExtIO_USRP.dll) { Copy-Item $$env:TEMP\\extio_temp\\ExtIO_USRP.dll -Dest $$root\\ExtIO\\ -Force };\
            if(Test-Path $$env:TEMP\\extio_temp\\*\\ExtIO_USRP.dll) { Copy-Item $$env:TEMP\\extio_temp\\*\\ExtIO_USRP.dll -Dest $$root\\ExtIO\\ -Force };\
            Write-Host '  -> ExtIO_USRP.dll extrait avec succes!' -ForegroundColor Green;\
        } catch { Write-Host '  -> ATTENTION: Echec telechargement/extraction package ExtIO' -ForegroundColor Red };\
    } else {\
        Write-Host '  -> ExtIO_USRP.dll deja present' -ForegroundColor Green;\
    };\
    Write-Host '[FINALISATION] Ajout outils au PATH systeme...' -ForegroundColor Yellow;\
    $$currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User');\
    $$uhdPath = if(Test-Path 'C:\\Program Files\\UHD\\bin') { 'C:\\Program Files\\UHD\\bin' } else { 'C:\\Program Files (x86)\\UHD\\bin' };\
    $$hackrfPath = $$root + '\\tools';\
    $$extioPath = $$root + '\\ExtIO';\
    Write-Host \"  -> Configuration PATH UHD: $$uhdPath\" -ForegroundColor Cyan;\
    if($$currentPath -notlike \"*$$uhdPath*\"){\
        [Environment]::SetEnvironmentVariable('PATH', $$currentPath + ';' + $$uhdPath, 'User');\
        $$env:PATH += ';' + $$uhdPath;\
        Write-Host '  -> UHD ajoute au PATH' -ForegroundColor Green;\
    } else {\
        Write-Host '  -> UHD deja dans le PATH' -ForegroundColor Green;\
    };\
    Write-Host \"  -> Configuration PATH HackRF: $$hackrfPath\" -ForegroundColor Cyan;\
    if($$currentPath -notlike \"*$$hackrfPath*\"){\
        [Environment]::SetEnvironmentVariable('PATH', [Environment]::GetEnvironmentVariable('PATH', 'User') + ';' + $$hackrfPath, 'User');\
        $$env:PATH += ';' + $$hackrfPath;\
        Write-Host '  -> HackRF ajoute au PATH' -ForegroundColor Green;\
    } else {\
        Write-Host '  -> HackRF deja dans le PATH' -ForegroundColor Green;\
    };\
    Write-Host \"  -> Configuration PATH ExtIO: $$extioPath\" -ForegroundColor Cyan;\
    if($$currentPath -notlike \"*$$extioPath*\"){\
        [Environment]::SetEnvironmentVariable('PATH', [Environment]::GetEnvironmentVariable('PATH', 'User') + ';' + $$extioPath, 'User');\
        $$env:PATH += ';' + $$extioPath;\
        Write-Host '  -> ExtIO ajoute au PATH' -ForegroundColor Green;\
    } else {\
        Write-Host '  -> ExtIO deja dans le PATH' -ForegroundColor Green;\
    };\
    Write-Host '';\
    Write-Host '=== INSTALLATION COMPLETE ===' -ForegroundColor Green;\
    Write-Host '';\
    Write-Host 'ETAPE 1: Installer drivers USB' -ForegroundColor Yellow;\
    Write-Host '  Run Zadig and install drivers for HackRF/USRP';\
    Write-Host '';\
    Write-Host 'ETAPE 2: Tester vos peripheriques' -ForegroundColor Yellow;\
    Write-Host '  UHD/USRP : uhd_find_devices';\
    Write-Host '  HackRF   : hackrf_info';\
    Write-Host '';\
    Write-Host 'ETAPE 3: Lancer TempestSDR' -ForegroundColor Yellow;\
    Write-Host \"  java32 -jar $$root\\JavaGUI\\JTempestSDR.jar\";\
    Write-Host \"  OU: java -jar $$root\\JavaGUI\\JTempestSDR.jar\";\
    Write-Host '';\
    Write-Host \"ExtIO files disponibles dans: $$root\\ExtIO\\\" -ForegroundColor Cyan;\
    Write-Host 'TempestSDR chargera automatiquement ExtIO_HackRF.dll et ExtIO_USRP.dll';\
    Write-Host '';\
    Write-Host 'NOTE: UHD 3.9.4 installe pour compatibilite FPGA v4 avec ExtIO_USRP' -ForegroundColor Gray;\
    Write-Host 'NOTE: Redemarrer le terminal pour utiliser les nouvelles variables PATH' -ForegroundColor Gray;\
    Write-Host 'NOTE: Utiliser java32 pour garantir execution Java 32-bit' -ForegroundColor Gray;\
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
