/*
 * generate-locations.c: writes locLCusLocationDB.pdb, the golden fixture for
 * the Swift Location codec (the custom locations of Prefs > Date & Time on
 * Palm OS 5; the built-in ones live in locLDefLocationDB with the same
 * record layout).
 *
 * The records are packed by hand, because pilot-link's pack_Timezone
 * writes the dstObserved and t4 bytes to the same offset (location.c) and
 * never writes the "unknown" byte, so its output does not match a device.
 * Each hand-packed record is checked with pilot-link's unpack_Location
 * before it is written, so the fixture agrees with the reader pilot-link
 * derived from real devices.
 *
 * Build against the libpisock that Scripts/build-pilot-link.sh installs:
 *
 *   P=.build/pilot-link/install
 *   clang -I$P/include -L$P/lib -lpisock -o /tmp/gen Tests/PalmSyncTests/Fixtures/generate-locations.c
 *   DYLD_LIBRARY_PATH=$P/lib /tmp/gen Tests/PalmSyncTests/Fixtures/locLCusLocationDB.pdb
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "pi-dlp.h"
#include "pi-file.h"
#include "pi-location.h"

#define FOURCC(a, b, c, d) \
	(((unsigned long)(a) << 24) | ((unsigned long)(b) << 16) | ((unsigned long)(c) << 8) | (unsigned long)(d))

struct rule { unsigned char weekday, week, month, unknown; };

static const struct rule no_rule = { 0, 0, 0, 0 };
static const struct rule second_sunday_march = { 0, 1, 3, 0 };
static const struct rule first_sunday_november = { 0, 0, 11, 0 };
static const struct rule first_sunday_october = { 0, 0, 10, 0 };
static const struct rule first_sunday_april = { 0, 0, 4, 0 };

static void put16(unsigned char **p, int v)
{
	*(*p)++ = (unsigned char)((v >> 8) & 0xff);
	*(*p)++ = (unsigned char)(v & 0xff);
}

/* A location record as the Palm stores it: the time zone (offset in
 * minutes, t2, DST start and end rules, observed 0x3c or 0, t4, 0x80,
 * name), an optional unknown byte, latitude and longitude as degrees and
 * minutes (negative = north / east), and the note (NUL even when empty). */
static int pack(unsigned char *out, int offset, struct rule start, struct rule end, int observed,
		const char *name, int has_unknown, unsigned char unknown,
		int lat_deg, int lat_min, int lon_deg, int lon_min, const char *note)
{
	unsigned char *p = out;

	put16(&p, offset);
	*p++ = 0;				/* t2 */
	*p++ = start.weekday; *p++ = start.week; *p++ = start.month; *p++ = start.unknown;
	*p++ = end.weekday; *p++ = end.week; *p++ = end.month; *p++ = end.unknown;
	*p++ = observed ? 0x3c : 0x00;
	*p++ = 0;				/* t4 */
	*p++ = 0x80;
	strcpy((char *)p, name);
	p += strlen(name) + 1;
	if (has_unknown)
		*p++ = unknown;
	put16(&p, lat_deg);
	put16(&p, lat_min);
	put16(&p, lon_deg);
	put16(&p, lon_min);
	strcpy((char *)p, note);
	p += strlen(note) + 1;
	return (int)(p - out);
}

/* pilot-link must read back what was packed */
static void verify(const unsigned char *data, int len, const char *name, int offset, int observed,
		   int has_unknown, int lat_deg, enum CompassDirection lat_dir, const char *note)
{
	pi_buffer_t *buf = pi_buffer_new(len);
	Location_t loc;

	pi_buffer_append(buf, data, len);
	memset(&loc, 0, sizeof(loc));
	if (unpack_Location(&loc, buf) < 0
	    || strcmp(loc.tz.name, name) != 0
	    || loc.tz.offset != offset
	    || loc.tz.dstObserved != observed
	    || loc.unknownExists != has_unknown
	    || loc.latitude.degrees != abs(lat_deg)
	    || loc.latitude.direction != lat_dir
	    || (loc.note == NULL ? note[0] != '\0' : strcmp(loc.note, note) != 0)) {
		fprintf(stderr, "pilot-link does not read back %s as packed\n", name);
		exit(1);
	}
	pi_buffer_free(buf);
}

static void append(pi_file_t *pf, const unsigned char *data, int len, unsigned long uid)
{
	if (pi_file_append_record(pf, (void *)data, len, 0, 0, uid) < 0) {
		fprintf(stderr, "pi_file_append_record failed\n");
		exit(1);
	}
}

int main(int argc, char **argv)
{
	struct DBInfo info;
	pi_file_t *pf;
	unsigned char rec[128];
	int len;

	if (argc != 2) {
		fprintf(stderr, "usage: %s <locLCusLocationDB.pdb>\n", argv[0]);
		return 2;
	}

	memset(&info, 0, sizeof(info));
	strcpy(info.name, "locLCusLocationDB");
	info.flags = dlpDBFlagBackup;
	info.type = FOURCC('D', 'A', 'T', 'A');
	info.creator = FOURCC('l', 'o', 'c', 'L');
	info.createDate = info.modifyDate = 1792368000;	/* 2026-10-19T00:00:00Z */

	pf = pi_file_create(argv[1], &info);
	if (pf == NULL) {
		fprintf(stderr, "cannot create %s\n", argv[1]);
		return 1;
	}

	/* 0: Vancouver after 2026-11-01: UTC-7 all year. 49°17'N 123°07'W */
	len = pack(rec, -420, no_rule, no_rule, 0, "Vancouver", 0, 0, -49, -17, 123, 7, "");
	verify(rec, len, "Vancouver", -420, 0, 0, -49, north, "");
	append(pf, rec, len, 0x3001);

	/* 1: Toronto, Eastern with DST. 43°39'N 79°23'W */
	len = pack(rec, -300, second_sunday_march, first_sunday_november, 1, "Toronto", 0, 0,
		   -43, -39, 79, 23, "Eastern");
	verify(rec, len, "Toronto", -300, 1, 0, -43, north, "Eastern");
	append(pf, rec, len, 0x3002);

	/* 2: Winnipeg after 2026-11-01: UTC-5 all year, with the unknown byte
	 * some devices put in front of the coordinates. 49°54'N 97°08'W */
	len = pack(rec, -300, no_rule, no_rule, 0, "Winnipeg", 1, 0x01, -49, -54, 97, 8, "");
	verify(rec, len, "Winnipeg", -300, 0, 1, -49, north, "");
	append(pf, rec, len, 0x3003);

	/* 3: Sydney, southern hemisphere, east of Greenwich. 33°52'S 151°12'E */
	len = pack(rec, 600, first_sunday_october, first_sunday_april, 1, "Sydney", 0, 0,
		   33, 52, -151, -12, "Southern hemisphere");
	verify(rec, len, "Sydney", 600, 1, 0, 33, south, "Southern hemisphere");
	append(pf, rec, len, 0x3004);

	/* 4: Kathmandu, a quarter-hour offset (+5:45). 27°43'N 85°19'E */
	len = pack(rec, 345, no_rule, no_rule, 0, "Kathmandu", 0, 0, -27, -43, -85, -19, "");
	verify(rec, len, "Kathmandu", 345, 0, 0, -27, north, "");
	append(pf, rec, len, 0x3005);

	if (pi_file_close(pf) < 0) {
		fprintf(stderr, "cannot write %s\n", argv[1]);
		return 1;
	}
	printf("wrote %s\n", argv[1]);
	return 0;
}
