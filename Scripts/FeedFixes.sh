#!/bin/bash
# SPDX-License-Identifier: MIT

# 目标级热修：摘除 mediatek 目标 DEFAULT_PACKAGES 中本仓已显式 =n 却被强制拉回的包
# 在 Custom Packages 步骤（feeds update/install 之后、make defconfig 之前）执行。
#
# 背景（2026-10-19）：上游源（immortalwrt-mt798x-6.6-padavanonly）的
#   target/linux/mediatek/Makefile 的 DEFAULT_PACKAGES 含
#     ... kmod-fs-btrfs automount blkid blockdev fdisk \
#         kmod-dummy kmod-usb2 kmod-usb3 kmod-usb-net-rndis usbutils
#   这些成员会生成 MODULE_DEFAULT_<pkg>=y / CONFIG_DEFAULT_<pkg>=y，把
#   CONFIG_PACKAGE_<pkg> 的默认值拉成 y —— Config/GENERAL.txt 里写
#   CONFIG_PACKAGE_<pkg>=n **无效**，make defconfig 后实测仍解析为 =y。
#   因此只能改目标 Makefile 本身。
#
# 本仓摘除项：kmod-fs-btrfs（Btrfs 内核模块，路由默认不用）
#             fdisk（分区工具；注：luci-app-mini-diskmanager 的 +fdisk 仍会 select 回来）
#             usbutils（lsusb 等，本仓已 =n）
# 有意保留：automount / blkid / blockdev（GENERAL.txt 中本就 =y，基础功能需要）。
#
# 作用面：只在 `DEFAULT_PACKAGES` 块（首行 + 其后所有以 \ 结尾的续行 + 终止行）内
#   按整词移除目标包名，不触碰文件其余内容；逐包处理、幂等、摘除失败会告警。
#   用 awk 而非 sed 的原因：sed 只能逐行匹配，无法可靠界定「块的最后一行」，
#   而 usbutils 恰好位于块末行（非续行），sed 方案会漏掉它。
# 维护说明：若上游调整该 Makefile 格式（例如取消续行写法），本段仍能工作（块退化为单行），
#   但若包名被拆到别的变量里，则会告警并跳过，届时按新格式调整即可。

drop_from_default_packages() {
	local MK="$1"
	local PKG="$2"

	[ -f "$MK" ] || return 0
	grep -q "^[[:space:]]*DEFAULT_PACKAGES" "$MK" || return 0
	grep -q "\b${PKG}\b" "$MK" || return 0

	awk -v pkg="$PKG" '
		/^[[:space:]]*DEFAULT_PACKAGES/ { inblk = 1 }
		inblk {
			gsub("[[:space:]]*" pkg "([[:space:]]|$)", " ")
			if ($0 !~ /\\[[:space:]]*$/) inblk = 0
		}
		{ print }
	' "$MK" > "$MK.feedfix.tmp" && cat "$MK.feedfix.tmp" > "$MK" && rm -f "$MK.feedfix.tmp"

	if grep -q "\b${PKG}\b" "$MK"; then
		echo "FeedFixes: WARNING ${PKG} 摘除失败（Makefile 格式可能已变），请人工检查 $MK"
	else
		echo "FeedFixes: removed ${PKG} from DEFAULT_PACKAGES ($MK)"
	fi
}

MK="./target/linux/mediatek/Makefile"
if [ -f "$MK" ]; then
	for P in kmod-fs-btrfs fdisk usbutils; do
		drop_from_default_packages "$MK" "$P"
	done
else
	echo "FeedFixes: $MK 不存在（目标可能非 mediatek），跳过 DEFAULT_PACKAGES 调整"
fi
