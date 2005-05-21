#!/bin/bash

if [[ $# -ne 1 ]] ; then
	echo "Usage: $0 <gcc ebuild>"
	exit 1
fi
ebuild=$1
if [[ ! -f ${ebuild} ]] ; then
	ebuild=/usr/local/gentoo-x86/sys-devel/gcc/gcc-${ebuild}.ebuild
	if [[ ! -e ${ebuild} ]] ; then
		echo "!!! gcc ebuild '$1' does not exist"
		exit 1
	fi
fi
gver=${ebuild##*/gcc/gcc-} # trim leading path
gver=${gver%%.ebuild}      # trim post .ebuild
gver=${gver%%-*}           # trim any -r#'s

# trim branch update number
sgver=$(echo ${gver} | sed -e 's:[0-9]::g')
[[ ${#sgver} -gt 2 ]] \
	&& sgver=${gver%.*} \
	|| sgver=${gver}

eread() {
	inherit(){ :;}
	while [[ $# -gt 0 ]] ; do
		export $1=$(source ${ebuild} 2>/dev/null; echo ${!1})
		shift
	done
}
eread PATCH_VER UCLIBC_VER PIE_VER PP_FVER HTB_VER MAN_VER

if [[ ! -d ./${gver} ]] ; then
	echo "Error: ${gver} is not a valid gcc ver"
	exit 1
fi

echo "Building patches for gcc version ${gver}"
echo " - PATCH:    ${PATCH_VER}"
echo " - UCLIBC:   ${UCLIBC_VER}"
echo " - PIE:      ${PIE_VER}"
echo " - SSP:      ${PP_FVER}"
echo " - BOUNDS:   ${HTB_VER}"
echo " - MAN:      ${MAN_VER}"

rm -rf tmp
rm -f gcc-${gver}-*.tar.bz2

# standard jobbies
mkdir -p tmp/patch/exclude tmp/uclibc tmp/piepatch
cp ${gver}/gentoo/*.patch ../README* tmp/patch/
[[ -d ${gver}/man   ]] && cp -r ${gver}/man tmp/
[[ -n ${UCLIBC_VER} ]] && cp -r ${gver}/uclibc/* ../README* tmp/uclibc/
[[ -n ${PIE_VER}    ]] && cp -r ${gver}/pie/* ../README* tmp/piepatch
[[ -n ${PP_FVER}    ]] && cp -r ${gver}/ssp tmp/
# extra cruft
[[ -n ${HTB_VER} ]] && \
cp -r ${gver}/misc/bounds-checking-gcc*.patch \
      tmp/bounds-checking-${gver}-${HTB_VER}.patch
find tmp/ -name CVS -type d | xargs rm -rf
bzip2 tmp/patch/*.patch || exit 1
[[ -n ${UCLIBC_VER} ]] && { bzip2 tmp/uclibc/*.patch || exit 1 ; }
[[ -n ${PIE_VER}    ]] && { bzip2 tmp/piepatch/*/*.patch || exit 1 ; }

# standard jobbies
tar -jcf gcc-${sgver}-patches-${PATCH_VER}.tar.bz2 \
	-C tmp patch || exit 1
[[ -n ${UCLIBC_VER} ]] && {
tar -jcf gcc-${sgver}-uclibc-patches-${UCLIBC_VER}.tar.bz2 \
	-C tmp uclibc || exit 1 ; }
[[ -n ${PIE_VER}    ]] && {
tar -jcf gcc-${sgver}-pie-patches-${PIE_VER}.tar.bz2 \
	-C tmp piepatch || exit 1 ; }
[[ -n ${PP_FVER}    ]] && {
tar -jcf protector-${PP_FVER}.tar.bz2 \
	-C tmp/ssp . || exit 1 ; }
[[ -d ${gver}/man   ]] && {
tar -jcf gcc-${MAN_VER}-manpages.tar.bz2 \
	-C tmp/man . || exit 1 ; }
# extra cruft
[[ -n ${HTB_VER}    ]] && {
bzip2 tmp/bounds-checking-${gver}-${HTB_VER}.patch \
	&& cp tmp/bounds-checking-${gver}-${HTB_VER}.patch.bz2 . || exit 1 ; }
rm -rf tmp

du -b *.bz2