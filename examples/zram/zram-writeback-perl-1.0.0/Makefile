VERSION := 1.0.0
DIST := zram-writeback-perl-$(VERSION)
PERL := perl

.PHONY: all syntax test dist install uninstall clean

all: syntax test

syntax:
	find lib -name '*.pm' -print -exec $(PERL) -Ilib -c {} \;
	$(PERL) -c sbin/zram-writeback

test:
	prove -Ilib -r t

dist: clean
	cd .. && tar --sort=name --owner=0 --group=0 --numeric-owner -czf $(DIST).tar.gz $(DIST)

install:
	./install.sh

uninstall:
	./uninstall.sh

clean:
	find . -name '*~' -delete
	find . -name '*.tmp' -delete
