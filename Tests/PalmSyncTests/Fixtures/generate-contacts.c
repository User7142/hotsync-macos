/*
 * generate-contacts.c: writes ContactsDB-PAdd.pdb, the golden fixture for the
 * Swift Contacts codec, with pilot-link's pack_Contact and
 * pack_ContactAppInfo (Palm OS 5 Contacts, database ContactsDB-PAdd,
 * AppInfo version 1.1 with 53 labels).
 *
 * Records: a contact with every field, one with only a last name, an empty
 * one (header only), phones with every label, three addresses, birthday with
 * and without reminder, Windows-1252 text, a picture blob and an anniversary
 * blob, and the deleted and secret attributes.
 *
 * Build against the libpisock that Scripts/build-pilot-link.sh installs:
 *
 *   P=.build/pilot-link/install
 *   clang -I$P/include -L$P/lib -lpisock -o /tmp/gen Tests/PalmSyncTests/Fixtures/generate-contacts.c
 *   DYLD_LIBRARY_PATH=$P/lib /tmp/gen Tests/PalmSyncTests/Fixtures/ContactsDB-PAdd.pdb
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "pi-contact.h"
#include "pi-dlp.h"
#include "pi-file.h"

#define FOURCC(a, b, c, d) \
	(((unsigned long)(a) << 24) | ((unsigned long)(b) << 16) | ((unsigned long)(c) << 8) | (unsigned long)(d))

/* Label list of a Palm OS 5 Contacts database (version 1.1): the entry
 * names in field order, then the extra labels the record refers to. */
static const char *labels[NUM_CONTACT_V11_LABELS] = {
	"Last name", "First name", "Company", "Title",
	"Work", "Home", "Fax", "Other", "E-mail", "Main", "Pager",
	"IM", "IM", "Website",
	"Custom 1", "Custom 2", "Custom 3", "Custom 4", "Custom 5",
	"Custom 6", "Custom 7", "Custom 8", "Custom 9",
	"Address", "City", "State", "Zip Code", "Country",
	"Address", "City", "State", "Zip Code", "Country",
	"Address", "City", "State", "Zip Code", "Country",
	"Note", "Birthday", "Mobile",
	"AIM", "MSN", "Yahoo", "ICQ", "Other",
	"Home", "Work", "Other",
	"Picture", "Anniversary", "Label 51", "Label 52"
};

static void date(struct tm *t, int year, int month, int day)
{
	memset(t, 0, sizeof(*t));
	t->tm_year = year - 1900;
	t->tm_mon = month - 1;
	t->tm_mday = day;
	t->tm_isdst = -1;
}

static void reset(struct Contact *c)
{
	memset(c, 0, sizeof(*c));
}

static void append(pi_file_t *pf, struct Contact *c, int attrs, int category, unsigned long uid)
{
	pi_buffer_t *buf = pi_buffer_new(512);

	if (pack_Contact(c, buf, contacts_v11) < 0) {
		fprintf(stderr, "pack_Contact failed\n");
		exit(1);
	}
	if (pi_file_append_record(pf, buf->data, buf->used, attrs, category, uid) < 0) {
		fprintf(stderr, "pi_file_append_record failed\n");
		exit(1);
	}
	pi_buffer_free(buf);
}

static Blob_t *blob(const char *type, const unsigned char *data, int length)
{
	Blob_t *b = malloc(sizeof(Blob_t));

	memcpy(b->type, type, 4);
	b->length = length;
	b->data = malloc(length);
	memcpy(b->data, data, length);
	return b;
}

