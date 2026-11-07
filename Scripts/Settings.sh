#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "/attendedsysupgrade/d" {} +
#修改默认主题
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" {} +
#修改immortalwrt.lan关联IP
find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" -exec sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" {} +
#添加编译日期标识
find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" -exec sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" {} +

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"

if [ -f "$WIFI_SH" ]; then
    sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
    sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
    # 2.4G SSID（第1个ssid）
    sed -i "0,/ssid='[^']*'/s/ssid='[^']*'/ssid='$WRT_SSID'/" $WIFI_UC
    # 5G SSID（第2个ssid）
    sed -i "0,/ssid='[^']*'/s/ssid='[^']*'/ssid='$WRT_SSID_5G'/" $WIFI_UC
    sed -i "s/country='.*'/country='CN'/g" $WIFI_UC
    if [ -z "$WRT_WORD" ]; then
        sed -i "s/encryption='.*'/encryption='none'/g" $WIFI_UC
        sed -i "/key='.*'/d" $WIFI_UC
    else
        sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
        sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" $WIFI_UC
    fi
fi

# UCI默认脚本，确保2.4G/5G SSID正确分离
UCI_FIX="./package/base-files/files/etc/uci-defaults/99-wifi-ssid"
cat > $UCI_FIX << EOF
#!/bin/sh
uci set wireless.@wifi-iface[0].ssid='$WRT_SSID'
uci set wireless.@wifi-iface[1].ssid='$WRT_SSID_5G'
uci set wireless.@wifi-iface[0].key='$WRT_WORD'
uci set wireless.@wifi-iface[1].key='$WRT_WORD'
uci commit wireless
exit 0
EOF
chmod +x $UCI_FIX

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi
