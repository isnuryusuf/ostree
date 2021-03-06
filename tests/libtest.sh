# Source library for shell script tests
#
# Copyright (C) 2011 Colin Walters <walters@verbum.org>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the
# Free Software Foundation, Inc., 59 Temple Place - Suite 330,
# Boston, MA 02111-1307, USA.

if [ -n "${G_TEST_SRCDIR:-}" ]; then
  test_srcdir="${G_TEST_SRCDIR}/tests"
else
  test_srcdir=$(dirname $0)
fi

if [ -n "${G_TEST_BUILDDIR:-}" ]; then
  test_builddir="${G_TEST_BUILDDIR}/tests"
else
  test_builddir=$(dirname $0)
fi

fatal() {
    echo $@ 1>&2; exit 1
}
# fatal() is shorter to type, but retain this alias
assert_not_reached () {
    fatal "$@"
}

test_tmpdir=$(pwd)

# Some tests look for specific English strings. Use a UTF-8 version
# of the C (POSIX) locale if we have one, or fall back to POSIX
# (https://sourceware.org/glibc/wiki/Proposals/C.UTF-8)
if locale -a | grep C.UTF-8 >/dev/null; then
  export LC_ALL=C.UTF-8
else
  export LC_ALL=C
fi

# Sanity check that we're in a tmpdir that has
# just .testtmp (created by tap-driver for `make check`,
# or nothing at all (as ginstest-runner does)
if ! test -f .testtmp; then
    files=$(ls)
    if test -n "${files}"; then
	ls -l
	assert_not_reached "test tmpdir=${test_tmpdir} is not empty; run this test via \`make check TESTS=\`, not directly"
    fi
    # Remember that this is an acceptable test $(pwd), for the benefit of
    # C and JS tests which may source this file again
    touch .testtmp
fi

export G_DEBUG=fatal-warnings

# Also, unbreak `tar` inside `make check`...Automake will inject
# TAR_OPTIONS: --owner=0 --group=0 --numeric-owner presumably so that
# tarballs are predictable, except we don't want this in our tests.
unset TAR_OPTIONS

# Don't flag deployments as immutable so that test harnesses can
# easily clean up.
export OSTREE_SYSROOT_DEBUG=mutable-deployments

export TEST_GPG_KEYID_1="472CDAFA"
export TEST_GPG_KEYID_2="CA950D41"
export TEST_GPG_KEYID_3="DF444D67"

# GPG when creating signatures demands a writable
# homedir in order to create lockfiles.  Work around
# this by copying locally.
echo "Copying gpghome to ${test_tmpdir}"
cp -a "${test_srcdir}/gpghome" ${test_tmpdir}
chmod -R u+w "${test_tmpdir}"
export TEST_GPG_KEYHOME=${test_tmpdir}/gpghome
export OSTREE_GPG_HOME=${test_tmpdir}/gpghome/trusted

if test -n "${OT_TESTS_DEBUG:-}"; then
    set -x
fi

# This is substituted by the build for installed tests
BUILT_WITH_ASAN=""

if test -n "${OT_TESTS_VALGRIND:-}"; then
    CMD_PREFIX="env G_SLICE=always-malloc OSTREE_SUPPRESS_SYNCFS=1 valgrind -q --error-exitcode=1 --leak-check=full --num-callers=30 --suppressions=${test_srcdir}/glib.supp --suppressions=${test_srcdir}/ostree.supp"
else
    # In some cases the LD_PRELOAD may cause obscure problems,
    # e.g. right now it breaks for me with -fsanitize=address, so
    # let's allow users to skip it.
    if test -z "${OT_SKIP_READDIR_RAND:-}" && test -z "${BUILT_WITH_ASAN:-}"; then
	CMD_PREFIX="env LD_PRELOAD=${test_builddir}/libreaddir-rand.so"
    else
	CMD_PREFIX=""
    fi
fi

if test -n "${OSTREE_UNINSTALLED:-}"; then
    OSTREE_HTTPD=${OSTREE_UNINSTALLED}/ostree-trivial-httpd
else
    OSTREE_HTTPD="${CMD_PREFIX} ostree trivial-httpd"
fi

assert_streq () {
    test "$1" = "$2" || fatal "$1 != $2"
}

