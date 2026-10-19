/* See LICENSE for license details. */
#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>

#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <limits.h>
#include <locale.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>
#include <libgen.h>
#include <X11/X.h>
#include <X11/keysym.h>

/* from X11/cursorfont.h */
#define XC_num_glyphs            154
#define XC_X_cursor              0
#define XC_arrow                 2
#define XC_based_arrow_down      4
#define XC_based_arrow_up        6
#define XC_boat                  8
#define XC_bogosity              10
#define XC_bottom_left_corner    12
#define XC_bottom_right_corner   14
#define XC_bottom_side           16
#define XC_bottom_tee            18
#define XC_box_spiral            20
#define XC_center_ptr            22
#define XC_circle                24
#define XC_clock                 26
#define XC_coffee_mug            28
#define XC_cross                 30
#define XC_cross_reverse         32
#define XC_crosshair             34
#define XC_diamond_cross         36
#define XC_dot                   38
#define XC_dotbox                40
#define XC_double_arrow          42
#define XC_draft_large           44
#define XC_draft_small           46
#define XC_draped_box            48
#define XC_exchange              50
#define XC_fleur                 52
#define XC_gobbler               54
#define XC_gumby                 56
#define XC_hand1                 58
#define XC_hand2                 60
#define XC_heart                 62
#define XC_icon                  64
#define XC_iron_cross            66
#define XC_left_ptr              68
#define XC_left_side             70
#define XC_left_tee              72
#define XC_leftbutton            74
#define XC_ll_angle              76
#define XC_lr_angle              78
#define XC_man                   80
#define XC_middlebutton          82
#define XC_mouse                 84
#define XC_pencil                86
#define XC_pirate                88
#define XC_plus                  90
#define XC_question_arrow        92
#define XC_right_ptr             94
#define XC_right_side            96
#define XC_right_tee             98
#define XC_rightbutton           100
#define XC_rtl_logo              102
#define XC_sailboat              104
#define XC_sb_down_arrow         106
#define XC_sb_h_double_arrow     108
#define XC_sb_left_arrow         110
#define XC_sb_right_arrow        112
#define XC_sb_up_arrow           114
#define XC_sb_v_double_arrow     116
#define XC_shuttle               118
#define XC_sizing                120
#define XC_spider                122
#define XC_spraycan              124
#define XC_star                  126
#define XC_target                128
#define XC_tcross                130
#define XC_top_left_arrow        132
#define XC_top_left_corner       134
#define XC_top_right_corner      136
#define XC_top_side              138
#define XC_top_tee               140
#define XC_trek                  142
#define XC_ul_angle              144
#define XC_umbrella              146
#define XC_ur_angle              148
#define XC_watch                 150
#define XC_xterm                 152

char *argv0;
#include "arg.h"
/* Foundation defines these too */
#undef MIN
#undef MAX
#include "st.h"
#include "win.h"

/* types used in config.h */
typedef struct {
	uint mod;
	KeySym keysym;
	void (*func)(const Arg *);
	const Arg arg;
} Shortcut;

typedef struct {
	uint mod;
	uint button;
	void (*func)(const Arg *);
	const Arg arg;
	uint  release;
} MouseShortcut;

typedef struct {
	KeySym k;
	uint mask;
	char *s;
	/* three-valued logic variables: 0 indifferent, 1 on, -1 off */
	signed char appkey;    /* application keypad */
	signed char appcursor; /* application cursor */
} Key;

/* X modifiers */
#define XK_ANY_MOD    UINT_MAX
#define XK_NO_MOD     0
#define XK_SWITCH_MOD (1<<13|1<<14)

/* function definitions used in config.h */
static void clipcopy(const Arg *);
static void clippaste(const Arg *);
static void numlock(const Arg *);
static void selpaste(const Arg *);
static void zoom(const Arg *);
static void zoomabs(const Arg *);
static void zoomreset(const Arg *);
static void ttysend(const Arg *);

/* config.h for applying patches and the configuration. */
#include "config.h"

/* Option key used as Alt: 0 none, 1 left, 2 right, 3 both */
#ifndef OPTIONMETA
#define OPTIONMETA 1
#endif

/* X11 color names */
#include "rgb.h"

/* XParseGeometry() mask bits */
#define XValue      0x0001
#define YValue      0x0002
#define WidthValue  0x0004
#define HeightValue 0x0008
#define XNegative   0x0010
#define YNegative   0x0020

/* from IOKit/hidsystem/IOLLEvent.h */
#define NX_DEVICELALTKEYMASK 0x00000020
#define NX_DEVICERALTKEYMASK 0x00000040

/* macros */
#define IS_SET(flag)		((win.mode & (flag)) != 0)
#define TRUERED(x)		(((x) & 0xff0000) >> 8)
#define TRUEGREEN(x)		(((x) & 0xff00))
#define TRUEBLUE(x)		(((x) & 0xff) << 8)

typedef struct {
	ushort red, green, blue, alpha;
} Color;

typedef struct {
	CTFontRef font;
	CGGlyph glyph;
	CGFloat x, y;
	int fakebold;
} GlyphFontSpec;

/* the parts of XEvent the mouse handlers use */
typedef struct {
	int type;
	uint button;
	uint state;
	int x, y;
} Event;

/* Purely graphic info */
typedef struct {
	int tw, th; /* tty width and height */
	int w, h; /* window width and height */
	int ch; /* char height */
	int cw; /* char width  */
	int mode; /* window state/mode flags */
	int cursor; /* cursor style */
} TermWindow;

typedef struct {
	CGContextRef buf;
	CGFloat scale;
	GlyphFontSpec *specbuf; /* font spec buffer used for rendering */
	struct {
		int x, y; /* in cells */
	} ime;
	int pointermotion;
	int started;
	int isfixed; /* is fixed geometry? */
	int l, t; /* left and top offset */
	int gm; /* geometry mask */
	NSInteger attention;
} XWindow;

typedef struct {
	char *primary, *clipboard;
	struct timespec tclick1;
	struct timespec tclick2;
} XSelection;

/* Font structure */
#define Font Font_
typedef struct {
	int height;
	int width;
	int ascent;
	int descent;
	int badslant;
	int badweight;
	int fakebold;
	CTFontRef match;
} Font;

/* Drawing Context */
typedef struct {
	Color *col;
	size_t collen;
	Font font, bfont, ifont, ibfont;
	int antialias;
} DC;

@interface StView : NSView <NSTextInputClient>
@end

@interface StDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

static inline ushort sixd_to_16bit(int);
static int xmakeglyphfontspecs(GlyphFontSpec *, const Glyph *, int, int, int);
static void xdrawglyphfontspecs(const GlyphFontSpec *, Glyph, int, int, int);
static void xdrawglyph(Glyph, int, int);
static void xclear(int, int, int, int);
static void xfillrect(const Color *, CGFloat, CGFloat, CGFloat, CGFloat);
static void xinit(int, int);
static void cresize(int, int);
static void xresize(int, int);
static void xresizebuf(void);
static void xhints(void);
static int parsecolor(const char *, Color *);
static int xloadcolor(int, const char *, Color *);
static void xloadfont(Font *, CTFontRef, CTFontSymbolicTraits);
static void xloadfonts(const char *, double);
static void xunloadfont(Font *);
static void xunloadfonts(void);
static void xsetenv(void);
static void xseturgency(int);
static int evcol(Event *);
static int evrow(Event *);
static int parsegeometry(const char *, int *, int *, uint *, uint *);

static void focus(int);
static uint buttonmask(uint);
static int mouseaction(Event *, uint);
static void brelease(Event *);
static void bpress(Event *);
static void bmotion(Event *);
static void setsel(char *);
static void mousesel(Event *, int);
static void mousereport(Event *);
static void pastetext(const char *, size_t);
static char *kmap(KeySym, uint);
static int match(uint, uint);

static void schedule(void);
static void drawnow(void);
static void run(void);
static void usage(void);

/* Globals */
static DC dc;
static XWindow xw;
static XSelection xsel;
static TermWindow win;
static NSWindow *window;
static StView *view;
static StDelegate *delegate;
static NSString *markedtext;
static dispatch_source_t ttysrc, drawtimer;
static int drawing;
static struct timespec trigger, lastblink;

/* Font Ring Cache */
enum {
	FRC_NORMAL,
	FRC_ITALIC,
	FRC_BOLD,
	FRC_ITALICBOLD
};

typedef struct {
	CTFontRef font;
	int flags;
	Rune unicodep;
} Fontcache;

/* Fontcache is an array now. A new font will be appended to the array. */
static Fontcache *frc = NULL;
static int frclen = 0;
static int frccap = 0;
static char *usedfont = NULL;
static double usedfontsize = 0;
static double defaultfontsize = 0;

static char *opt_class = NULL;
static char **opt_cmd  = NULL;
static char *opt_embed = NULL;
static char *opt_font  = NULL;
static char *opt_io    = NULL;
static char *opt_line  = NULL;
static char *opt_name  = NULL;
static char *opt_title = NULL;

static uint buttons; /* bit field of pressed buttons */

void
clipcopy(const Arg *dummy)
{
	NSPasteboard *pb;
	NSString *s;

	free(xsel.clipboard);
	xsel.clipboard = NULL;

	if (xsel.primary != NULL) {
		xsel.clipboard = xstrdup(xsel.primary);
		s = [NSString stringWithUTF8String:xsel.clipboard];
		if (!s)
			return;
		pb = [NSPasteboard generalPasteboard];
		[pb clearContents];
		[pb setString:s forType:NSPasteboardTypeString];
	}
}

void
clippaste(const Arg *dummy)
{
	NSString *s;
	const char *p;

	s = [[NSPasteboard generalPasteboard]
	     stringForType:NSPasteboardTypeString];
	if (!s || !(p = [s UTF8String]))
		return;
	pastetext(p, strlen(p));
}

void
selpaste(const Arg *dummy)
{
	if (xsel.primary)
		pastetext(xsel.primary, strlen(xsel.primary));
}

