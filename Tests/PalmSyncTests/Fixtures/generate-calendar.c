/*
 * generate-calendar.c: writes CalendarDB-PDat.pdb, the golden fixture for the
 * Swift Calendar codec, with pilot-link's own pack_CalendarEvent and
 * pack_CalendarAppInfo (Palm OS 5 Calendar, database CalendarDB-PDat).
 *
 * Every record kind the codec has to round-trip byte for byte: timeless and
 * timed events, alarms, all five repeat types, exceptions, note and location,
 * Windows-1252 text, a time zone blob, an unknown blob, and the record
 * attributes (deleted, dirty, secret).
 *
 * Build against the libpisock that Scripts/build-pilot-link.sh installs:
 *
 *   P=.build/pilot-link/install
 *   clang -I$P/include -L$P/lib -lpisock -o /tmp/gen Tests/PalmSyncTests/Fixtures/generate-calendar.c
 *   DYLD_LIBRARY_PATH=$P/lib /tmp/gen Tests/PalmSyncTests/Fixtures/CalendarDB-PDat.pdb
 *
 * The time zone blob is built by hand: pilot-link's pack_Timezone writes the
 * dstObserved and t4 bytes to the same offset (location.c), so its output does
 * not match what the Palm writes. The layout below is the one unpack_Timezone
 * reads, which was taken from real devices.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "pi-calendar.h"
#include "pi-dlp.h"
#include "pi-file.h"

#define FOURCC(a, b, c, d) \
	(((unsigned long)(a) << 24) | ((unsigned long)(b) << 16) | ((unsigned long)(c) << 8) | (unsigned long)(d))

static void date(struct tm *t, int year, int month, int day, int hour, int min)
{
	memset(t, 0, sizeof(*t));
	t->tm_year = year - 1900;
	t->tm_mon = month - 1;
	t->tm_mday = day;
	t->tm_hour = hour;
	t->tm_min = min;
	t->tm_isdst = -1;
}

static void reset(CalendarEvent_t *e)
{
	memset(e, 0, sizeof(*e));
	e->repeatForever = 1;
}

static void append(pi_file_t *pf, CalendarEvent_t *e, int attrs, int category, unsigned long uid)
{
	pi_buffer_t *buf = pi_buffer_new(256);

	if (pack_CalendarEvent(e, buf, calendar_v1) < 0) {
		fprintf(stderr, "pack_CalendarEvent failed for %s\n", e->description ? e->description : "?");
		exit(1);
	}
	if (pi_file_append_record(pf, buf->data, buf->used, attrs, category, uid) < 0) {
		fprintf(stderr, "pi_file_append_record failed\n");
		exit(1);
	}
	pi_buffer_free(buf);
}

/* A Bd00 blob as the Palm writes it: offset (minutes, int16), t2, DST start
 * rule (weekday, week, month, unknown), DST end rule, observed (0x3c or 0),
 * t4, unknown (0x80 or 0), name NUL-terminated. */
static Blob_t *timezone_blob(int offset, const unsigned char start[4], const unsigned char end[4],
			     int observed, const char *name)
{
	Blob_t *blob = malloc(sizeof(Blob_t));
	unsigned char *p;

	blob->length = 2 + 1 + 4 + 4 + 3 + (int)strlen(name) + 1;
	blob->data = p = malloc(blob->length);
	memcpy(blob->type, BLOB_TYPE_CALENDAR_TIMEZONE_ID, 4);
	p[0] = (unsigned char)((offset >> 8) & 0xff);
	p[1] = (unsigned char)(offset & 0xff);
	p[2] = 0;
	memcpy(p + 3, start, 4);
	memcpy(p + 7, end, 4);
	p[11] = observed ? 0x3c : 0x00;
	p[12] = 0;
	p[13] = 0x80;
	strcpy((char *)p + 14, name);
	return blob;
}