assert_str_match () {
    if ! echo "$1" | grep -E -q "$2"; then
	      fatal "$1 does not match regexp $2"
    fi
}

assert_not_streq () {
    (! test "$1" = "$2") || fatal "$1 == $2"
}

assert_has_file () {
    test -f "$1" || fatal "Couldn't find '$1'"
}

assert_has_dir () {
    test -d "$1" || fatal "Couldn't find '$1'"
}

assert_not_has_file () {
    if test -f "$1"; then
        sed -e 's/^/# /' < "$1" >&2
        fatal "File '$1' exists"
    fi
}

assert_not_file_has_content () {
    if grep -q -e "$2" "$1"; then
        sed -e 's/^/# /' < "$1" >&2
        fatal "File '$1' incorrectly matches regexp '$2'"
    fi
}

assert_not_has_dir () {
    if test -d "$1"; then
	      fatal "Directory '$1' exists"
    fi
}

assert_file_has_content () {
    if ! grep -q -e "$2" "$1"; then
        sed -e 's/^/# /' < "$1" >&2
        fatal "File '$1' doesn't match regexp '$2'"
    fi
}

assert_symlink_has_content () {
    if ! test -L "$1"; then
        echo 1>&2 "File '$1' is not a symbolic link"
        exit 1
    fi
    if ! readlink "$1" | grep -q -e "$2"; then
        sed -e 's/^/# /' < "$1" >&2
        echo 1>&2 "Symbolic link '$1' doesn't match regexp '$2'"
        exit 1
    fi
}

assert_file_empty() {
    if test -s "$1"; then
        sed -e 's/^/# /' < "$1" >&2
        fatal "File '$1' is not empty"
    fi
}

assert_files_hardlinked() {
    f1=$(stat -c %i $1)
    f2=$(stat -c %i $2)
    if [ "$f1" != "$f2" ]; then
        fatal "Files '$1' and '$2' are not hardlinked"
    fi
}

setup_test_repository () {
    mode=$1
    shift

    oldpwd=`pwd`

    cd ${test_tmpdir}
    mkdir repo
    cd repo
    ot_repo="--repo=`pwd`"
    export OSTREE="${CMD_PREFIX} ostree ${ot_repo}"
    if test -n "$mode"; then
	$OSTREE init --mode=${mode}
    else
	$OSTREE init
    fi

    cd ${test_tmpdir}
    mkdir files
    cd files
    ot_files=`pwd`
    export ht_files
    ln -s nosuchfile somelink
    echo first > firstfile

    cd ${test_tmpdir}/files
    $OSTREE commit -b test2 -s "Test Commit 1" -m "Commit body first"

    mkdir baz
    echo moo > baz/cow
    echo alien > baz/saucer
    mkdir baz/deeper
    echo hi > baz/deeper/ohyeah
    ln -s nonexistent baz/alink
    mkdir baz/another/
    echo x > baz/another/y

    cd ${test_tmpdir}/files
    $OSTREE commit -b test2 -s "Test Commit 2" -m "Commit body second"
    $OSTREE fsck -q

    cd $oldpwd
}

setup_fake_remote_repo1() {
    mode=$1
    commit_opts=${2:-}
    args=${3:-}
    shift
    oldpwd=`pwd`
    mkdir ostree-srv
    cd ostree-srv
    mkdir gnomerepo
    ${CMD_PREFIX} ostree --repo=gnomerepo init --mode=$mode
    mkdir gnomerepo-files
    cd gnomerepo-files 
    echo first > firstfile
    mkdir baz
    echo moo > baz/cow
    echo alien > baz/saucer
    ${CMD_PREFIX} ostree  --repo=${test_tmpdir}/ostree-srv/gnomerepo commit $commit_opts --add-metadata-string version=3.0 -b main -s "A remote commit" -m "Some Commit body"
    mkdir baz/deeper
    ${CMD_PREFIX} ostree --repo=${test_tmpdir}/ostree-srv/gnomerepo commit $commit_opts --add-metadata-string version=3.1 -b main -s "Add deeper"
    echo hi > baz/deeper/ohyeah
    mkdir baz/another/
    echo x > baz/another/y
    ${CMD_PREFIX} ostree --repo=${test_tmpdir}/ostree-srv/gnomerepo commit $commit_opts --add-metadata-string version=3.2 -b main -s "The rest"
    cd ..
    rm -rf gnomerepo-files
    
    cd ${test_tmpdir}
    mkdir ${test_tmpdir}/httpd
    cd httpd
    ln -s ${test_tmpdir}/ostree-srv ostree
    ${OSTREE_HTTPD} --autoexit --log-file $(pwd)/httpd.log --daemonize -p ${test_tmpdir}/httpd-port $args
    port=$(cat ${test_tmpdir}/httpd-port)
    echo "http://127.0.0.1:${port}" > ${test_tmpdir}/httpd-address
    cd ${oldpwd} 

    export OSTREE="${CMD_PREFIX} ostree --repo=repo"
}