void
pastetext(const char *text, size_t len)
{
	char *data, *repl, *last;

	/*
	 * As seen in getsel:
	 * Line endings are inconsistent in the terminal and GUI world
	 * copy and pasting. When receiving some selection data,
	 * replace all '\n' with '\r'.
	 * FIXME: Fix the computer world.
	 */
	data = xmalloc(len + 1);
	memcpy(data, text, len);
	repl = data;
	last = data + len;
	while ((repl = memchr(repl, '\n', last - repl))) {
		*repl++ = '\r';
	}

	if (IS_SET(MODE_BRCKTPASTE))
		ttywrite("\033[200~", 6, 0);
	ttywrite(data, len, 1);
	if (IS_SET(MODE_BRCKTPASTE))
		ttywrite("\033[201~", 6, 0);
	free(data);
}

void
numlock(const Arg *dummy)
{
	win.mode ^= MODE_NUMLOCK;
}

void
zoom(const Arg *arg)
{
	Arg larg;

	larg.f = usedfontsize + arg->f;
	zoomabs(&larg);
}

void
zoomabs(const Arg *arg)
{
	xunloadfonts();
	xloadfonts(usedfont, arg->f);
	cresize(0, 0);
	redraw();
	xhints();
}

void
zoomreset(const Arg *arg)
{
	Arg larg;

	if (defaultfontsize > 0) {
		larg.f = defaultfontsize;
		zoomabs(&larg);
	}
}

void
ttysend(const Arg *arg)
{
	ttywrite(arg->s, strlen(arg->s), 1);
}

int
evcol(Event *e)
{
	int x = e->x - borderpx;
	LIMIT(x, 0, win.tw - 1);
	return x / win.cw;
}

int
evrow(Event *e)
{
	int y = e->y - borderpx;
	LIMIT(y, 0, win.th - 1);
	return y / win.ch;
}

void
mousesel(Event *e, int done)
{
	int type, seltype = SEL_REGULAR;
	uint state = e->state & ~(Button1Mask | forcemousemod);

	for (type = 1; type < LEN(selmasks); ++type) {
		if (match(selmasks[type], state)) {
			seltype = type;
			break;
		}
	}
	selextend(evcol(e), evrow(e), seltype, done);
	if (done)
		setsel(getsel());
}

void
mousereport(Event *e)
{
	int len, btn, code;
	int x = evcol(e), y = evrow(e);
	int state = e->state;
	char buf[40];
	static int ox, oy;

	if (e->type == MotionNotify) {
		if (x == ox && y == oy)
			return;
		if (!IS_SET(MODE_MOUSEMOTION) && !IS_SET(MODE_MOUSEMANY))
			return;
		/* MODE_MOUSEMOTION: no reporting if no button is pressed */
		if (IS_SET(MODE_MOUSEMOTION) && buttons == 0)
			return;
		/* Set btn to lowest-numbered pressed button, or 12 if no
		 * buttons are pressed. */
		for (btn = 1; btn <= 11 && !(buttons & (1<<(btn-1))); btn++)
			;
		code = 32;
	} else {
		btn = e->button;
		/* Only buttons 1 through 11 can be encoded */
		if (btn < 1 || btn > 11)
			return;
		if (e->type == ButtonRelease) {
			/* MODE_MOUSEX10: no button release reporting */
			if (IS_SET(MODE_MOUSEX10))
				return;
			/* Don't send release events for the scroll wheel */
			if (btn == 4 || btn == 5)
				return;
		}
		code = 0;
	}

	ox = x;
	oy = y;

	/* Encode btn into code. If no button is pressed for a motion event in
	 * MODE_MOUSEMANY, then encode it as a release. */
	if ((!IS_SET(MODE_MOUSESGR) && e->type == ButtonRelease) || btn == 12)
		code += 3;
	else if (btn >= 8)
		code += 128 + btn - 8;
	else if (btn >= 4)
		code += 64 + btn - 4;
	else
		code += btn - 1;

	if (!IS_SET(MODE_MOUSEX10)) {
		code += ((state & ShiftMask  ) ?  4 : 0)
		      + ((state & Mod1Mask   ) ?  8 : 0) /* meta key: alt */
		      + ((state & ControlMask) ? 16 : 0);
	}

	if (IS_SET(MODE_MOUSESGR)) {
		len = snprintf(buf, sizeof(buf), "\033[<%d;%d;%d%c",
				code, x+1, y+1,
				e->type == ButtonRelease ? 'm' : 'M');
	} else if (x < 223 && y < 223) {
		len = snprintf(buf, sizeof(buf), "\033[M%c%c%c",
				32+code, 32+x+1, 32+y+1);
	} else {
		return;
	}

	ttywrite(buf, len, 0);
}

uint
buttonmask(uint button)
{
	return button == Button1 ? Button1Mask
	     : button == Button2 ? Button2Mask
	     : button == Button3 ? Button3Mask
	     : button == Button4 ? Button4Mask
	     : button == Button5 ? Button5Mask
	     : 0;
}

int
mouseaction(Event *e, uint release)
{
	MouseShortcut *ms;

	/* ignore Button<N>mask for Button<N> - it's set on release */
	uint state = e->state & ~buttonmask(e->button);

	for (ms = mshortcuts; ms < mshortcuts + LEN(mshortcuts); ms++) {
		if (ms->release == release &&
		    ms->button == e->button &&
		    (match(ms->mod, state) ||  /* exact or forced */
		     match(ms->mod, state & ~forcemousemod))) {
			ms->func(&(ms->arg));
			return 1;
		}
	}

	return 0;
}

void
bpress(Event *e)
{
	int btn = e->button;
	struct timespec now;
	int snap;

	if (1 <= btn && btn <= 11)
		buttons |= 1 << (btn-1);

	if (IS_SET(MODE_MOUSE) && !(e->state & forcemousemod)) {
		mousereport(e);
		return;
	}

	if (mouseaction(e, 0))
		return;

	if (btn == Button1) {
		/*
		 * If the user clicks below predefined timeouts specific
		 * snapping behaviour is exposed.
		 */
		clock_gettime(CLOCK_MONOTONIC, &now);
		if (TIMEDIFF(now, xsel.tclick2) <= tripleclicktimeout) {
			snap = SNAP_LINE;
		} else if (TIMEDIFF(now, xsel.tclick1) <= doubleclicktimeout) {
			snap = SNAP_WORD;
		} else {
			snap = 0;
		}
		xsel.tclick2 = xsel.tclick1;
		xsel.tclick1 = now;

		selstart(evcol(e), evrow(e), snap);
	}
}

void
xclipcopy(void)
{
	clipcopy(NULL);
}

void
setsel(char *str)
{
	if (!str)
		return;

	free(xsel.primary);
	xsel.primary = str;
}

void
xsetsel(char *str)
{
	setsel(str);
}

void
brelease(Event *e)
{
	int btn = e->button;

	if (1 <= btn && btn <= 11)
		buttons &= ~(1 << (btn-1));

	if (IS_SET(MODE_MOUSE) && !(e->state & forcemousemod)) {
		mousereport(e);
		return;
	}

	if (mouseaction(e, 1))
		return;
	if (btn == Button1)
		mousesel(e, 1);
}

void
bmotion(Event *e)
{
	if (IS_SET(MODE_MOUSE) && !(e->state & forcemousemod)) {
		mousereport(e);
		return;
	}

	mousesel(e, 0);
}

void
cresize(int width, int height)
{
	int col, row;

	if (width != 0)
		win.w = width;
	if (height != 0)
		win.h = height;

	col = (win.w - 2 * borderpx) / win.cw;
	row = (win.h - 2 * borderpx) / win.ch;
	col = MAX(1, col);
	row = MAX(1, row);

	tresize(col, row);
	xresize(col, row);
	ttyresize(win.tw, win.th);
}

void
xresize(int col, int row)
{
	win.tw = col * win.cw;
	win.th = row * win.ch;

	xresizebuf();

	/* resize to new width */
	xw.specbuf = xrealloc(xw.specbuf, col * sizeof(GlyphFontSpec));
}

void
xresizebuf(void)
{
	CGColorSpaceRef cs;
	CGFloat scale;

	scale = window ? [window backingScaleFactor] : 1.0;
	if (scale <= 0)
		scale = 1.0;

	if (xw.buf)
		CGContextRelease(xw.buf);
	cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	xw.buf = CGBitmapContextCreate(NULL, ceil(win.w * scale),
			ceil(win.h * scale), 8, 0, cs,
			kCGImageAlphaPremultipliedFirst |
			kCGBitmapByteOrder32Host);
	CGColorSpaceRelease(cs);
	if (!xw.buf)
		die("can't create drawing buffer\n");
	xw.scale = scale;
	CGContextScaleCTM(xw.buf, scale, scale);
	CGContextSetTextMatrix(xw.buf, CGAffineTransformIdentity);
	CGContextSetShouldAntialias(xw.buf, dc.antialias);
	xclear(0, 0, win.w, win.h);
}

ushort
sixd_to_16bit(int x)
{
	return x == 0 ? 0 : 0x3737 + 0x2828 * x;
}

static int
rgbnamecmp(const void *key, const void *elem)
{
	return strcasecmp(key, *(const char **)elem);
}

/* accepts the formats of XParseColor() */
int
parsecolor(const char *name, Color *c)
{
	unsigned long v[3];
	double d[3];
	const char *p;
	char *end;
	int i, n;
	const struct rgbname *e;

	c->alpha = 0xffff;
	if (name[0] == '#') {
		n = strlen(++name);
		if (n == 0 || n % 3 || n > 12 || strspn(name,
		    "0123456789abcdefABCDEF") != n)
			return 0;
		n /= 3;
		for (i = 0; i < 3; i++) {
			v[i] = 0;
			for (p = name + i * n; p < name + (i + 1) * n; p++)
				v[i] = v[i] << 4 | (isdigit(*p) ? *p - '0'
				                    : (tolower(*p) - 'a' + 10));
			v[i] <<= 16 - n * 4;
		}
	} else if (!strncasecmp(name, "rgb:", 4)) {
		p = name + 4;
		for (i = 0; i < 3; i++) {
			n = strspn(p, "0123456789abcdefABCDEF");
			if (n < 1 || n > 4)
				return 0;
			v[i] = strtoul(p, NULL, 16) * 0xffff / ((1UL << n * 4) - 1);
			p += n;
			if (*p != (i < 2 ? '/' : '\0'))
				return 0;
			p++;
		}
	} else if (!strncasecmp(name, "rgbi:", 5)) {
		p = name + 5;
		for (i = 0; i < 3; i++) {
			d[i] = strtod(p, &end);
			if (end == p || d[i] < 0 || d[i] > 1 ||
			    *end != (i < 2 ? '/' : '\0'))
				return 0;
			v[i] = d[i] * 0xffff + 0.5;
			p = end + 1;
		}
	} else {
		if (!(e = bsearch(name, rgbnames, LEN(rgbnames),
		                  sizeof(rgbnames[0]), rgbnamecmp)))
			return 0;
		v[0] = e->r * 0x101;
		v[1] = e->g * 0x101;
		v[2] = e->b * 0x101;
	}
	c->red = v[0];
	c->green = v[1];
	c->blue = v[2];

	return 1;
}