int main(int argc, char **argv)
{
	struct DBInfo info;
	pi_file_t *pf;
	CalendarAppInfo_t ai;
	CalendarEvent_t e;
	pi_buffer_t *buf;
	int i;

	if (argc != 2) {
		fprintf(stderr, "usage: %s <CalendarDB-PDat.pdb>\n", argv[0]);
		return 2;
	}

	memset(&info, 0, sizeof(info));
	strcpy(info.name, "CalendarDB-PDat");
	info.flags = dlpDBFlagBackup;
	info.version = 0;
	info.type = FOURCC('D', 'A', 'T', 'A');
	info.creator = FOURCC('P', 'D', 'a', 't');
	info.createDate = info.modifyDate = 1792368000;	/* 2026-10-19T00:00:00Z */
	info.backupDate = 0;

	pf = pi_file_create(argv[1], &info);
	if (pf == NULL) {
		fprintf(stderr, "cannot create %s\n", argv[1]);
		return 1;
	}

	/* AppInfo: four categories, week starts on Sunday */
	memset(&ai, 0, sizeof(ai));
	ai.type = calendar_v1;
	strcpy(ai.category.name[0], "Unfiled");
	strcpy(ai.category.name[1], "Work");
	strcpy(ai.category.name[2], "Family");
	strcpy(ai.category.name[3], "G Work");
	for (i = 0; i < 16; i++)
		ai.category.ID[i] = (unsigned char)i;
	ai.category.lastUniqueID = 3;
	ai.startOfWeek = 0;
	buf = pi_buffer_new(300);
	if (pack_CalendarAppInfo(&ai, buf) == 0) {
		fprintf(stderr, "pack_CalendarAppInfo failed\n");
		return 1;
	}
	pi_file_set_app_info(pf, buf->data, buf->used);
	/* the file takes ownership of the data, not the pi_buffer_t */

	/* 0: plain timed event */
	reset(&e);
	date(&e.begin, 2026, 10, 20, 9, 0);
	date(&e.end, 2026, 10, 20, 10, 0);
	e.description = "Standup";
	append(pf, &e, 0, 1, 0x1001);

	/* 1: timeless event with a note */
	reset(&e);
	e.event = 1;
	date(&e.begin, 2026, 11, 1, 0, 0);
	e.end = e.begin;
	e.description = "Clocks stay";
	e.note = "No fall back in BC";
	append(pf, &e, 0, 0, 0x1002);

	/* 2: alarm 15 minutes before, with a location */
	reset(&e);
	date(&e.begin, 2026, 10, 21, 14, 30);
	date(&e.end, 2026, 10, 21, 15, 0);
	e.alarm = 1;
	e.advance = 15;
	e.advanceUnits = calendar_advMinutes;
	e.description = "Dentist";
	e.location = "Downtown";
	append(pf, &e, 0, 2, 0x1003);

	/* 3: daily, forever */
	reset(&e);
	date(&e.begin, 2026, 10, 1, 8, 0);
	date(&e.end, 2026, 10, 1, 8, 15);
	e.repeatType = calendarRepeatDaily;
	e.repeatFrequency = 1;
	e.description = "Meds";
	append(pf, &e, 0, 0, 0x1004);

	/* 4: weekly Mon/Wed/Fri until 2027-03-31, two exceptions */
	reset(&e);
	date(&e.begin, 2026, 10, 19, 18, 0);
	date(&e.end, 2026, 10, 19, 19, 0);
	e.repeatType = calendarRepeatWeekly;
	e.repeatForever = 0;
	date(&e.repeatEnd, 2027, 3, 31, 0, 0);
	e.repeatFrequency = 1;
	e.repeatDays[1] = e.repeatDays[3] = e.repeatDays[5] = 1;
	e.repeatWeekstart = 0;
	e.exceptions = 2;
	e.exception = calloc(2, sizeof(struct tm));
	date(&e.exception[0], 2026, 10, 23, 0, 0);
	date(&e.exception[1], 2026, 10, 28, 0, 0);
	e.description = "Gym";
	append(pf, &e, 0, 2, 0x1005);
	free(e.exception);

	/* 5: monthly by day, second Tuesday, forever */
	reset(&e);
	date(&e.begin, 2026, 10, 13, 19, 0);
	date(&e.end, 2026, 10, 13, 21, 0);
	e.repeatType = calendarRepeatMonthlyByDay;
	e.repeatFrequency = 1;
	e.repeatDay = calendar_2ndTue;
	e.description = "Board";
	append(pf, &e, 0, 1, 0x1006);

	/* 6: monthly by date, every second month on the 15th, until 2027-12-15 */
	reset(&e);
	e.event = 1;
	date(&e.begin, 2026, 10, 15, 0, 0);
	e.end = e.begin;
	e.repeatType = calendarRepeatMonthlyByDate;
	e.repeatForever = 0;
	date(&e.repeatEnd, 2027, 12, 15, 0, 0);
	e.repeatFrequency = 2;
	e.description = "Rent";
	append(pf, &e, 0, 0, 0x1007);

	/* 7: yearly, alarm one day before, Windows-1252 text:
	 * "Zoë" (0xEB), an em dash (0x97) and a euro sign (0x80) */
	reset(&e);
	e.event = 1;
	date(&e.begin, 2026, 5, 4, 0, 0);
	e.end = e.begin;
	e.repeatType = calendarRepeatYearly;
	e.repeatFrequency = 1;
	e.alarm = 1;
	e.advance = 1;
	e.advanceUnits = calendar_advDays;
	e.description = "Zo\xEB's birthday";
	e.note = "Cake \x97 budget 20 \x80";
	append(pf, &e, 0, 2, 0x1008);

	/* 8: timed event with a Toronto time zone blob (Eastern, DST second
	 * Sunday of March to first Sunday of November) and an unknown Bd01 blob */
	{
		static const unsigned char start[4] = { 0x00, 0x01, 0x03, 0x00 };
		static const unsigned char end[4] = { 0x00, 0x00, 0x0b, 0x00 };
		Blob_t *other = malloc(sizeof(Blob_t));

		reset(&e);
		date(&e.begin, 2026, 11, 5, 11, 0);
		date(&e.end, 2026, 11, 5, 12, 0);
		e.description = "Toronto call";
		e.blob[0] = timezone_blob(-300, start, end, 1, "Toronto");
		memcpy(other->type, BLOB_TYPE_CALENDAR_UNKNOWN_ID, 4);
		other->length = 3;
		other->data = (uint8_t *)"\x01\x02\x03";
		e.blob[1] = other;
		append(pf, &e, 0, 1, 0x1009);
	}

	/* 9: deleted and dirty (what a fast sync sees after a delete on the Palm) */
	reset(&e);
	date(&e.begin, 2026, 10, 22, 12, 0);
	date(&e.end, 2026, 10, 22, 13, 0);
	e.description = "Gone";
	append(pf, &e, dlpRecAttrDeleted | dlpRecAttrDirty, 0, 0x100a);

	/* 10: secret (private) record */
	reset(&e);
	date(&e.begin, 2026, 10, 22, 16, 0);
	date(&e.end, 2026, 10, 22, 16, 30);
	e.description = "Private";
	append(pf, &e, dlpRecAttrSecret, 0, 0x100b);

	/* 11: category 3. (There is no archived bit in a .pdb: dlpRecAttrArchived
	 * is 0x08, which is part of the category nibble in the file; archived
	 * records only exist on the wire during a sync.) */
	reset(&e);
	e.event = 1;
	date(&e.begin, 2025, 1, 1, 0, 0);
	e.end = e.begin;
	e.description = "Old";
	append(pf, &e, 0, 3, 0x100c);

	/* 12: empty description and a 300-byte note */
	{
		char note[301];

		memset(note, 'n', 300);
		note[300] = '\0';
		reset(&e);
		date(&e.begin, 2026, 12, 24, 23, 0);
		date(&e.end, 2026, 12, 25, 0, 0);
		e.description = "";
		e.note = note;
		append(pf, &e, 0, 0, 0x100d);
	}

	if (pi_file_close(pf) < 0) {
		fprintf(stderr, "cannot write %s\n", argv[1]);
		return 1;
	}
	printf("wrote %s\n", argv[1]);
	return 0;
}
