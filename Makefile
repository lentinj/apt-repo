PACKAGES = \
    lentinj-desktop.deb \

repo: repo/conf/distributions ${PACKAGES}

%.deb:
	cd $(basename $@) && debuild -b
	ln -fs $(shell ls -1t $(basename $@)_*.deb | head -1) $@
	cd repo && reprepro includedeb sid ../$(shell ls -1t $(basename $@)_*.deb | head -1)