int
xloadcolor(int i, const char *name, Color *ncolor)
{
	if (!name) {
		if (BETWEEN(i, 16, 255)) { /* 256 color */
			ncolor->alpha = 0xffff;
			if (i < 6*6*6+16) { /* same colors as xterm */
				ncolor->red   = sixd_to_16bit( ((i-16)/36)%6 );
				ncolor->green = sixd_to_16bit( ((i-16)/6) %6 );
				ncolor->blue  = sixd_to_16bit( ((i-16)/1) %6 );
			} else { /* greyscale */
				ncolor->red = 0x0808 + 0x0a0a * (i - (6*6*6+16));
				ncolor->green = ncolor->blue = ncolor->red;
			}
			return 1;
		} else
			name = colorname[i];
	}

	return name && parsecolor(name, ncolor);
}

void
xloadcols(void)
{
	int i;
	static int loaded;

	if (!loaded) {
		dc.collen = MAX(LEN(colorname), 256);
		dc.col = xmalloc(dc.collen * sizeof(Color));
	}

	for (i = 0; i < dc.collen; i++)
		if (!xloadcolor(i, NULL, &dc.col[i])) {
			if (colorname[i])
				die("could not allocate color '%s'\n", colorname[i]);
			else
				die("could not allocate color %d\n", i);
		}
	loaded = 1;
}

int
xgetcolor(int x, unsigned char *r, unsigned char *g, unsigned char *b)
{
	if (!BETWEEN(x, 0, dc.collen - 1))
		return 1;

	*r = dc.col[x].red >> 8;
	*g = dc.col[x].green >> 8;
	*b = dc.col[x].blue >> 8;

	return 0;
}

int
xsetcolorname(int x, const char *name)
{
	Color ncolor;

	if (!BETWEEN(x, 0, dc.collen - 1))
		return 1;

	if (!xloadcolor(x, name, &ncolor))
		return 1;

	dc.col[x] = ncolor;

	return 0;
}

/* y counts from the top, like in X */
void
xfillrect(const Color *c, CGFloat x, CGFloat y, CGFloat w, CGFloat h)
{
	CGContextSetRGBFillColor(xw.buf, c->red / 65535.0,
			c->green / 65535.0, c->blue / 65535.0,
			c->alpha / 65535.0);
	CGContextFillRect(xw.buf, CGRectMake(x, win.h - y - h, w, h));
}

/*
 * Absolute coordinates.
 */
void
xclear(int x1, int y1, int x2, int y2)
{
	xfillrect(&dc.col[IS_SET(MODE_REVERSE)? defaultfg : defaultbg],
			x1, y1, x2-x1, y2-y1);
}

void
xhints(void)
{
	NSSize size = NSMakeSize(win.w, win.h);

	if (!window)
		return;

	[window setContentResizeIncrements:NSMakeSize(win.cw, win.ch)];
	[window setContentMinSize:NSMakeSize(win.cw + 2 * borderpx,
	                                     win.ch + 2 * borderpx)];
	if (xw.isfixed) {
		[window setContentMinSize:size];
		[window setContentMaxSize:size];
	}
}

/* like XParseGeometry() */
int
parsegeometry(const char *s, int *x, int *y, uint *w, uint *h)
{
	int mask = 0;
	long v;
	char *end;

	if (*s == '=')
		s++;
	if (isdigit(*s)) {
		v = strtol(s, &end, 10);
		if (*end != 'x' && *end != 'X')
			return 0;
		*w = v;
		mask |= WidthValue;
		s = end + 1;
		if (!isdigit(*s))
			return 0;
		*h = strtol(s, &end, 10);
		mask |= HeightValue;
		s = end;
	}
	if (*s == '+' || *s == '-') {
		if (*s == '-')
			mask |= XNegative;
		v = strtol(s, &end, 10);
		if (end == s + 1)
			return 0;
		*x = v;
		mask |= XValue;
		s = end;
		if (*s != '+' && *s != '-')
			return 0;
		if (*s == '-')
			mask |= YNegative;
		v = strtol(s, &end, 10);
		if (end == s + 1)
			return 0;
		*y = v;
		mask |= YValue;
		s = end;
	}
	return *s ? 0 : mask;
}

void
xloadfont(Font *f, CTFontRef base, CTFontSymbolicTraits want)
{
	CTFontSymbolicTraits have;
	CGAffineTransform skew = { 1, 0, 0.2, 1, 0, 0 };
	CGGlyph glyphs[sizeof(ascii_printable)];
	UniChar chars[sizeof(ascii_printable)];
	double adv;
	int i, len = strlen(ascii_printable);

	f->badslant = f->badweight = f->fakebold = 0;
	f->match = NULL;
	if (want)
		f->match = CTFontCreateCopyWithSymbolicTraits(base, 0, NULL,
				want, want);

	/* no such face, fake it like fontconfig does */
	if (!f->match) {
		f->match = CTFontCreateCopyWithAttributes(base, 0,
				(want & kCTFontItalicTrait) ? &skew : NULL,
				NULL);
		if (want & kCTFontBoldTrait)
			f->fakebold = 1;
	}
	if (!f->match)
		die("can't open font %s\n", usedfont);

	have = CTFontGetSymbolicTraits(f->match);
	if ((want & kCTFontBoldTrait) && !(have & kCTFontBoldTrait) &&
	    !f->fakebold) {
		f->badweight = 1;
		fputs("font weight does not match\n", stderr);
	}

	for (i = 0; i < len; i++)
		chars[i] = ascii_printable[i];
	CTFontGetGlyphsForCharacters(f->match, chars, glyphs, len);
	adv = CTFontGetAdvancesForGlyphs(f->match,
			kCTFontOrientationHorizontal, glyphs, NULL, len);

	f->ascent = ceil(CTFontGetAscent(f->match));
	f->descent = ceil(CTFontGetDescent(f->match));

	f->height = f->ascent + f->descent;
	f->width = ceil(adv / len);
}

/* parses a fontconfig or XLFD font name */
static CTFontRef
xcreatefont(const char *fontstr, double *size, CTFontSymbolicTraits *traits)
{
	char *s, *orig, *tok, *val, *family, *fields[15];
	CTFontDescriptorRef desc;
	CTFontRef font, f;
	CFStringRef name, have;
	double pixelsize = 0, ptsize = 0;
	int n, xlfd = fontstr[0] == '-';

	s = orig = xstrdup(fontstr);
	*traits = 0;
	dc.antialias = 1;
	family = NULL;

	if (xlfd) {
		for (n = 0, tok = s + 1; n < LEN(fields); n++) {
			fields[n] = tok;
			if (!(tok = strchr(tok, '-')))
				break;
			*tok++ = '\0';
		}
		if (n >= 1 && fields[1][0] && strcmp(fields[1], "*"))
			family = fields[1];
		if (n >= 2 && strcasestr(fields[2], "bold"))
			*traits |= kCTFontBoldTrait;
		if (n >= 3 && (!strcasecmp(fields[3], "i") ||
		               !strcasecmp(fields[3], "o")))
			*traits |= kCTFontItalicTrait;
		if (n >= 6)
			pixelsize = atof(fields[6]);
		if (n >= 7 && pixelsize <= 0)
			ptsize = atof(fields[7]) / 10;
	} else {
		/* "Family-size" */
		tok = strsep(&s, ":");
		if ((val = strchr(tok, ',')))
			*val = '\0';
		if ((val = strrchr(tok, '-')) && val[1] &&
		    strspn(val + 1, "0123456789.") == strlen(val + 1)) {
			*val++ = '\0';
			ptsize = atof(val);
		}
		if (tok[0])
			family = tok;
		while ((tok = strsep(&s, ":"))) {
			if (!(val = strchr(tok, '=')))
				val = "";
			else
				*val++ = '\0';
			if (!strcasecmp(tok, "pixelsize")) {
				pixelsize = atof(val);
			} else if (!strcasecmp(tok, "size")) {
				ptsize = atof(val);
			} else if (!strcasecmp(tok, "family")) {
				family = val;
			} else if (!strcasecmp(tok, "antialias")) {
				dc.antialias = !strcasecmp(val, "true") ||
				               !strcmp(val, "1");
			} else if (!strcasecmp(tok, "style")) {
				if (strcasestr(val, "bold"))
					*traits |= kCTFontBoldTrait;
				if (strcasestr(val, "italic") ||
				    strcasestr(val, "oblique"))
					*traits |= kCTFontItalicTrait;
			} else if (!strcasecmp(tok, "weight")) {
				if (strcasestr(val, "bold") ||
				    strcasestr(val, "black") ||
				    strcasestr(val, "heavy") || atoi(val) >= 200)
					*traits |= kCTFontBoldTrait;
			} else if (!strcasecmp(tok, "slant")) {
				if (strcasestr(val, "italic") ||
				    strcasestr(val, "oblique") || atoi(val) > 0)
					*traits |= kCTFontItalicTrait;
			} else if (!strcasecmp(tok, "bold")) {
				*traits |= kCTFontBoldTrait;
			} else if (!strcasecmp(tok, "italic")) {
				*traits |= kCTFontItalicTrait;
			}
		}
	}

	*size = pixelsize > 0 ? pixelsize : ptsize > 0 ? ptsize : 0;

	font = NULL;
	if (family && strcasecmp(family, "monospace") &&
	    strcasecmp(family, "mono")) {
		name = CFStringCreateWithCString(NULL, family,
				kCFStringEncodingUTF8);
		desc = CTFontDescriptorCreateWithAttributes((__bridge
		       CFDictionaryRef)@{ (__bridge id)kCTFontFamilyNameAttribute:
		                          (__bridge id)name });
		font = CTFontCreateWithFontDescriptor(desc, 12, NULL);
		CFRelease(desc);

		/* unknown families get a default font */
		have = CTFontCopyFamilyName(font);
		if (CFStringCompare(have, name, kCFCompareCaseInsensitive)
		    != kCFCompareEqualTo) {
			CFRelease(font);
			font = NULL;
		}
		CFRelease(have);
		CFRelease(name);
	}
	/* fall back to Menlo */
	if (!font)
		font = CTFontCreateWithName(CFSTR("Menlo-Regular"), 12, NULL);

	if (*traits && (f = CTFontCreateCopyWithSymbolicTraits(font, 0, NULL,
	                *traits, *traits))) {
		CFRelease(font);
		font = f;
	}

	free(orig);
	return font;
}