# Set up a large repository for stress testing.
# Something like the Fedora Atomic Workstation branch which has
# objects: meta: 7497 content: 103541
# 9443 directories, 7097 symlinks, 112832 regfiles
# So we'll make ~11 files per dir, with one of them a symlink
# Actually, let's cut this down to 1/3 which is still useful.  So:
# 3147 dirs, with still ~11 files per dir, for 37610 content objects
setup_exampleos_repo() {
    args=${1:-}
    cd ${test_tmpdir}
    mkdir ostree-srv
    mkdir -p ostree-srv/exampleos/{repo,build-repo}
    export ORIGIN_REPO=ostree-srv/exampleos/repo
    export ORIGIN_BUILD_REPO=ostree-srv/exampleos/build-repo
    ${CMD_PREFIX} ostree --repo=${ORIGIN_REPO} init --mode=archive
    ${CMD_PREFIX} ostree --repo=${ORIGIN_BUILD_REPO} init --mode=bare-user
    cd ${test_tmpdir}
    rm main -rf
    mkdir main
    cd main
    ndirs=3147
    depth=0
    set +x  # No need to spam the logs for this
    echo "$(date): Generating initial content..."
    while [ $ndirs -gt 0 ]; do
        # 2/3 of the time, recurse a dir, up to a max of 9, otherwise back up
        x=$(($ndirs % 3))
        case $x in
            0) if [ $depth -gt 0 ]; then cd ..; depth=$((depth-1)); fi ;;
            1|2) if [ $depth -lt 9 ]; then
                         mkdir dir-${ndirs}
                         cd dir-${ndirs}
                         depth=$((depth+1))
                     else
                         if [ $depth -gt 0 ]; then cd ..; depth=$((depth-1)); fi
                 fi ;;
        esac
        # One symlink - we use somewhat predictable content to have dupes
        ln -s $(($x % 20)) link-$ndirs
        # 10 files
        nfiles=10
        while [ $nfiles -gt 0 ]; do
            echo file-$ndirs-$nfiles > f$ndirs-$nfiles
            # Make an unreadable file to trigger https://github.com/ostreedev/ostree/pull/634
            if [ $(($x % 10)) -eq 0 ]; then
                chmod 0600 f$ndirs-$nfiles
            fi
            nfiles=$((nfiles-1))
        done
        ndirs=$((ndirs-1))
    done
    cd ${test_tmpdir}
    set -x

    export REF=exampleos/42/standard

    ${CMD_PREFIX} ostree --repo=${ORIGIN_BUILD_REPO} commit -b ${REF} --tree=dir=main
    rm main -rf
    ${CMD_PREFIX} ostree --repo=${ORIGIN_BUILD_REPO} checkout ${REF} main

    find main > files.txt
    nfiles=$(wc -l files.txt | cut -f 1 -d ' ')
    # We'll make 5 more commits
    for iter in $(seq 5); do
        set +x
        # Change 10% of files
        for fiter in $(seq $(($nfiles / 10))); do
            filenum=$(($RANDOM % ${nfiles}))
            set +o pipefail
            filename=$(tail -n +${filenum} < files.txt | head -1)
            set -o pipefail
            if test -f $filename; then
                rm -f $filename
                echo file-${iter}-${fiter} > ${filename}
            fi
        done
        set -x
        ${CMD_PREFIX} ostree --repo=${ORIGIN_BUILD_REPO} commit --link-checkout-speedup -b ${REF} --tree=dir=main
    done

    ${CMD_PREFIX} ostree --repo=${ORIGIN_REPO} pull-local --depth=-1 ${ORIGIN_BUILD_REPO}

    for x in "^^" "^" ""; do
        ${CMD_PREFIX} ostree --repo=${ORIGIN_REPO} static-delta generate --from="${REF}${x}^" --to="${REF}${x}"
    done
    ${CMD_PREFIX} ostree --repo=${ORIGIN_REPO} summary -u

    cd ${test_tmpdir}/ostree-srv
    mkdir httpd
    ${OSTREE_HTTPD} --autoexit --log-file $(pwd)/httpd/httpd.log --daemonize -p httpd/port $args
    port=$(cat httpd/port)
    echo "http://127.0.0.1:${port}" > httpd/address

    cd ${test_tmpdir}
    rm repo -rf
    ${CMD_PREFIX} ostree --repo=repo init --mode=bare-user
    ${CMD_PREFIX} ostree --repo=repo remote add --set=gpg-verify=false origin $(cat ostree-srv/httpd/address)/exampleos/repo
    export OSTREE="${CMD_PREFIX} ostree --repo=repo"
}

