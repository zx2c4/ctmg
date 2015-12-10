PREFIX ?= /usr
DESTDIR ?=
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib
MANDIR ?= $(PREFIX)/share/man

all:
	@echo "Run \"sudo make install\" to install ctmg"

install:
	@install -v -d "$(DESTDIR)$(BINDIR)/" && install -v -m 0755 ctmg.sh "$(DESTDIR)$(BINDIR)/ctmg"