void
xloadfonts(const char *fontstr, double fontsize)
{
	CTFontSymbolicTraits traits;
	CTFontRef base, sized;
	double fontval;

	base = xcreatefont(fontstr, &fontval, &traits);
	if (!base)
		die("can't open font %s\n", fontstr);

	if (fontsize > 1) {
		usedfontsize = fontsize;
	} else {
		/*
		 * Default font size is 12, if none given. This is to
		 * have a known usedfontsize value.
		 */
		usedfontsize = fontval > 0 ? fontval : 12;
		defaultfontsize = usedfontsize;
	}

	sized = CTFontCreateCopyWithAttributes(base, usedfontsize, NULL, NULL);
	CFRelease(base);
	if (!sized)
		die("can't open font %s\n", fontstr);

	xloadfont(&dc.font, sized, traits);

	/* Setting character width and height. */
	win.cw = ceilf(dc.font.width * cwscale);
	win.ch = ceilf(dc.font.height * chscale);

	xloadfont(&dc.ifont, sized, traits | kCTFontItalicTrait);
	xloadfont(&dc.ibfont, sized, traits | kCTFontItalicTrait |
	          kCTFontBoldTrait);
	xloadfont(&dc.bfont, sized, traits | kCTFontBoldTrait);

	CFRelease(sized);
}

void
xunloadfont(Font *f)
{
	CFRelease(f->match);
	f->match = NULL;
}

void
xunloadfonts(void)
{
	/* Free the loaded fonts in the font cache.  */
	while (frclen > 0)
		CFRelease(frc[--frclen].font);

	xunloadfont(&dc.font);
	xunloadfont(&dc.bfont);
	xunloadfont(&dc.ifont);
	xunloadfont(&dc.ibfont);
}

static NSCursor *
xcreatecursor(void)
{
	NSImage *img;
	Color fg, bg;
	NSColor *nfg, *nbg;

	switch (mouseshape) {
	case XC_left_ptr:
	case XC_arrow:
	case XC_top_left_arrow:
		return [NSCursor arrowCursor];
	case XC_hand1:
	case XC_hand2:
		return [NSCursor pointingHandCursor];
	case XC_crosshair:
	case XC_cross:
	case XC_tcross:
		return [NSCursor crosshairCursor];
	case XC_xterm:
		break;
	default:
		return [NSCursor IBeamCursor];
	}

	/* I-beam in mousefg with a mousebg outline */
	if (!xloadcolor(mousefg, NULL, &fg))
		fg = (Color){ 0xffff, 0xffff, 0xffff, 0xffff };
	if (!xloadcolor(mousebg, NULL, &bg))
		bg = (Color){ 0, 0, 0, 0xffff };
	nfg = [NSColor colorWithSRGBRed:fg.red / 65535.0
	       green:fg.green / 65535.0 blue:fg.blue / 65535.0 alpha:1];
	nbg = [NSColor colorWithSRGBRed:bg.red / 65535.0
	       green:bg.green / 65535.0 blue:bg.blue / 65535.0 alpha:1];

	img = [NSImage imageWithSize:NSMakeSize(9, 18) flipped:YES
	       drawingHandler:^BOOL(NSRect r) {
		NSBezierPath *p = [NSBezierPath bezierPath];

		[p moveToPoint:NSMakePoint(1.5, 1.5)];
		[p lineToPoint:NSMakePoint(7.5, 1.5)];
		[p moveToPoint:NSMakePoint(4.5, 1.5)];
		[p lineToPoint:NSMakePoint(4.5, 16.5)];
		[p moveToPoint:NSMakePoint(1.5, 16.5)];
		[p lineToPoint:NSMakePoint(7.5, 16.5)];
		[p setLineCapStyle:NSLineCapStyleSquare];
		[nbg setStroke];
		[p setLineWidth:3];
		[p stroke];
		[nfg setStroke];
		[p setLineWidth:1];
		[p stroke];
		return YES;
	}];

	return [[NSCursor alloc] initWithImage:img hotSpot:NSMakePoint(4, 9)];
}