setup_os_boot_syslinux() {
    # Stub syslinux configuration
    mkdir -p sysroot/boot/loader.0
    ln -s loader.0 sysroot/boot/loader
    touch sysroot/boot/loader/syslinux.cfg
    # And a compatibility symlink
    mkdir -p sysroot/boot/syslinux
    ln -s ../loader/syslinux.cfg sysroot/boot/syslinux/syslinux.cfg
}

setup_os_boot_uboot() {
    # Stub U-Boot configuration
    mkdir -p sysroot/boot/loader.0
    ln -s loader.0 sysroot/boot/loader
    touch sysroot/boot/loader/uEnv.txt
    # And a compatibility symlink
    ln -s loader/uEnv.txt sysroot/boot/uEnv.txt
}

setup_os_boot_grub2() {
    grub2_options=$1
    mkdir -p sysroot/boot/grub2/
    ln -s ../loader/grub.cfg sysroot/boot/grub2/grub.cfg
    export OSTREE_BOOT_PARTITION="/boot"
    case "$grub2_options" in
        *ostree-grub-generator*)
            cp ${test_srcdir}/ostree-grub-generator ${test_tmpdir}
            chmod +x ${test_tmpdir}/ostree-grub-generator
            export OSTREE_GRUB2_EXEC=${test_tmpdir}/ostree-grub-generator
            ;;
    esac
}

