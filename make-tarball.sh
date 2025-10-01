#!/usr/bin/env bash

XZ_OPT=${XZ_OPT-"-T0"}
export XZ_OPT

find_ebuild() {
	local ver=$1

	for ebuild in \
		${ver} \
		~/git/gentoo/sys-devel/gcc/gcc-${ver}.ebuild \
		/usr/local/src/gentoo/repo/gentoo/sys-devel/gcc/gcc-${ver}.ebuild \
		"$(portageq get_repo_path $(portageq envvar EPREFIX)/ gentoo)"/sys-devel/gcc/gcc-${ver}.ebuild \
		/usr/portage/sys-devel/gcc/gcc-${ver}.ebuild \
		""
	do
		[[ -f ${ebuild} ]] && break
	done

	echo ${ebuild}
}


if [[ $# -ne 1 ]] ; then
	echo "Usage: $0 <gcc ebuild>"
	exit 1
fi

ver=${1%/}
orig_ver=${ver}

ebuild=$(find_ebuild ${ver})

# If it doesn't exist, check for a snapshot version. We want to be able
# to input e.g. '11.3.0' and fall back to '11.2.1_p2021127' if it doesn't
# exist, as that version will become 11.3.0 anyway.
#
# (_p# is going to be something like gcc-11.2.1_p20211127, where gcc 11.2.1
# will never be released (but gcc 11.2 was) and gcc 11.3 is the next release.
# For such cases, use 11.3 as ver.)
had_pre=0
had_p=0

if [[ -z ${ebuild} ]] ; then
	ver=${ver%%_pre*}

	ver_major=$(echo ${ver} | cut -d'.' -f1)
	ver_minor=$(($(echo ${ver} | cut -d'.' -f2) - 1))
	ver="${ver_major}.${ver_minor}.1_pre*"
	ebuild=$(find_ebuild ${ver})

	[[ -n ${ebuild} ]] && had_pre=1
fi

if [[ -z ${ebuild} ]] ; then
	ver=${orig_ver%%_p*}

	ver_major=$(echo ${ver} | cut -d'.' -f1)
	ver_minor=$(($(echo ${ver} | cut -d'.' -f2) - 1))
	ver="${ver_major}.${ver_minor}.0_pre*"
	ebuild=$(find_ebuild ${ver})

	[[ -n ${ebuild} ]] && had_p=1
fi

if [[ -z ${ebuild} ]] ; then
	ver=${orig_ver}
	ver=${ver%%_p*}

	ver_major=$(echo ${ver} | cut -d'.' -f1)
	ver_minor=$(($(echo ${ver} | cut -d'.' -f2) - 1))
	ver="${ver_major}.${ver_minor}.1_p*"

	ebuild=$(find_ebuild ${ver})

	[[ -n ${ebuild} ]] && had_p=1
fi

if [[ -z ${ebuild} ]] ; then
	echo "!!! gcc ebuild '${ver}' does not exist"
	exit 1
fi

digest=${ebuild/.ebuild}
rm -f ${digest/gcc\//gcc\/files\/digest-}
gver=${ebuild##*/gcc/gcc-} # trim leading path
gver=${gver%%.ebuild}      # trim post .ebuild
gver=${gver%%-*}           # trim any -r#'s
gver=${gver%%_pre*}        # trim any _pre.*#'s

# We use the same logic as finding the ebuild above for snapshots too
gver=${gver%%_p*}
if [[ ${had_pre} -eq 1 ]] ; then
	gver_major=$(echo ${gver} | cut -d'.' -f1)
	gver_minor=$(($(echo ${gver} | cut -d'.' -f2) + 1))
	gver="${gver_major}.${gver_minor}.0"
elif [[ ${had_p} -eq 1 ]] ; then
	gver_major=$(echo ${gver} | cut -d'.' -f1)
	gver_minor=$(($(echo ${gver} | cut -d'.' -f2) + 1))
	gver="${gver_major}.${gver_minor}.0"
fi

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

eread MUSL_VER PP_VER HTB_VER HTB_GCC_VER MAN_VER SPECS_VER SPECS_GCC_VER
[[ -n ${HTB_VER} && -z ${HTB_GCC_VER} ]] && HTB_GCC_VER=${gver}
PATCH_VER=$(awk '{print $1; exit}' ./${gver}/gentoo/README.history)
PIE_VER=$(awk '{print $1; exit}' ./${gver}/pie/README.history)

if [[ ! -d ./${gver} ]] ; then
	echo "Error: ${gver} is not a valid gcc ver"
	exit 1
fi

echo "Building patches for gcc version ${gver}"
echo " - PATCH:    ${PATCH_VER} (taken from ${gver}/gentoo/README.history)"
echo " - MUSL:     ${MUSL_VER}"
echo " - PIE:      ${PIE_VER} (taken from ${gver}/pie/README.history)"
echo " - SPECS:    ${SPECS_VER} (${SPECS_GCC_VER:-${gver}})"
echo " - SSP:      ${PP_VER}"
echo " - BOUNDS:   ${HTB_GCC_VER}-${HTB_VER}"
echo " - MAN:      ${MAN_VER}"

rm -rf tmp
rm -f gcc-${gver}-*.tar.bz2 gcc-${gver}-*.tar.xz

# standard jobbies
mkdir -p tmp/patch/exclude tmp/musl tmp/piepatch tmp/specs
[[ -n ${PATCH_VER}  ]] && cp ${gver}/gentoo/*.patch ${gver}/gentoo/README.history README.Gentoo.patches tmp/patch/
[[ -d ${gver}/man   ]] && cp -r ${gver}/man tmp/
[[ -n ${MUSL_VER} ]] && cp -r ${gver}/musl/* README.Gentoo.patches tmp/musl/
[[ -n ${PIE_VER}    ]] && cp -r ${gver}/pie/* README.Gentoo.patches tmp/piepatch/
[[ -n ${PP_VER}     ]] && cp -r ${gver}/ssp tmp/
[[ -n ${SPECS_VER}  ]] && cp -r ${SPECS_GCC_VER:-${gver}}/specs/* tmp/specs/
# extra cruft
[[ -n ${HTB_VER} ]] && \
cp ${gver}/misc/bounds-checking-gcc*.patch \
   tmp/bounds-checking-gcc-${HTB_GCC_VER}-${HTB_VER}.patch
find tmp/ -name CVS -type d | xargs rm -rf

# standard jobbies
[[ -n ${PATCH_VER}  ]] && {
tar -acf gcc-${sgver}-patches-${PATCH_VER}.tar.xz \
	-C tmp patch || exit 1 ; }
[[ -n ${MUSL_VER} ]] && {
tar -acf gcc-${sgver}-musl-patches-${MUSL_VER}.tar.xz \
	-C tmp musl || exit 1 ; }
[[ -n ${PIE_VER}    ]] && {
tar -acf gcc-${sgver}-piepatches-v${PIE_VER}.tar.xz \
	-C tmp piepatch || exit 1 ; }
[[ -n ${SPECS_VER}  ]] && {
tar -acf gcc-${sgver}-specs-${SPECS_VER}.tar.xz \
	-C tmp specs || exit 1 ; }
[[ -n ${PP_VER}     ]] && {
mv tmp/ssp/protector.patch tmp/ssp/gcc-${gver}-ssp.patch
tar -acf gcc-${gver}-ssp-${PP_VER}.tar.xz \
	-C tmp ssp || exit 1 ; }
[[ -d ${gver}/man   ]] && {
tar -acf gcc-${MAN_VER}-manpages.tar.xz \
	-C tmp/man . || exit 1 ; }
# extra cruft
[[ -n ${HTB_VER}    ]] && {
xz tmp/bounds-checking-*.patch \
	&& cp tmp/bounds-checking-*.patch.xz . || exit 1 ; }
rm -rf tmp

du -b *.xz