void
xinit(int cols, int rows)
{
	NSRect screen, frame;
	NSWindowStyleMask style;

	/* font */
	usedfont = (opt_font == NULL)? font : opt_font;
	xloadfonts(usedfont, 0);

	/* colors */
	xloadcols();

	/* adjust fixed window geometry */
	win.w = 2 * borderpx + cols * win.cw;
	win.h = 2 * borderpx + rows * win.ch;

	style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
	        NSWindowStyleMaskMiniaturizable;
	if (!xw.isfixed)
		style |= NSWindowStyleMaskResizable;

	window = [[NSWindow alloc]
	          initWithContentRect:NSMakeRect(0, 0, win.w, win.h)
	          styleMask:style backing:NSBackingStoreBuffered defer:NO];
	[window setReleasedWhenClosed:NO];
	[window setDelegate:(id<NSWindowDelegate>)[NSApp delegate]];
	[window setAcceptsMouseMovedEvents:YES];
	[window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
	[window setTabbingMode:NSWindowTabbingModeDisallowed];
	if (opt_class)
		[window setIdentifier:@(opt_class)];

	view = [[StView alloc] initWithFrame:NSMakeRect(0, 0, win.w, win.h)];
	[window setContentView:view];
	[window makeFirstResponder:view];

	/* position */
	screen = [[NSScreen mainScreen] frame];
	if (xw.gm & (XValue|YValue)) {
		frame = [window frame];
		if (xw.gm & XNegative)
			xw.l += screen.size.width - frame.size.width;
		if (xw.gm & YNegative)
			xw.t += screen.size.height - frame.size.height;
		[window setFrameTopLeftPoint:NSMakePoint(
		 screen.origin.x + xw.l, NSMaxY(screen) - xw.t)];
	} else {
		[window center];
	}

	xresizebuf();

	/* font spec buffer */
	xw.specbuf = xmalloc(cols * sizeof(GlyphFontSpec));

	win.mode = MODE_NUMLOCK | MODE_VISIBLE;
	resettitle();
	xhints();
	[window makeKeyAndOrderFront:nil];

	clock_gettime(CLOCK_MONOTONIC, &xsel.tclick1);
	clock_gettime(CLOCK_MONOTONIC, &xsel.tclick2);
	xsel.primary = NULL;
	xsel.clipboard = NULL;
}

static int
runetoutf16(Rune r, UniChar *c)
{
	if (r > 0x10FFFF || BETWEEN(r, 0xD800, 0xDFFF))
		r = 0xFFFD;
	if (r < 0x10000) {
		c[0] = r;
		return 1;
	}
	r -= 0x10000;
	c[0] = 0xD800 + (r >> 10);
	c[1] = 0xDC00 + (r & 0x3FF);
	return 2;
}

static CGGlyph
charindex(CTFontRef font, Rune rune)
{
	UniChar chars[2];
	CGGlyph glyphs[2] = { 0, 0 };
	int n;

	n = runetoutf16(rune, chars);
	CTFontGetGlyphsForCharacters(font, chars, glyphs, n);
	return glyphs[0];
}

int
xmakeglyphfontspecs(GlyphFontSpec *specs, const Glyph *glyphs, int len, int x, int y)
{
	CGFloat winx = borderpx + x * win.cw, winy = borderpx + y * win.ch, xp, yp;
	ushort mode, prevmode = USHRT_MAX;
	Font *font = &dc.font;
	int frcflags = FRC_NORMAL;
	CGFloat runewidth = win.cw;
	Rune rune;
	CGGlyph glyphidx;
	CFStringRef str;
	UniChar chars[2];
	int i, f, n, numspecs = 0;

	for (i = 0, xp = winx, yp = winy + font->ascent; i < len; ++i) {
		/* Fetch rune and mode for current glyph. */
		rune = glyphs[i].u;
		mode = glyphs[i].mode;

		/* Skip dummy wide-character spacing. */
		if (mode == ATTR_WDUMMY)
			continue;

		/* Determine font for glyph if different from previous glyph. */
		if (prevmode != mode) {
			prevmode = mode;
			font = &dc.font;
			frcflags = FRC_NORMAL;
			runewidth = win.cw * ((mode & ATTR_WIDE) ? 2.0f : 1.0f);
			if ((mode & ATTR_ITALIC) && (mode & ATTR_BOLD)) {
				font = &dc.ibfont;
				frcflags = FRC_ITALICBOLD;
			} else if (mode & ATTR_ITALIC) {
				font = &dc.ifont;
				frcflags = FRC_ITALIC;
			} else if (mode & ATTR_BOLD) {
				font = &dc.bfont;
				frcflags = FRC_BOLD;
			}
			yp = winy + font->ascent;
		}

		/* Lookup character index with default font. */
		glyphidx = charindex(font->match, rune);
		if (glyphidx) {
			specs[numspecs].font = font->match;
			specs[numspecs].glyph = glyphidx;
			specs[numspecs].x = xp;
			specs[numspecs].y = yp;
			specs[numspecs].fakebold = font->fakebold;
			xp += runewidth;
			numspecs++;
			continue;
		}

		/* Fallback on font cache, search the font cache for match. */
		for (f = 0; f < frclen; f++) {
			glyphidx = charindex(frc[f].font, rune);
			/* Everything correct. */
			if (glyphidx && frc[f].flags == frcflags)
				break;
			/* We got a default font for a not found glyph. */
			if (!glyphidx && frc[f].flags == frcflags
					&& frc[f].unicodep == rune) {
				break;
			}
		}

		/* Nothing was found. Use CoreText to find a fallback font. */
		if (f >= frclen) {
			n = runetoutf16(rune, chars);
			str = CFStringCreateWithCharacters(NULL, chars, n);

			/* Allocate memory for the new cache entry. */
			if (frclen >= frccap) {
				frccap += 16;
				frc = xrealloc(frc, frccap * sizeof(Fontcache));
			}

			frc[frclen].font = CTFontCreateForString(font->match,
					str, CFRangeMake(0, n));
			CFRelease(str);
			if (!frc[frclen].font)
				die("CTFontCreateForString failed seeking fallback font\n");
			frc[frclen].flags = frcflags;
			frc[frclen].unicodep = rune;

			glyphidx = charindex(frc[frclen].font, rune);

			f = frclen;
			frclen++;
		}

		specs[numspecs].font = frc[f].font;
		specs[numspecs].glyph = glyphidx;
		specs[numspecs].x = xp;
		specs[numspecs].y = yp;
		specs[numspecs].fakebold = font->fakebold;
		xp += runewidth;
		numspecs++;
	}

	return numspecs;
}

static void
xdrawspecs(const GlyphFontSpec *specs, int len, const Color *fg)
{
	CGGlyph glyphs[len];
	CGPoint pos[len];
	int i, j, n;

	CGContextSetRGBFillColor(xw.buf, fg->red / 65535.0,
			fg->green / 65535.0, fg->blue / 65535.0,
			fg->alpha / 65535.0);
	CGContextSetRGBStrokeColor(xw.buf, fg->red / 65535.0,
			fg->green / 65535.0, fg->blue / 65535.0,
			fg->alpha / 65535.0);

	/* one call per run of glyphs in the same font */
	for (i = 0; i < len; i = j) {
		for (j = i, n = 0; j < len && specs[j].font == specs[i].font &&
		     specs[j].fakebold == specs[i].fakebold; j++, n++) {
			glyphs[n] = specs[j].glyph;
			pos[n] = CGPointMake(specs[j].x, win.h - specs[j].y);
		}
		if (specs[i].fakebold) {
			CGContextSetTextDrawingMode(xw.buf, kCGTextFillStroke);
			CGContextSetLineWidth(xw.buf,
			      MAX(0.5, CTFontGetSize(specs[i].font) / 24));
		}
		CTFontDrawGlyphs(specs[i].font, glyphs, pos, n, xw.buf);
		if (specs[i].fakebold)
			CGContextSetTextDrawingMode(xw.buf, kCGTextFill);
	}
}

void
xdrawglyphfontspecs(const GlyphFontSpec *specs, Glyph base, int len, int x, int y)
{
	int charlen = len * ((base.mode & ATTR_WIDE) ? 2 : 1);
	int winx = borderpx + x * win.cw, winy = borderpx + y * win.ch,
	    width = charlen * win.cw;
	Color *fg, *bg, *temp, revfg, revbg, truefg, truebg;

	/* Fallback on color display for attributes not supported by the font */
	if (base.mode & ATTR_ITALIC && base.mode & ATTR_BOLD) {
		if (dc.ibfont.badslant || dc.ibfont.badweight)
			base.fg = defaultattr;
	} else if ((base.mode & ATTR_ITALIC && dc.ifont.badslant) ||
	    (base.mode & ATTR_BOLD && dc.bfont.badweight)) {
		base.fg = defaultattr;
	}

	if (IS_TRUECOL(base.fg)) {
		truefg.alpha = 0xffff;
		truefg.red = TRUERED(base.fg) | TRUERED(base.fg) >> 8;
		truefg.green = TRUEGREEN(base.fg) | TRUEGREEN(base.fg) >> 8;
		truefg.blue = TRUEBLUE(base.fg) | TRUEBLUE(base.fg) >> 8;
		fg = &truefg;
	} else {
		fg = &dc.col[base.fg];
	}

	if (IS_TRUECOL(base.bg)) {
		truebg.alpha = 0xffff;
		truebg.green = TRUEGREEN(base.bg) | TRUEGREEN(base.bg) >> 8;
		truebg.red = TRUERED(base.bg) | TRUERED(base.bg) >> 8;
		truebg.blue = TRUEBLUE(base.bg) | TRUEBLUE(base.bg) >> 8;
		bg = &truebg;
	} else {
		bg = &dc.col[base.bg];
	}

	/* Change basic system colors [0-7] to bright system colors [8-15] */
	if ((base.mode & ATTR_BOLD_FAINT) == ATTR_BOLD && BETWEEN(base.fg, 0, 7))
		fg = &dc.col[base.fg + 8];

	if (IS_SET(MODE_REVERSE)) {
		if (fg == &dc.col[defaultfg]) {
			fg = &dc.col[defaultbg];
		} else {
			revfg.red = ~fg->red;
			revfg.green = ~fg->green;
			revfg.blue = ~fg->blue;
			revfg.alpha = fg->alpha;
			fg = &revfg;
		}

		if (bg == &dc.col[defaultbg]) {
			bg = &dc.col[defaultfg];
		} else {
			revbg.red = ~bg->red;
			revbg.green = ~bg->green;
			revbg.blue = ~bg->blue;
			revbg.alpha = bg->alpha;
			bg = &revbg;
		}
	}

	if ((base.mode & ATTR_BOLD_FAINT) == ATTR_FAINT) {
		revfg.red = fg->red / 2;
		revfg.green = fg->green / 2;
		revfg.blue = fg->blue / 2;
		revfg.alpha = fg->alpha;
		fg = &revfg;
	}

	if (base.mode & ATTR_REVERSE) {
		temp = fg;
		fg = bg;
		bg = temp;
	}

	if (base.mode & ATTR_BLINK && win.mode & MODE_BLINK)
		fg = bg;

	if (base.mode & ATTR_INVISIBLE)
		fg = bg;

	/* Intelligent cleaning up of the borders. */
	if (x == 0) {
		xclear(0, (y == 0)? 0 : winy, borderpx,
			winy + win.ch +
			((winy + win.ch >= borderpx + win.th)? win.h : 0));
	}
	if (winx + width >= borderpx + win.tw) {
		xclear(winx + width, (y == 0)? 0 : winy, win.w,
			((winy + win.ch >= borderpx + win.th)? win.h : (winy + win.ch)));
	}
	if (y == 0)
		xclear(winx, 0, winx + width, borderpx);
	if (winy + win.ch >= borderpx + win.th)
		xclear(winx, winy + win.ch, winx + width, win.h);

	/* Clean up the region we want to draw to. */
	xfillrect(bg, winx, winy, width, win.ch);

	/* glyphs can overhang the cells */
	CGContextSaveGState(xw.buf);
	CGContextClipToRect(xw.buf, CGRectMake(winx, win.h - winy - win.ch,
	                    width, win.ch));

	/* Render the glyphs. */
	xdrawspecs(specs, len, fg);

	/* Render underline and strikethrough. */
	if (base.mode & ATTR_UNDERLINE) {
		xfillrect(fg, winx, winy + dc.font.ascent * chscale + 1,
				width, 1);
	}

	if (base.mode & ATTR_STRUCK) {
		xfillrect(fg, winx, winy + 2 * dc.font.ascent * chscale / 3,
				width, 1);
	}

	/* Reset clip to none. */
	CGContextRestoreGState(xw.buf);
}

void
xdrawglyph(Glyph g, int x, int y)
{
	int numspecs;
	GlyphFontSpec spec;

	numspecs = xmakeglyphfontspecs(&spec, &g, 1, x, y);
	xdrawglyphfontspecs(&spec, g, numspecs, x, y);
}

void
xdrawcursor(int cx, int cy, Glyph g, int ox, int oy, Glyph og)
{
	Color drawcol;

	/* remove the old cursor */
	if (selected(ox, oy))
		og.mode ^= ATTR_REVERSE;
	xdrawglyph(og, ox, oy);

	if (IS_SET(MODE_HIDE))
		return;

	/*
	 * Select the right color for the right mode.
	 */
	g.mode &= ATTR_BOLD|ATTR_ITALIC|ATTR_UNDERLINE|ATTR_STRUCK|ATTR_WIDE;

	if (IS_SET(MODE_REVERSE)) {
		g.mode |= ATTR_REVERSE;
		g.bg = defaultfg;
		if (selected(cx, cy)) {
			drawcol = dc.col[defaultcs];
			g.fg = defaultrcs;
		} else {
			drawcol = dc.col[defaultrcs];
			g.fg = defaultcs;
		}
	} else {
		if (selected(cx, cy)) {
			g.fg = defaultfg;
			g.bg = defaultrcs;
		} else {
			g.fg = defaultbg;
			g.bg = defaultcs;
		}
		drawcol = dc.col[g.bg];
	}

	/* draw the new one */
	if (IS_SET(MODE_FOCUSED)) {
		switch (win.cursor) {
		case 7: /* st extension */
			g.u = 0x2603; /* snowman (U+2603) */
			/* FALLTHROUGH */
		case 0: /* Blinking Block */
		case 1: /* Blinking Block (Default) */
		case 2: /* Steady Block */
			xdrawglyph(g, cx, cy);
			break;
		case 3: /* Blinking Underline */
		case 4: /* Steady Underline */
			xfillrect(&drawcol,
					borderpx + cx * win.cw,
					borderpx + (cy + 1) * win.ch - \
						cursorthickness,
					win.cw, cursorthickness);
			break;
		case 5: /* Blinking bar */
		case 6: /* Steady bar */
			xfillrect(&drawcol,
					borderpx + cx * win.cw,
					borderpx + cy * win.ch,
					cursorthickness, win.ch);
			break;
		}
	} else {
		xfillrect(&drawcol,
				borderpx + cx * win.cw,
				borderpx + cy * win.ch,
				win.cw - 1, 1);
		xfillrect(&drawcol,
				borderpx + cx * win.cw,
				borderpx + cy * win.ch,
				1, win.ch - 1);
		xfillrect(&drawcol,
				borderpx + (cx + 1) * win.cw - 1,
				borderpx + cy * win.ch,
				1, win.ch - 1);
		xfillrect(&drawcol,
				borderpx + cx * win.cw,
				borderpx + (cy + 1) * win.ch - 1,
				win.cw, 1);
	}
}

void
xsetenv(void)
{
	char buf[sizeof(long) * 8 + 1];

	snprintf(buf, sizeof(buf), "%lu", (ulong)[window windowNumber]);
	setenv("WINDOWID", buf, 1);
}

static NSString *
utf8string(const char *p)
{
	NSString *s;

	if (!(s = [NSString stringWithUTF8String:p]))
		s = [NSString stringWithCString:p
		     encoding:NSISOLatin1StringEncoding];
	return s ? s : @"";
}

void
xseticontitle(char *p)
{
	DEFAULT(p, opt_title);

	if (p[0] == '\0')
		p = opt_title;

	[window setMiniwindowTitle:utf8string(p)];
}

void
xsettitle(char *p)
{
	DEFAULT(p, opt_title);

	if (p[0] == '\0')
		p = opt_title;

	[window setTitle:utf8string(p)];
}

int
xstartdraw(void)
{
	return IS_SET(MODE_VISIBLE);
}

void
xdrawline(Line line, int x1, int y1, int x2)
{
	int i, x, ox, numspecs;
	Glyph base, new;
	GlyphFontSpec *specs = xw.specbuf;

	numspecs = xmakeglyphfontspecs(specs, &line[x1], x2 - x1, x1, y1);
	i = ox = 0;
	for (x = x1; x < x2 && i < numspecs; x++) {
		new = line[x];
		if (new.mode == ATTR_WDUMMY)
			continue;
		if (selected(x, y1))
			new.mode ^= ATTR_REVERSE;
		if (i > 0 && ATTRCMP(base, new)) {
			xdrawglyphfontspecs(specs, base, i, ox, y1);
			specs += i;
			numspecs -= i;
			i = 0;
		}
		if (i == 0) {
			ox = x;
			base = new;
		}
		i++;
	}
	if (i > 0)
		xdrawglyphfontspecs(specs, base, i, ox, y1);
}

void
xfinishdraw(void)
{
	[view setNeedsDisplay:YES];
}

void
xximspot(int x, int y)
{
	xw.ime.x = x;
	xw.ime.y = y;
}

void
xsetpointermotion(int set)
{
	xw.pointermotion = set;
}

void
xsetmode(int set, unsigned int flags)
{
	int mode = win.mode;
	MODBIT(win.mode, set, flags);
	if ((win.mode & MODE_REVERSE) != (mode & MODE_REVERSE))
		redraw();
}

int
xsetcursor(int cursor)
{
	if (!BETWEEN(cursor, 0, 7)) /* 7: st extension */
		return 1;
	win.cursor = cursor;
	return 0;
}

void
xseturgency(int add)
{
	if (add) {
		if (!xw.attention)
			xw.attention = [NSApp requestUserAttention:
			                NSInformationalRequest];
	} else if (xw.attention) {
		[NSApp cancelUserAttentionRequest:xw.attention];
		xw.attention = 0;
	}
}

void
xbell(void)
{
	if (!(IS_SET(MODE_FOCUSED)))
		xseturgency(1);
	if (bellvolume)
		NSBeep();
}

void
focus(int in)
{
	if (in) {
		win.mode |= MODE_FOCUSED;
		xseturgency(0);
		if (IS_SET(MODE_FOCUS))
			ttywrite("\033[I", 3, 0);
	} else {
		win.mode &= ~MODE_FOCUSED;
		if (IS_SET(MODE_FOCUS))
			ttywrite("\033[O", 3, 0);
	}
}

int
match(uint mask, uint state)
{
	return mask == XK_ANY_MOD || mask == (state & ~ignoremod);
}

char*
kmap(KeySym k, uint state)
{
	Key *kp;
	int i;

	/* Check for mapped keys out of X11 function keys. */
	for (i = 0; i < LEN(mappedkeys); i++) {
		if (mappedkeys[i] == k)
			break;
	}
	if (i == LEN(mappedkeys)) {
		if ((k & 0xFFFF) < 0xFD00)
			return NULL;
	}

	for (kp = key; kp < key + LEN(key); kp++) {
		if (kp->k != k)
			continue;

		if (!match(kp->mask, state))
			continue;

		if (IS_SET(MODE_APPKEYPAD) ? kp->appkey < 0 : kp->appkey > 0)
			continue;
		if (IS_SET(MODE_NUMLOCK) && kp->appkey == 2)
			continue;

		if (IS_SET(MODE_APPCURSOR) ? kp->appcursor < 0 : kp->appcursor > 0)
			continue;

		return kp->s;
	}

	return NULL;
}

/* Command is Mod4, the Option key set by OPTIONMETA is Mod1 */
static uint
modstate(NSEventModifierFlags f)
{
	uint state = 0;
	int lalt, ralt;

	if (f & NSEventModifierFlagShift)
		state |= ShiftMask;
	if (f & NSEventModifierFlagCapsLock)
		state |= LockMask;
	if (f & NSEventModifierFlagControl)
		state |= ControlMask;
	if (f & NSEventModifierFlagCommand)
		state |= Mod4Mask;
	if (f & NSEventModifierFlagOption) {
		lalt = (f & NX_DEVICELALTKEYMASK) != 0;
		ralt = (f & NX_DEVICERALTKEYMASK) != 0;
		if (!lalt && !ralt)
			lalt = 1;
		if ((lalt && (OPTIONMETA & 1)) || (ralt && (OPTIONMETA & 2)))
			state |= Mod1Mask;
	}
	return state;
}

/* by virtual key code */
static const struct {
	ushort code;
	KeySym ksym;
	char *s; /* sent if config.h has no mapping */
} speckeys[] = {
	{ 0x24, XK_Return,       "\r"   },
	{ 0x30, XK_Tab,          "\t"   },
	{ 0x33, XK_BackSpace,    "\b"   },
	{ 0x35, XK_Escape,       "\033" },
	{ 0x75, XK_Delete,       "\177" },
	{ 0x72, XK_Insert,       ""     }, /* Help */
	{ 0x73, XK_Home,         ""     },
	{ 0x77, XK_End,          ""     },
	{ 0x74, XK_Prior,        ""     },
	{ 0x79, XK_Next,         ""     },
	{ 0x7B, XK_Left,         ""     },
	{ 0x7C, XK_Right,        ""     },
	{ 0x7D, XK_Down,         ""     },
	{ 0x7E, XK_Up,           ""     },
	{ 0x6E, XK_Menu,         ""     },
	{ 0x7A, XK_F1,           ""     },
	{ 0x78, XK_F2,           ""     },
	{ 0x63, XK_F3,           ""     },
	{ 0x76, XK_F4,           ""     },
	{ 0x60, XK_F5,           ""     },
	{ 0x61, XK_F6,           ""     },
	{ 0x62, XK_F7,           ""     },
	{ 0x64, XK_F8,           ""     },
	{ 0x65, XK_F9,           ""     },
	{ 0x6D, XK_F10,          ""     },
	{ 0x67, XK_F11,          ""     },
	{ 0x6F, XK_F12,          ""     },
	{ 0x69, XK_F13,          ""     },
	{ 0x6B, XK_F14,          ""     },
	{ 0x71, XK_F15,          ""     },
	{ 0x6A, XK_F16,          ""     },
	{ 0x40, XK_F17,          ""     },
	{ 0x4F, XK_F18,          ""     },
	{ 0x50, XK_F19,          ""     },
	{ 0x5A, XK_F20,          ""     },
	{ 0x47, XK_Num_Lock,     ""     }, /* Clear */
	{ 0x4C, XK_KP_Enter,     "\r"   },
	{ 0x41, XK_KP_Decimal,   NULL   },
	{ 0x43, XK_KP_Multiply,  NULL   },
	{ 0x45, XK_KP_Add,       NULL   },
	{ 0x4B, XK_KP_Divide,    NULL   },
	{ 0x4E, XK_KP_Subtract,  NULL   },
	{ 0x51, XK_KP_Equal,     NULL   },
	{ 0x52, XK_KP_0,         NULL   },
	{ 0x53, XK_KP_1,         NULL   },
	{ 0x54, XK_KP_2,         NULL   },
	{ 0x55, XK_KP_3,         NULL   },
	{ 0x56, XK_KP_4,         NULL   },
	{ 0x57, XK_KP_5,         NULL   },
	{ 0x58, XK_KP_6,         NULL   },
	{ 0x59, XK_KP_7,         NULL   },
	{ 0x5B, XK_KP_8,         NULL   },
	{ 0x5C, XK_KP_9,         NULL   },
};

static KeySym
runetokeysym(Rune c)
{
	/* Latin-1 keysyms are the code points, others 0x01000000 + UCS */
	if ((c >= 0x20 && c < 0x7F) || (c >= 0xA0 && c <= 0xFF))
		return c;
	return 0x01000000 | c;
}

static Rune
firstrune(NSString *s)
{
	UniChar c[2];

	if ([s length] == 0)
		return 0;
	c[0] = [s characterAtIndex:0];
	if (CFStringIsSurrogateHighCharacter(c[0]) && [s length] > 1) {
		c[1] = [s characterAtIndex:1];
		return CFStringGetLongCharacterForSurrogatePair(c[0], c[1]);
	}
	return c[0];
}

/* like kpress() in x.c, returns 0 to pass the key to the input method */
static int
kpress(NSEvent *ev, int ime)
{
	KeySym ksym = NoSymbol;
	char buf[64], *customkey;
	const char *text = NULL;
	int len, i;
	uint state;
	Rune c = 0;
	Shortcut *bp;
	NSString *chars;

	if (IS_SET(MODE_KBDLOCK))
		return 1;

	state = modstate([ev modifierFlags]);

	for (i = 0; i < LEN(speckeys); i++) {
		if (speckeys[i].code == [ev keyCode]) {
			ksym = speckeys[i].ksym;
			text = speckeys[i].s;
			break;
		}
	}
	if (ksym == XK_Tab && (state & ShiftMask))
		ksym = XK_ISO_Left_Tab;

	/* with Shift, and with Option unless it is Alt */
	if ((state & Mod1Mask) || !([ev modifierFlags] &
	    NSEventModifierFlagOption))
		chars = [ev charactersIgnoringModifiers];
	else if ([[ev characters] length])
		chars = [ev characters];
	else
		chars = [ev charactersIgnoringModifiers];

	if (ksym == NoSymbol || text == NULL) {
		c = firstrune(chars);
		if (c >= 0xF700 && c <= 0xF8FF) /* Cocoa function keys */
			c = 0;
		if (ksym == NoSymbol && c)
			ksym = runetokeysym(c);
	}

	/* 1. shortcuts */
	for (bp = shortcuts; bp < shortcuts + LEN(shortcuts); bp++) {
		if (ksym == bp->keysym && match(bp->mod, state)) {
			bp->func(&(bp->arg));
			return 1;
		}
	}

	/* 2. custom keys from config.h */
	if ((customkey = kmap(ksym, state))) {
		ttywrite(customkey, strlen(customkey), 1);
		return 1;
	}

	/* 3. composed string from input method */
	if (text) {
		len = strlen(text);
		memcpy(buf, text, len);
	} else if (!c) {
		return 1;
	} else if (ime && !(state & (ControlMask|Mod1Mask|Mod4Mask)) &&
	           !BETWEEN(ksym, XK_KP_Space, XK_KP_9)) {
		return 0;
	} else {
		if (state & ControlMask) {
			/* like XLookupString() */
			if ((c >= '@' && c < 0177) || c == ' ')
				c &= 0x1F;
			else if (c == '2')
				c = '\0';
			else if (c >= '3' && c <= '7')
				c -= ('3' - '\033');
			else if (c == '8')
				c = '\177';
			else if (c == '/')
				c = '_' & 0x1F;
		}
		len = utf8encode(c, buf);
	}

	if (len == 0)
		return 1;
	if (len == 1 && state & Mod1Mask) {
		if (IS_SET(MODE_8BIT)) {
			if (*buf < 0177) {
				c = *buf | 0x80;
				len = utf8encode(c, buf);
			}
		} else {
			buf[1] = buf[0];
			buf[0] = '\033';
			len = 2;
		}
	}
	ttywrite(buf, len, 1);
	return 1;
}

static uint
evbutton(NSEvent *ev)
{
	NSInteger n = [ev buttonNumber];

	/* X numbering: left 1, middle 2, right 3, back 8, forward 9 */
	return n == 0 ? Button1 : n == 1 ? Button3 : n == 2 ? Button2 : n + 5;
}

static uint
buttonstate(void)
{
	uint i, state = 0;

	for (i = 1; i <= 5; i++)
		if (buttons & (1 << (i-1)))
			state |= buttonmask(i);
	return state;
}

static void
mouseevent(NSEvent *ev, int type, uint button)
{
	NSPoint p = [view convertPoint:[ev locationInWindow] fromView:nil];
	Event e;

	e.type = type;
	e.button = button;
	e.state = modstate([ev modifierFlags]) | buttonstate();
	e.x = floor(p.x);
	e.y = floor(p.y);

	switch (type) {
	case ButtonPress:
		bpress(&e);
		break;
	case ButtonRelease:
		brelease(&e);
		break;
	case MotionNotify:
		bmotion(&e);
		break;
	}
	schedule();
}

static void
scrollevent(NSEvent *ev)
{
	static CGFloat accx, accy;
	CGFloat dx = [ev scrollingDeltaX], dy = [ev scrollingDeltaY];
	uint btn;
	int n;

	/* trackpad deltas are in points, wheel deltas in lines */
	if ([ev hasPreciseScrollingDeltas]) {
		dx /= win.cw;
		dy /= win.ch;
	}
	if ([ev phase] == NSEventPhaseBegan)
		accx = accy = 0;
	accx += dx;
	accy += dy;

	for (n = trunc(accy); n; n += n > 0 ? -1 : 1) {
		btn = n > 0 ? Button4 : Button5;
		accy += n > 0 ? -1 : 1;
		mouseevent(ev, ButtonPress, btn);
		mouseevent(ev, ButtonRelease, btn);
	}
	for (n = trunc(accx); n; n += n > 0 ? -1 : 1) {
		btn = n > 0 ? 6 : 7;
		accx += n > 0 ? -1 : 1;
		mouseevent(ev, ButtonPress, btn);
		mouseevent(ev, ButtonRelease, btn);
	}
}

@implementation StView

- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)ev { return YES; }

