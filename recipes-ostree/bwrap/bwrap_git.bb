DESCRIPTION = "RPM integration for ostree."
HOMEPAGE = "https://github.com/projectatomic/bubblewrap"
LICENSE = "LGPLv2"

LIC_FILES_CHKSUM = "file://COPYING;md5=5f30f0716dfdd0d91eb439ebec522ec2"

SRC_URI = " \
     git://git@github.com/projectatomic/bubblewrap;protocol=https;branch=master \
"

SRCREV = "5f27455af6e5e36d5f8b06c41214e1a71c054acb"
SRCREV = "56609f864757924cecd5ceeaef35e46a9c1351ea"

inherit autotools-brokensep pkgconfig

FILES_${PN} += "/usr/share/bash-completion/completions/bwrap"

PV = "v0.2.1"
S = "${WORKDIR}/git"

DEPENDS = " \
	libcap \
"

DEPENDS_class-native = " \
	libcap-native \
"

BBCLASSEXTEND = "native"

do_configure_prepend() {
    cd ${S}
    mkdir -p ${docdir}
    NOCONFIGURE=1 ./autogen.sh
}

