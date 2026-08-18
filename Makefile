TARGET = iphone:clang:latest:15.0
ARCHS = arm64 arm64e

# 根据参数选择打包方案
ifeq ($(SCHEME),roothide)
export THEOS_PACKAGE_SCHEME = roothide
else ifeq ($(SCHEME),rootless)
export THEOS_PACKAGE_SCHEME = rootless
else
unexport THEOS_PACKAGE_SCHEME
endif

# 在GitHub Actions中运行时的特殊配置
ifeq ($(GITHUB_ACTIONS),true)
export INSTALL = 0
export FINALPACKAGE = 1
endif

export DEBUG = 0
INSTALL_TARGET_PROCESSES = QQ

include $(THEOS)/makefiles/common.mk


TWEAK_NAME = QQLite

$(TWEAK_NAME)_FILES = QQTweakDemo.xm QQTweakAntiRecall.xm QQTweakSettingsViewController.m QQTweakAboutViewController.m QQTweakListBuilder.m QQTweakAlert.m QQTweakPrefs.m

$(TWEAK_NAME)_CFLAGS = -fobjc-arc -w
$(TWEAK_NAME)_LDFLAGS = -lz

$(TWEAK_NAME)_CFLAGS += -I$(THEOS_PROJECT_DIR)/include

$(TWEAK_NAME)_LOGOS_DEFAULT_GENERATOR = internal
CXXFLAGS += -std=c++11
CCFLAGS += -std=c++11

export THEOS_STRICT_LOGOS=0
export ERROR_ON_WARNINGS=0
export LOGOS_DEFAULT_GENERATOR=internal

include $(THEOS_MAKE_PATH)/tweak.mk

THEOS_DEVICE_IP = 192.168.15.246

THEOS_DEVICE_PORT = 22

# 清理 packages 目录
clean::
	@echo -e "\033[31m==>\033[0m Cleaning packages…"
	@rm -rf .theos packages

# 编译并自动安装
after-package::
	@echo -e "\033[32m==>\033[0m Packaging complete."
	@if [ "$(GITHUB_ACTIONS)" != "true" ] && [ "$(INSTALL)" = "1" ]; then \
        DEB_FILE=$$(ls -t packages/*.deb | head -1); \
        PACKAGE_NAME=$$(basename "$$DEB_FILE" | cut -d'_' -f1); \
        echo -e "\033[34m==>\033[0m Installing $$PACKAGE_NAME to device…"; \
        ssh root@$(THEOS_DEVICE_IP) "rm -rf /tmp/$${PACKAGE_NAME}.deb"; \
        scp "$$DEB_FILE" root@$(THEOS_DEVICE_IP):/tmp/$${PACKAGE_NAME}.deb; \
        ssh root@$(THEOS_DEVICE_IP) "dpkg -i --force-overwrite /tmp/$${PACKAGE_NAME}.deb && rm -f /tmp/$${PACKAGE_NAME}.deb"; \
	else \
        echo -e "\033[33m==>\033[0m Skipping installation (GitHub Actions environment or INSTALL!=1)"; \
	fi
