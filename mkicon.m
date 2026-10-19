/* See LICENSE for license details. */
/* writes the st icon as an iconset for iconutil(1) */
#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>

#include <stdio.h>
#include <stdlib.h>

/* default st colors: gray90 on black */
#define FG 229 / 255.0, 229 / 255.0, 229 / 255.0
#define BG 0, 0, 0

static void
die(const char *msg)
{
	fputs(msg, stderr);
	exit(1);
}

/* on a 1024x1024 canvas */
static void
drawicon(CGContextRef c)
{
	CGRect body = CGRectMake(100, 100, 824, 824);
	CGPathRef shape;
	CTFontRef font;
	CFAttributedStringRef str;
	CFDictionaryRef attrs;
	CTLineRef line;
	CGColorRef fg, shadow;
	CGFloat x, y, cw, ch;

	/* size and corner radius of the macOS icon grid */
	shape = CGPathCreateWithRoundedRect(body, 185, 185, NULL);
	CGContextSaveGState(c);
	shadow = CGColorCreateSRGB(0, 0, 0, 0.35);
	CGContextSetShadowWithColor(c, CGSizeMake(0, -10), 20, shadow);
	CGColorRelease(shadow);
	CGContextAddPath(c, shape);
	CGContextSetRGBFillColor(c, BG, 1);
	CGContextFillPath(c);
	CGContextRestoreGState(c);

	/* keeps the edge visible on dark backgrounds */
	CGContextAddPath(c, shape);
	CGContextSetRGBStrokeColor(c, 1, 1, 1, 0.18);
	CGContextSetLineWidth(c, 6);
	CGContextStrokePath(c);

	/* "st" and a block cursor */
	font = CTFontCreateWithName(CFSTR("Menlo-Bold"), 300, NULL);
	fg = CGColorCreateSRGB(FG, 1);
	attrs = (__bridge CFDictionaryRef)@{
		(__bridge id)kCTFontAttributeName: (__bridge id)font,
		(__bridge id)kCTForegroundColorAttributeName: (__bridge id)fg,
	};
	str = CFAttributedStringCreate(NULL, CFSTR("st"), attrs);
	line = CTLineCreateWithAttributedString(str);

	/* three cells: s, t and the cursor */
	cw = CTLineGetTypographicBounds(line, NULL, NULL, NULL) / 2;
	ch = CTFontGetAscent(font) + CTFontGetDescent(font);
	x = 512 - 3 * cw / 2;
	y = 512 - ch / 2 + CTFontGetDescent(font);
	CGContextSetTextPosition(c, x, y);
	CTLineDraw(line, c);

	CGContextSetRGBFillColor(c, FG, 1);
	CGContextFillRect(c, CGRectMake(x + 2 * cw, y - CTFontGetDescent(font),
	                                cw, ch));

	CFRelease(line);
	CFRelease(str);
	CGColorRelease(fg);
	CFRelease(font);
	CGPathRelease(shape);
}

static void
writepng(const char *dir, const char *name, int px)
{
	CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGContextRef c;
	CGImageRef img;
	CGImageDestinationRef dst;
	NSURL *url;

	c = CGBitmapContextCreate(NULL, px, px, 8, 0, cs,
	                          (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
	if (!c)
		die("mkicon: can't create bitmap\n");
	CGContextScaleCTM(c, px / 1024.0, px / 1024.0);
	drawicon(c);

	img = CGBitmapContextCreateImage(c);
	url = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%s/%s",
	       dir, name]];
	dst = CGImageDestinationCreateWithURL((__bridge CFURLRef)url,
	                                      CFSTR("public.png"), 1, NULL);
	if (!dst)
		die("mkicon: can't write png\n");
	CGImageDestinationAddImage(dst, img, NULL);
	if (!CGImageDestinationFinalize(dst))
		die("mkicon: can't write png\n");

	CFRelease(dst);
	CGImageRelease(img);
	CGContextRelease(c);
	CGColorSpaceRelease(cs);
}

int
main(int argc, char *argv[])
{
	static const struct { const char *name; int px; } sizes[] = {
		{ "icon_16x16.png",       16 },
		{ "icon_16x16@2x.png",    32 },
		{ "icon_32x32.png",       32 },
		{ "icon_32x32@2x.png",    64 },
		{ "icon_128x128.png",    128 },
		{ "icon_128x128@2x.png", 256 },
		{ "icon_256x256.png",    256 },
		{ "icon_256x256@2x.png", 512 },
		{ "icon_512x512.png",    512 },
		{ "icon_512x512@2x.png", 1024 },
	};
	int i;

	if (argc != 2)
		die("usage: mkicon dir.iconset\n");
	@autoreleasepool {
		[[NSFileManager defaultManager] createDirectoryAtPath:@(argv[1])
		 withIntermediateDirectories:YES attributes:nil error:NULL];
		for (i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++)
			writepng(argv[1], sizes[i].name, sizes[i].px);
	}
	return 0;
}