setup_os_repository () {
    mode=$1
    bootmode=$2
    shift

    oldpwd=`pwd`

    cd ${test_tmpdir}
    mkdir testos-repo
    if test -n "$mode"; then
	${CMD_PREFIX} ostree --repo=testos-repo init --mode=${mode}
    else
	${CMD_PREFIX} ostree --repo=testos-repo init
    fi

    cd ${test_tmpdir}
    mkdir osdata
    cd osdata
    mkdir -p boot usr/bin usr/lib/modules/3.6.0 usr/share usr/etc
    echo "a kernel" > boot/vmlinuz-3.6.0
    echo "an initramfs" > boot/initramfs-3.6.0
    bootcsum=$(cat boot/vmlinuz-3.6.0 boot/initramfs-3.6.0 | sha256sum | cut -f 1 -d ' ')
    export bootcsum
    mv boot/vmlinuz-3.6.0 boot/vmlinuz-3.6.0-${bootcsum}
    mv boot/initramfs-3.6.0 boot/initramfs-3.6.0-${bootcsum}
    
    echo "an executable" > usr/bin/sh
    echo "some shared data" > usr/share/langs.txt
    echo "a library" > usr/lib/libfoo.so.0
    ln -s usr/bin bin
cat > usr/etc/os-release <<EOF
NAME=TestOS
VERSION=42
ID=testos
VERSION_ID=42
PRETTY_NAME="TestOS 42"
EOF
    echo "a config file" > usr/etc/aconfigfile
    mkdir -p usr/etc/NetworkManager
    echo "a default daemon file" > usr/etc/NetworkManager/nm.conf
    mkdir -p usr/etc/testdirectory
    echo "a default daemon file" > usr/etc/testdirectory/test

    ${CMD_PREFIX} ostree --repo=${test_tmpdir}/testos-repo commit --add-metadata-string version=1.0.9 -b testos/buildmaster/x86_64-runtime -s "Build"
    
    # Ensure these commits have distinct second timestamps
    sleep 2
    echo "a new executable" > usr/bin/sh
    ${CMD_PREFIX} ostree --repo=${test_tmpdir}/testos-repo commit --add-metadata-string version=1.0.10 -b testos/buildmaster/x86_64-runtime -s "Build"

    cd ${test_tmpdir}
    cp -a osdata osdata-devel
    cd osdata-devel
    mkdir -p usr/include
    echo "a development header" > usr/include/foo.h
    ${CMD_PREFIX} ostree --repo=${test_tmpdir}/testos-repo commit --add-metadata-string version=1.0.9 -b testos/buildmaster/x86_64-devel -s "Build"

    ${CMD_PREFIX} ostree --repo=${test_tmpdir}/testos-repo fsck -q

    cd ${test_tmpdir}
    mkdir sysroot
    export OSTREE_SYSROOT=sysroot
    ${CMD_PREFIX} ostree admin init-fs sysroot
    ${CMD_PREFIX} ostree admin os-init testos

    case $bootmode in
        "syslinux")
	    setup_os_boot_syslinux
            ;;
        "uboot")
	    setup_os_boot_uboot
            ;;
        *grub2*)
        setup_os_boot_grub2 "${bootmode}"
            ;;
    esac
    
    cd ${test_tmpdir}
    mkdir ${test_tmpdir}/httpd
    cd httpd
    ln -s ${test_tmpdir} ostree
    ${OSTREE_HTTPD} --autoexit --daemonize -p ${test_tmpdir}/httpd-port
    port=$(cat ${test_tmpdir}/httpd-port)
    echo "http://127.0.0.1:${port}" > ${test_tmpdir}/httpd-address
    cd ${oldpwd} 
}

os_repository_new_commit ()
{
    boot_checksum_iteration=${1:-0}
    content_iteration=${2:-0}
    echo "BOOT ITERATION: $boot_checksum_iteration"
    cd ${test_tmpdir}/osdata
    rm boot/*
    echo "new: a kernel ${boot_checksum_iteration}" > boot/vmlinuz-3.6.0
    echo "new: an initramfs ${boot_checksum_iteration}" > boot/initramfs-3.6.0
    bootcsum=$(cat boot/vmlinuz-3.6.0 boot/initramfs-3.6.0 | sha256sum | cut -f 1 -d ' ')
    export bootcsum
    mv boot/vmlinuz-3.6.0 boot/vmlinuz-3.6.0-${bootcsum}
    mv boot/initramfs-3.6.0 boot/initramfs-3.6.0-${bootcsum}

    echo "a new default config file" > usr/etc/a-new-default-config-file
    mkdir -p usr/etc/new-default-dir
    echo "a new default dir and file" > usr/etc/new-default-dir/moo

    echo "content iteration ${content_iteration}" > usr/bin/content-iteration

    version=$(date "+%Y%m%d.${content_iteration}")

    ${CMD_PREFIX} ostree --repo=${test_tmpdir}/testos-repo commit  --add-metadata-string "version=${version}" -b testos/buildmaster/x86_64-runtime -s "Build"
    cd ${test_tmpdir}
}

skip() {
    echo "1..0 # SKIP" "$@"
    exit 0
}

skip_without_user_xattrs () {
    touch test-xattrs
    setfattr -n user.testvalue -v somevalue test-xattrs || \
        skip "this test requires xattr support"
}

skip_without_fuse () {
    fusermount --version >/dev/null 2>&1 || skip "no fusermount"

    capsh --print | grep -q 'Bounding set.*[^a-z]cap_sys_admin' || \
        skip "No cap_sys_admin in bounding set, can't use FUSE"

    [ -w /dev/fuse ] || skip "no write access to /dev/fuse"
    [ -e /etc/mtab ] || skip "no /etc/mtab"
}

has_gpgme () {
    ${CMD_PREFIX} ostree --version > version.txt
    assert_file_has_content version.txt '- gpgme'
    rm -f version.txt
    true
}

libtest_cleanup_gpg () {
    gpg-connect-agent --homedir ${test_tmpdir}/gpghome killagent /bye || true
}
