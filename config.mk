# st version
VERSION = 0.9.3

# Customize below to fit your system

# paths
PREFIX = /usr/local
MANPREFIX = $(PREFIX)/share/man

X11INC = /usr/X11R6/include
X11LIB = /usr/X11R6/lib

PKG_CONFIG = pkg-config

# x or mac, set by make
FRONTEND = x

# X11 includes and libs
X11INCS = -I$(X11INC) \
          `$(PKG_CONFIG) --cflags fontconfig` \
          `$(PKG_CONFIG) --cflags freetype2`
X11LIBS = -L$(X11LIB) -lm -lX11 -lutil -lXft \
          `$(PKG_CONFIG) --libs fontconfig` \
          `$(PKG_CONFIG) --libs freetype2`

# macOS includes and libs, xorgproto has the keysyms used in config.h
MACINCS = `$(PKG_CONFIG) --cflags xproto`
MACLIBS = -lm -lutil -framework Cocoa -framework CoreText
MACCFLAGS = -fobjc-arc -D_DARWIN_C_SOURCE

# includes and libs
INCS = $(X11INCS)
LIBS = $(X11LIBS)

# flags
STCPPFLAGS = -DVERSION=\"$(VERSION)\" -D_XOPEN_SOURCE=600
STCFLAGS = $(INCS) $(STCPPFLAGS) $(CPPFLAGS) $(CFLAGS)
STLDFLAGS = $(LIBS) $(LDFLAGS)

# OpenBSD:
#CPPFLAGS = -DVERSION=\"$(VERSION)\" -D_XOPEN_SOURCE=600 -D_BSD_SOURCE
#LIBS = -L$(X11LIB) -lm -lX11 -lutil -lXft \
#       `$(PKG_CONFIG) --libs fontconfig` \
#       `$(PKG_CONFIG) --libs freetype2`
#MANPREFIX = ${PREFIX}/man

# compiler and linker
# CC = c99