- (instancetype)initWithFrame:(NSRect)frame
{
	NSTrackingArea *ta;

	if (!(self = [super initWithFrame:frame]))
		return nil;
	ta = [[NSTrackingArea alloc] initWithRect:NSZeroRect
	      options:NSTrackingMouseMoved | NSTrackingActiveAlways |
	              NSTrackingInVisibleRect
	      owner:self userInfo:nil];
	[self addTrackingArea:ta];
	return self;
}

- (void)resetCursorRects
{
	static NSCursor *cursor;

	if (!cursor)
		cursor = xcreatecursor();
	[self addCursorRect:[self bounds] cursor:cursor];
}

- (void)drawRect:(NSRect)rect
{
	CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
	CGImageRef img;
	const Color *bg = &dc.col[IS_SET(MODE_REVERSE) ? defaultfg : defaultbg];
	NSColor *fgc, *bgc;
	Color *fg;

	CGContextSetRGBFillColor(ctx, bg->red / 65535.0, bg->green / 65535.0,
	                         bg->blue / 65535.0, 1);
	CGContextFillRect(ctx, NSRectToCGRect(rect));

	if (xw.buf && (img = CGBitmapContextCreateImage(xw.buf))) {
		CGContextSaveGState(ctx);
		CGContextTranslateCTM(ctx, 0, win.h);
		CGContextScaleCTM(ctx, 1, -1);
		CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
		CGContextDrawImage(ctx, CGRectMake(0, 0, win.w, win.h), img);
		CGContextRestoreGState(ctx);
		CGImageRelease(img);
	}

	/* input method preedit text */
	if ([markedtext length]) {
		fg = &dc.col[IS_SET(MODE_REVERSE) ? defaultbg : defaultfg];
		fgc = [NSColor colorWithSRGBRed:fg->red / 65535.0
		       green:fg->green / 65535.0 blue:fg->blue / 65535.0
		       alpha:1];
		bgc = [NSColor colorWithSRGBRed:bg->red / 65535.0
		       green:bg->green / 65535.0 blue:bg->blue / 65535.0
		       alpha:1];
		[markedtext drawAtPoint:NSMakePoint(borderpx + xw.ime.x * win.cw,
		                                    borderpx + xw.ime.y * win.ch)
		 withAttributes:@{
			NSFontAttributeName: (__bridge NSFont *)dc.font.match,
			NSForegroundColorAttributeName: fgc,
			NSBackgroundColorAttributeName: bgc,
			NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
		}];
	}
}

