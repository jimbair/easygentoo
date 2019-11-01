# Copy config over for genkernel after manual changes using make menuconfig
CONF='/usr/src/linux/.config'
TARGET="/etc/kernels/kernel-config-x86_64-$(uname -r)"
[[ -e "${CONF}" ]] || exit 1
diff ${CONF} ${TARGET} && exit 0
cat "${CONF}" > /etc/kernels/kernel-config-x86_64-$(uname -r) || exit 2
echo "Config successfully updated"
exit 0