int main(int argc, char **argv)
{
	struct DBInfo info;
	pi_file_t *pf;
	struct ContactAppInfo ai;
	struct Contact c;
	pi_buffer_t *buf;
	int i;

	if (argc != 2) {
		fprintf(stderr, "usage: %s <ContactsDB-PAdd.pdb>\n", argv[0]);
		return 2;
	}

	memset(&info, 0, sizeof(info));
	strcpy(info.name, "ContactsDB-PAdd");
	info.flags = dlpDBFlagBackup;
	info.version = 0;
	info.type = FOURCC('D', 'A', 'T', 'A');
	info.creator = FOURCC('P', 'A', 'd', 'd');
	info.createDate = info.modifyDate = 1792368000;	/* 2026-10-19T00:00:00Z */
	info.backupDate = 0;

	pf = pi_file_create(argv[1], &info);
	if (pf == NULL) {
		fprintf(stderr, "cannot create %s\n", argv[1]);
		return 1;
	}

	/* AppInfo: four categories, 53 labels, sorted by name */
	memset(&ai, 0, sizeof(ai));
	ai.type = contacts_v11;
	ai.num_labels = NUM_CONTACT_V11_LABELS;
	strcpy(ai.category.name[0], "Unfiled");
	strcpy(ai.category.name[1], "Business");
	strcpy(ai.category.name[2], "Personal");
	strcpy(ai.category.name[3], "QuickList");
	for (i = 0; i < 16; i++)
		ai.category.ID[i] = (unsigned char)i;
	ai.category.lastUniqueID = 3;
	for (i = 0; i < NUM_CONTACT_V11_LABELS; i++)
		strncpy(ai.labels[i], labels[i], 15);
	ai.country = 1;		/* Canada, as the Palm numbers them */
	ai.sortByCompany = 0;
	buf = pi_buffer_new(1200);
	if (pack_ContactAppInfo(&ai, buf) < 0) {
		fprintf(stderr, "pack_ContactAppInfo failed\n");
		return 1;
	}
	pi_file_set_app_info(pf, buf->data, buf->used);

	/* 0: every field, every phone label, three addresses, birthday with a
	 * reminder 7 days ahead, a picture blob and an anniversary blob */
	{
		static const unsigned char picture[] = { 0x00, 0x00, 0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 'J', 'F', 'I', 'F' };
		/* anniversary 2001-06-30 (packed 0xC2DE), unknown, reminder on, 3 days */
		static const unsigned char anniversary[] = { 0xc2, 0xde, 0x00, 0x01, 0x03 };

		reset(&c);
		c.entry[contLastname] = "Leto";
		c.entry[contFirstname] = "Zo\xEB";
		c.entry[contCompany] = "Lasergirl";
		c.entry[contTitle] = "Engineer";
		c.entry[contPhone1] = "+1 604 555 0101";
		c.entry[contPhone2] = "+1 604 555 0102";
		c.entry[contPhone3] = "+1 604 555 0103";
		c.entry[contPhone4] = "+1 604 555 0104";
		c.entry[contPhone5] = "zoe@example.com";
		c.entry[contPhone6] = "+1 604 555 0106";
		c.entry[contPhone7] = "+1 604 555 0107";
		c.entry[contIM1] = "zoe_aim";
		c.entry[contIM2] = "zoe_icq";
		c.entry[contWebsite] = "https://example.com";
		c.entry[contCustom1] = "c1";
		c.entry[contCustom9] = "c9";
		c.entry[contAddress1] = "1 Main St";
		c.entry[contCity1] = "Vancouver";
		c.entry[contState1] = "BC";
		c.entry[contZip1] = "V6B 1A1";
		c.entry[contCountry1] = "Canada";
		c.entry[contAddress2] = "2 Work Ave";
		c.entry[contCity2] = "Burnaby";
		c.entry[contAddress3] = "3 Other Rd";
		c.entry[contCountry3] = "Canada";
		c.entry[contNote] = "Note \x97 caf\xE9";
		c.phoneLabel[0] = 0;	/* Work */
		c.phoneLabel[1] = 1;	/* Home */
		c.phoneLabel[2] = 2;	/* Fax */
		c.phoneLabel[3] = 3;	/* Other */
		c.phoneLabel[4] = 4;	/* E-mail */
		c.phoneLabel[5] = 5;	/* Main */
		c.phoneLabel[6] = 7;	/* Mobile */
		c.showPhone = 6;
		c.addressLabel[0] = 0;	/* Home */
		c.addressLabel[1] = 1;	/* Work */
		c.addressLabel[2] = 2;	/* Other */
		c.IMLabel[0] = 0;	/* AIM */
		c.IMLabel[1] = 3;	/* ICQ */
		c.birthdayFlag = 1;
		date(&c.birthday, 1985, 3, 8);
		c.reminder = 1;
		c.advance = 7;
		c.advanceUnits = 2;	/* days */
		c.blob[0] = blob(BLOB_TYPE_PICTURE_ID, picture, sizeof(picture));
		c.blob[1] = blob(BLOB_TYPE_ANNIVERSARY_ID, anniversary, sizeof(anniversary));
		append(pf, &c, 0, 2, 0x2001);
	}

	/* 1: only a last name */
	reset(&c);
	c.entry[contLastname] = "Solo";
	append(pf, &c, 0, 0, 0x2002);

	/* 2: nothing at all (17 header bytes) */
	reset(&c);
	append(pf, &c, 0, 0, 0x2003);

	/* 3: company only, so the company offset counts no names */
	reset(&c);
	c.entry[contCompany] = "Acme";
	c.entry[contPhone1] = "+1 800 555 0199";
	c.phoneLabel[0] = 5;	/* Main */
	append(pf, &c, 0, 1, 0x2004);

	/* 4: birthday without a reminder */
	reset(&c);
	c.entry[contLastname] = "Birthday";
	c.entry[contFirstname] = "No reminder";
	c.birthdayFlag = 1;
	date(&c.birthday, 2000, 12, 31);
	append(pf, &c, 0, 2, 0x2005);

	/* 5: deleted and dirty */
	reset(&c);
	c.entry[contLastname] = "Gone";
	append(pf, &c, dlpRecAttrDeleted | dlpRecAttrDirty, 0, 0x2006);

	/* 6: secret, with a 400-character note */
	{
		char note[401];

		memset(note, 'n', 400);
		note[400] = '\0';
		reset(&c);
		c.entry[contLastname] = "Private";
		c.entry[contNote] = note;
		append(pf, &c, dlpRecAttrSecret, 3, 0x2007);
	}

	if (pi_file_close(pf) < 0) {
		fprintf(stderr, "cannot write %s\n", argv[1]);
		return 1;
	}
	printf("wrote %s\n", argv[1]);
	return 0;
}