- (void)setFrameSize:(NSSize)size
{
	[super setFrameSize:size];
	if (!xw.started || ((int)size.width == win.w &&
	    (int)size.height == win.h))
		return;
	cresize(size.width, size.height);
	drawnow();
}

- (void)viewDidChangeBackingProperties
{
	[super viewDidChangeBackingProperties];
	if (!xw.started || [window backingScaleFactor] == xw.scale)
		return;
	xresizebuf();
	redraw();
	drawnow();
}

- (void)keyDown:(NSEvent *)ev
{
	/* the input method gets all keys while composing */
	if ([markedtext length] || !kpress(ev, 1))
		[self interpretKeyEvents:@[ev]];
	schedule();
}

- (BOOL)performKeyEquivalent:(NSEvent *)ev
{
	/* or Control keys trigger Cocoa key bindings */
	if (!([ev modifierFlags] & NSEventModifierFlagCommand) &&
	    [window firstResponder] == self && [window isKeyWindow]) {
		[self keyDown:ev];
		return YES;
	}
	return [super performKeyEquivalent:ev];
}

- (void)mouseDown:(NSEvent *)ev { mouseevent(ev, ButtonPress, evbutton(ev)); }
- (void)rightMouseDown:(NSEvent *)ev { [self mouseDown:ev]; }
- (void)otherMouseDown:(NSEvent *)ev { [self mouseDown:ev]; }
- (void)mouseUp:(NSEvent *)ev { mouseevent(ev, ButtonRelease, evbutton(ev)); }
- (void)rightMouseUp:(NSEvent *)ev { [self mouseUp:ev]; }
- (void)otherMouseUp:(NSEvent *)ev { [self mouseUp:ev]; }
- (void)mouseDragged:(NSEvent *)ev { mouseevent(ev, MotionNotify, 0); }
- (void)rightMouseDragged:(NSEvent *)ev { [self mouseDragged:ev]; }
- (void)otherMouseDragged:(NSEvent *)ev { [self mouseDragged:ev]; }
- (void)scrollWheel:(NSEvent *)ev { scrollevent(ev); }

- (void)mouseMoved:(NSEvent *)ev
{
	if (xw.pointermotion)
		mouseevent(ev, MotionNotify, 0);
}

/* NSTextInputClient */

- (void)insertText:(id)string replacementRange:(NSRange)range
{
	const char *p;

	if ([string isKindOfClass:[NSAttributedString class]])
		string = [string string];
	markedtext = nil;
	[self setNeedsDisplay:YES];
	if (!(p = [string UTF8String]) || !*p)
		return;
	ttywrite(p, strlen(p), 1);
	schedule();
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)sel
     replacementRange:(NSRange)range
{
	if ([string isKindOfClass:[NSAttributedString class]])
		string = [string string];
	markedtext = [string copy];
	[self setNeedsDisplay:YES];
}

- (void)unmarkText
{
	markedtext = nil;
	[self setNeedsDisplay:YES];
}

- (BOOL)hasMarkedText
{
	return [markedtext length] > 0;
}

- (NSRange)markedRange
{
	return [markedtext length] ? NSMakeRange(0, [markedtext length])
	                           : NSMakeRange(NSNotFound, 0);
}

