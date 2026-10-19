# st - simple terminal
# See LICENSE file for copyright and license details.
.POSIX:

include config.mk

SRC = st.c x.c mac.m
OBJ = st.o $(FRONTEND).o
APP = $(APPPREFIX)/st.app

all: config.h
	@if [ "`uname -s`" = Darwin ]; then \
		$(MAKE) FRONTEND=mac INCS="$(MACINCS)" LIBS="$(MACLIBS)" app; \
	else \
		$(MAKE) st; \
	fi

config.h:
	cp config.def.h config.h

.c.o:
	$(CC) $(STCFLAGS) -c $<

mac.o: mac.m
	$(CC) $(STCFLAGS) $(MACCFLAGS) -c mac.m

st.o: config.h st.h win.h
x.o: arg.h config.h st.h win.h
mac.o: arg.h config.h st.h win.h rgb.h

$(OBJ): config.h config.mk

st: $(OBJ)
	$(CC) -o $@ $(OBJ) $(STLDFLAGS)

mkicon: mkicon.m
	$(CC) $(CFLAGS) -fobjc-arc -o $@ mkicon.m -framework Cocoa \
		-framework CoreText

st.icns: mkicon
	rm -rf st.iconset
	./mkicon st.iconset
	iconutil -c icns -o $@ st.iconset
	rm -rf st.iconset

app: $(APP)

$(APP): st st.icns st.plist
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp -f st $(APP)/Contents/MacOS/st
	cp -f st.icns $(APP)/Contents/Resources/st.icns
	sed "s/VERSION/$(VERSION)/g" < st.plist > $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

clean:
	rm -f st st.o x.o mac.o mkicon st.icns st-$(VERSION).tar.gz
	rm -rf st.iconset

dist: clean
	mkdir -p st-$(VERSION)
	cp -R FAQ LEGACY TODO LICENSE Makefile README config.mk\
		config.def.h st.info st.1 arg.h st.h win.h rgb.h mkicon.m\
		st.plist $(SRC)\
		st-$(VERSION)
	tar -cf - st-$(VERSION) | gzip > st-$(VERSION).tar.gz
	rm -rf st-$(VERSION)

install: all
	@if [ "`uname -s`" != Darwin ]; then $(MAKE) install-x11; fi

install-x11:
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	cp -f st $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/st
	mkdir -p $(DESTDIR)$(MANPREFIX)/man1
	sed "s/VERSION/$(VERSION)/g" < st.1 > $(DESTDIR)$(MANPREFIX)/man1/st.1
	chmod 644 $(DESTDIR)$(MANPREFIX)/man1/st.1
	tic -sx st.info
	@echo Please see the README file regarding the terminfo entry of st.

uninstall:
	@if [ "`uname -s`" = Darwin ]; then \
		echo rm -rf $(APP); rm -rf $(APP); \
	else \
		$(MAKE) uninstall-x11; \
	fi

uninstall-x11:
	rm -f $(DESTDIR)$(PREFIX)/bin/st
	rm -f $(DESTDIR)$(MANPREFIX)/man1/st.1

.PHONY: all app clean dist install install-x11 uninstall uninstall-x11
