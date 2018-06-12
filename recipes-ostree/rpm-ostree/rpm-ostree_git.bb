DESCRIPTION = "RPM integration for ostree."
HOMEPAGE = "https://rpm-ostree.readthedocs.io"
LICENSE = "LGPLv2"

LIC_FILES_CHKSUM = "file://COPYING;md5=5f30f0716dfdd0d91eb439ebec522ec2"

SRC_URI = " \
    gitsm://git@github.com/projectatomic/rpm-ostree;protocol=https;branch=master \
    file://cross-build.patch \
    file://bwrap-env.patch \
    file://add_environtment_var_overrides.patch \
    file://use_readlink_on_rootfs_descriptor.patch \
"

SRC_URI_append_class-native = " file://host-rpmostree-compile.patch \
"

SRCREV = "cf6f704ee437ee29dc90dca036b8f76089aaeb99"

inherit autotools-brokensep pkgconfig requires-systemd gobject-introspection cmake distutils3-base

PV = "v2018.3"
S = "${WORKDIR}/git"
B = "${WORKDIR}/git"

DEPENDS = " \
    ostree \
    rpm \
    libdnf \
    json-glib \
    systemd \
    glib-2.0 \
    librepo \
    libcheck \
    librepo-native \
    libsolv \
    zlib \
    libarchive \
    xz \
    polkit \
    cmake-native \
    libxml2-native \
    libxslt-native \
    python3 \
"

DEPENDS_class-native = " \
    ostree-native \
    rpm-native \
    json-glib-native \
    glib-2.0-native \
    librepo-native \
    libcheck-native \
    libsolv-native \
    zlib-native \
    libarchive-native \
    xz-native \
    libxml2-native \
    libxslt-native \
"

RDEPENDS_${PN}_class-target = " \
    gnupg \
"

BBCLASSEXTEND = "native"

do_configure() {
    cd ${S}
    mkdir -p ${docdir}
    sed -i -e 's/gtkdocize/gtkdocize_noexist/' autogen.sh
    NOCONFIGURE=1 ./autogen.sh
    autotools_do_configure
}

do_compile() {
    cd ${B}
    perl -p -i -e 's#-O2#-O0 -g#' config.status
    ./config.status
    autotools_do_compile
}

do_install() {
    autotools_do_install
    # Files not needed at this time
    rm -f ${D}${libdir}/librpmostree*.la
    rm -rf ${D}/usr/share/dbus-1
    rm -rf ${D}/usr/share/polkit-1
    rm -rf ${D}/usr/lib/systemd
}

EXTRA_OEMAKE += 'MANS="" man1_MANS="" man5_MANS=""'
EXTRA_OECONF_class-native += " \
    --with-builtin-grub2-mkconfig \
    --enable-wrpseudo-compat \
    --disable-otmpfile \
"
