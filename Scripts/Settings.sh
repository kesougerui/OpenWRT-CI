#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
#主题配套-config包并非所有主题都有（如bootstrap没有），存在才写入
if find ./feeds -maxdepth 5 -type d -name "luci-app-$WRT_THEME-config" 2>/dev/null | grep -q .; then
	echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config
fi

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#无WIFI配置标志
if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
	echo "WRT_WIFI=wifi-no" >> $GITHUB_ENV
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi


#eBPF/dae 内核配置（源码默认关闭，按 dae 官方文档要求开启）
enable_ebpf_kernel_cfg() {
	local KEY VAL FILE
	for FILE in ./target/linux/generic/config-* ./target/linux/${WRT_TARGET:-qualcommax}/config-*; do
		[ -f "$FILE" ] || continue
		for KV in \
			"CONFIG_CGROUPS=y" \
			"CONFIG_KPROBES=y" \
			"CONFIG_NET_SCH_INGRESS=m" \
			"CONFIG_NET_CLS_BPF=m" \
			"CONFIG_NET_ACT_BPF=m" \
			"CONFIG_NET_CLS_ACT=y" \
			"CONFIG_BPF_STREAM_PARSER=y" \
			"CONFIG_DEBUG_INFO_BTF=y" \
			"CONFIG_KPROBE_EVENTS=y" \
			"CONFIG_BPF_EVENTS=y"
		do
			KEY="${KV%%=*}"
			VAL="${KV#*=}"
			if grep -qE "^(${KEY}=|# ${KEY} is not set)" "$FILE"; then
				sed -i -e "s|^# ${KEY} is not set|${KEY}=${VAL}|" -e "s|^${KEY}=.*|${KEY}=${VAL}|" "$FILE"
			else
				echo "${KV}" >> "$FILE"
			fi
		done
		echo "kernel eBPF config applied: $FILE"
	done
}
enable_ebpf_kernel_cfg