- (NSRange)selectedRange
{
	return NSMakeRange(NSNotFound, 0);
}

- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText
{
	return @[];
}

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range
     actualRange:(NSRangePointer)actual
{
	return nil;
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point
{
	return NSNotFound;
}

- (NSRect)firstRectForCharacterRange:(NSRange)range
     actualRange:(NSRangePointer)actual
{
	NSRect r = NSMakeRect(borderpx + xw.ime.x * win.cw,
	                      borderpx + xw.ime.y * win.ch, win.cw, win.ch);

	r = [self convertRect:r toView:nil];
	return [window convertRectToScreen:r];
}

- (void)doCommandBySelector:(SEL)sel
{
	/* kpress() handles these */
}

@end

@implementation StDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)n
{
	if (@available(macOS 14.0, *))
		[NSApp activate];
	else
		[NSApp activateIgnoringOtherApps:YES];
	[window makeKeyAndOrderFront:nil];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app
{
	ttyhangup();
	return NSTerminateNow;
}

- (BOOL)windowShouldClose:(NSWindow *)w
{
	ttyhangup();
	exit(0);
}

- (void)windowDidBecomeKey:(NSNotification *)n
{
	focus(1);
	schedule();
}

- (void)windowDidResignKey:(NSNotification *)n
{
	focus(0);
	schedule();
}

- (void)windowDidChangeOcclusionState:(NSNotification *)n
{
	int visible = ([window occlusionState] &
	               NSWindowOcclusionStateVisible) != 0;

	if (visible && !IS_SET(MODE_VISIBLE)) {
		win.mode |= MODE_VISIBLE;
		redraw(); /* like an X expose */
		schedule();
	} else if (!visible) {
		win.mode &= ~MODE_VISIBLE;
	}
}

- (void)copy:(id)sender { clipcopy(NULL); }
- (void)paste:(id)sender { clippaste(NULL); schedule(); }
- (void)pasteSelection:(id)sender { selpaste(NULL); schedule(); }
- (void)zoomIn:(id)sender { zoom(&(Arg){ .f = +1 }); drawnow(); }
- (void)zoomOut:(id)sender { zoom(&(Arg){ .f = -1 }); drawnow(); }
- (void)zoomReset:(id)sender { zoomreset(NULL); drawnow(); }

@end

static void
xmenu(void)
{
	NSMenu *bar, *m;
	NSMenuItem *it;
	NSString *app = [[NSProcessInfo processInfo] processName];

	bar = [NSMenu new];

	m = [[NSMenu alloc] initWithTitle:app];
	[m addItemWithTitle:[@"Hide " stringByAppendingString:app]
	   action:@selector(hide:) keyEquivalent:@"h"];
	it = [m addItemWithTitle:@"Hide Others"
	      action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
	[it setKeyEquivalentModifierMask:NSEventModifierFlagCommand |
	                                 NSEventModifierFlagOption];
	[m addItemWithTitle:@"Show All"
	   action:@selector(unhideAllApplications:) keyEquivalent:@""];
	[m addItem:[NSMenuItem separatorItem]];
	[m addItemWithTitle:[@"Quit " stringByAppendingString:app]
	   action:@selector(terminate:) keyEquivalent:@"q"];
	[[bar addItemWithTitle:@"" action:NULL keyEquivalent:@""] setSubmenu:m];

	m = [[NSMenu alloc] initWithTitle:@"Edit"];
	[m addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
	[m addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
	[m addItemWithTitle:@"Paste Selection"
	   action:@selector(pasteSelection:) keyEquivalent:@"V"];
	[[bar addItemWithTitle:@"" action:NULL keyEquivalent:@""] setSubmenu:m];

	m = [[NSMenu alloc] initWithTitle:@"View"];
	[m addItemWithTitle:@"Zoom In" action:@selector(zoomIn:)
	   keyEquivalent:@"+"];
	[m addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:)
	   keyEquivalent:@"-"];
	[m addItemWithTitle:@"Actual Size" action:@selector(zoomReset:)
	   keyEquivalent:@"0"];
	[m addItem:[NSMenuItem separatorItem]];
	it = [m addItemWithTitle:@"Enter Full Screen"
	      action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
	[it setKeyEquivalentModifierMask:NSEventModifierFlagCommand |
	                                 NSEventModifierFlagControl];
	[[bar addItemWithTitle:@"" action:NULL keyEquivalent:@""] setSubmenu:m];

	m = [[NSMenu alloc] initWithTitle:@"Window"];
	[m addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:)
	   keyEquivalent:@"m"];
	[m addItemWithTitle:@"Zoom" action:@selector(performZoom:)
	   keyEquivalent:@""];
	[m addItemWithTitle:@"Close" action:@selector(performClose:)
	   keyEquivalent:@"w"];
	[[bar addItemWithTitle:@"" action:NULL keyEquivalent:@""] setSubmenu:m];
	[NSApp setWindowsMenu:m];

	[NSApp setMainMenu:bar];
}

static void
armtimer(double ms)
{
	if (ms < 0) {
		dispatch_source_set_timer(drawtimer, DISPATCH_TIME_FOREVER,
				DISPATCH_TIME_FOREVER, 0);
		return;
	}
	dispatch_source_set_timer(drawtimer,
			dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC),
			DISPATCH_TIME_FOREVER, NSEC_PER_MSEC / 4);
}

/*
 * To reduce flicker and tearing, when new content or event
 * triggers drawing, we first wait a bit to ensure we got
 * everything, and if nothing new arrives - we draw.
 * We start with trying to wait minlatency ms. If more content
 * arrives sooner, we retry with shorter and shorter periods,
 * and eventually draw even without idle after maxlatency ms.
 * Typically this results in low latency while interacting,
 * maximum latency intervals during `cat huge.txt`, and perfect
 * sync with periodic updates from animations/key-repeats/etc.
 */
void
schedule(void)
{
	struct timespec now;
	double timeout;

	if (!xw.started)
		return;

	clock_gettime(CLOCK_MONOTONIC, &now);
	if (!drawing) {
		trigger = now;
		drawing = 1;
	}
	timeout = (maxlatency - TIMEDIFF(now, trigger)) \
	          / maxlatency * minlatency;
	if (timeout > 0)
		armtimer(timeout);  /* we have time, try to find idle */
	else
		drawnow();
}

/* idle detected or maxlatency exhausted -> draw */
void
drawnow(void)
{
	struct timespec now;
	double timeout = -1;

	clock_gettime(CLOCK_MONOTONIC, &now);
	if (blinktimeout && tattrset(ATTR_BLINK)) {
		timeout = blinktimeout - TIMEDIFF(now, lastblink);
		if (timeout <= 0) {
			if (-timeout > blinktimeout) /* start visible */
				win.mode |= MODE_BLINK;
			win.mode ^= MODE_BLINK;
			tsetdirtattr(ATTR_BLINK);
			lastblink = now;
			timeout = blinktimeout;
		}
	}

	draw();
	drawing = 0;
	armtimer(timeout);
}

void
run(void)
{
	int ttyfd;

	ttyfd = ttynew(opt_line, shell, opt_io, opt_cmd);
	xw.started = 1;
	cresize(view.frame.size.width, view.frame.size.height);

	ttysrc = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, ttyfd, 0,
	                                dispatch_get_main_queue());
	dispatch_source_set_event_handler(ttysrc, ^{
		ttyread();
		schedule();
	});
	drawtimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
	                                   dispatch_get_main_queue());
	dispatch_source_set_event_handler(drawtimer, ^{
		drawnow();
	});
	armtimer(-1);
	dispatch_resume(ttysrc);
	dispatch_resume(drawtimer);

	drawnow();
	[NSApp run];
}

void
usage(void)
{
	die("usage: %s [-aiv] [-c class] [-f font] [-g geometry]"
	    " [-n name] [-o file]\n"
	    "          [-T title] [-t title] [-w windowid]"
	    " [[-e] command [args ...]]\n"
	    "       %s [-aiv] [-c class] [-f font] [-g geometry]"
	    " [-n name] [-o file]\n"
	    "          [-T title] [-t title] [-w windowid] -l line"
	    " [stty_args ...]\n", argv0, argv0);
}

int
main(int argc, char *argv[])
{
	xw.l = xw.t = 0;
	xw.isfixed = 0;
	xsetcursor(cursorshape);

	ARGBEGIN {
	case 'a':
		allowaltscreen = 0;
		break;
	case 'c':
		opt_class = EARGF(usage());
		break;
	case 'e':
		if (argc > 0)
			--argc, ++argv;
		goto run;
	case 'f':
		opt_font = EARGF(usage());
		break;
	case 'g':
		xw.gm = parsegeometry(EARGF(usage()),
				&xw.l, &xw.t, &cols, &rows);
		break;
	case 'i':
		xw.isfixed = 1;
		break;
	case 'o':
		opt_io = EARGF(usage());
		break;
	case 'l':
		opt_line = EARGF(usage());
		break;
	case 'n':
		opt_name = EARGF(usage());
		break;
	case 't':
	case 'T':
		opt_title = EARGF(usage());
		break;
	case 'w':
		opt_embed = EARGF(usage());
		break;
	case 'v':
		die("%s " VERSION "\n", argv0);
		break;
	default:
		usage();
	} ARGEND;

run:
	if (argc > 0) /* eat all remaining arguments */
		opt_cmd = argv;

	if (!opt_title)
		opt_title = (opt_line || !opt_cmd) ? "st" : opt_cmd[0];

	if (opt_embed)
		fprintf(stderr, "%s: -w: embedding is not supported on macOS\n",
		        argv0);

	setlocale(LC_CTYPE, "");
	/* Finder starts apps with the C locale, wcwidth() needs UTF-8 */
	if (MB_CUR_MAX == 1)
		setlocale(LC_CTYPE, "UTF-8");
	cols = MAX(cols, 1);
	rows = MAX(rows, 1);

	@autoreleasepool {
		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		delegate = [StDelegate new];
		[NSApp setDelegate:delegate];
		xmenu();

		tnew(cols, rows);
		xinit(cols, rows);
		xsetenv();
		selinit();
		run();
	}

	return 0;
}
