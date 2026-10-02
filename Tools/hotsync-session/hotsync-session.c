/*
 * hotsync-session: eine HotSync-Sitzung an genau einem Anschluss.
 *
 * Wozu: pilot-xfer bekommt die zu installierenden Dateien schon beim Start
 * und kann nicht erst fragen, WELCHER Palm sich gemeldet hat. HotSync
 * ordnet Dateien aber dem Palm zu (Profil = Benutzername + User-ID). Dieses
 * Werkzeug nimmt die Verbindung an, meldet die Identität des Palms und
 * wartet dann auf Anweisungen der App - so landet nie eine Datei auf dem
 * falschen Palm, auch wenn an einer Kette mehrere Palms hängen.
 *
 * Aufruf:   hotsync-session --port usb: [--timeout SEK]
 *           hotsync-session --port /dev/cu.usbserial-A1 [--timeout SEK]
 *           (Baudrate seriell über PILOTRATE, wie bei pilot-link üblich)
 *
 * stdout:   ein JSON-Objekt pro Zeile (Ereignisse, siehe emit_*)
 * stdin:    eine Anweisung pro Zeile, erst nach "connected":
 *             install <Pfad>   Datei installieren
 *             setuser <ID> <Name>  Palm ohne Benutzer übernimmt ein Profil
 *             log <Text>       Eintrag ins HotSync-Log des Palms
 *             end              Sitzung sauber beenden
 *
 * Exit:     0 Sitzung beendet, 1 Fehler, 2 kein Palm innerhalb des Timeouts
 */

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "pi-dlp.h"
#include "pi-file.h"
#include "pi-socket.h"

/* ---- JSON-Ausgabe -------------------------------------------------------- */

/* Palm OS speichert Text in Windows-1252; für JSON brauchen wir UTF-8.
 * 0x80-0x9F weichen von Latin-1 ab, diese Tabelle deckt sie ab. */
static const unsigned short cp1252_high[32] = {
	0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
	0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD,
	0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
	0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178
};

static void put_utf8(unsigned int cp)
{
	if (cp < 0x80) {
		putchar((int)cp);
	} else if (cp < 0x800) {
		putchar(0xC0 | (cp >> 6));
		putchar(0x80 | (cp & 0x3F));
	} else {
		putchar(0xE0 | (cp >> 12));
		putchar(0x80 | ((cp >> 6) & 0x3F));
		putchar(0x80 | (cp & 0x3F));
	}
}

/* Schreibt einen JSON-String. palm_text: Quelle ist Windows-1252 (vom
 * Palm), sonst UTF-8 (Pfade, Meldungen) und wird nur maskiert. */
static void put_json_string(const char *s, int palm_text)
{
	const unsigned char *p = (const unsigned char *)s;

	putchar('"');
	for (; *p; p++) {
		unsigned int c = *p;
		if (c == '"' || c == '\\') {
			putchar('\\');
			putchar((int)c);
		} else if (c < 0x20) {
			printf("\\u%04x", c);
		} else if (c >= 0x80 && palm_text) {
			put_utf8(c < 0xA0 ? cp1252_high[c - 0x80] : c);
		} else {
			putchar((int)c);
		}
	}
	putchar('"');
}

/* Alle Ereignisse gehen sofort raus: die App reagiert auf jede Zeile. */
static void emit_end(void)
{
	fputs("}\n", stdout);
	fflush(stdout);
}

static void emit_begin(const char *event)
{
	fputs("{\"event\":", stdout);
	put_json_string(event, 0);
}

static void emit_str(const char *key, const char *value, int palm_text)
{
	printf(",\"%s\":", key);
	put_json_string(value, palm_text);
}

static void emit_int(const char *key, long value)
{
	printf(",\"%s\":%ld", key, value);
}

static void emit_error(const char *stage, const char *fmt, ...)
{
	char message[256];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(message, sizeof(message), fmt, ap);
	va_end(ap);

	emit_begin("error");
	emit_str("stage", stage, 0);
	emit_str("message", message, 0);
	emit_end();
}

/* Gegenrichtung für "setuser": UTF-8 von der App nach Windows-1252 für den
 * Palm. Zeichen, die es dort nicht gibt, werden zu '?'. */
static void utf8_to_cp1252(const char *in, char *out, size_t out_size)
{
	const unsigned char *p = (const unsigned char *)in;
	size_t n = 0;

	while (*p && n + 1 < out_size) {
		unsigned int cp;
		int i;

		if (*p < 0x80) {
			cp = *p++;
		} else if ((*p & 0xE0) == 0xC0 && p[1]) {
			cp = ((p[0] & 0x1F) << 6) | (p[1] & 0x3F);
			p += 2;
		} else if ((*p & 0xF0) == 0xE0 && p[1] && p[2]) {
			cp = ((p[0] & 0x0F) << 12) | ((p[1] & 0x3F) << 6) | (p[2] & 0x3F);
			p += 3;
		} else {
			/* 4-Byte-Folgen (Emoji) und kaputte Bytes überspringen */
			p++;
			while ((*p & 0xC0) == 0x80)
				p++;
			out[n++] = '?';
			continue;
		}

		if (cp < 0x80 || (cp >= 0xA0 && cp <= 0xFF)) {
			out[n++] = (char)cp;
			continue;
		}
		for (i = 0; i < 32; i++) {
			if (cp1252_high[i] == cp && cp != 0xFFFD)
				break;
		}
		out[n++] = i < 32 ? (char)(0x80 + i) : '?';
	}
	out[n] = '\0';
}

/* ---- Installation ------------------------------------------------------- */

static const char *base_name(const char *path)
{
	const char *slash = strrchr(path, '/');
	return slash ? slash + 1 : path;
}

/* Fortschritt je übertragenem Datensatz - die App zeigt damit, dass die
 * Übertragung lebt, und kann einen Hänger von einer großen Datei
 * unterscheiden. */
static int install_progress(int sd, pi_progress_t *progress)
{
	(void)sd;
	emit_begin("progress");
	emit_int("bytes", (long)progress->transferred_bytes);
	emit_end();
	return PI_TRANSFER_CONTINUE;
}

/* Installiert eine Datei und meldet "installed" oder "failed". Die Gründe
 * kommen als Rohcodes; die Zuordnung zu Texten macht die App (HotSyncCore),
 * damit es dafür genau eine Stelle gibt. */
static void install_file(int sd, const char *path)
{
	const char *name = base_name(path);
	struct stat sbuf;
	struct CardInfo card;
	unsigned long ram_free = 0;
	pi_file_t *pf;

	emit_begin("installing");
	emit_str("file", name, 0);
	emit_end();

	if (stat(path, &sbuf) != 0 || (pf = pi_file_open(path)) == NULL) {
		emit_begin("failed");
		emit_str("file", name, 0);
		emit_str("reason", "unreadableFile", 0);
		emit_end();
		return;
	}

	/* Freien Speicher aller Karten summieren wie pilot-xfer: lieber vorher
	 * ablehnen als mitten in der Übertragung abbrechen. */
	card.card = -1;
	card.more = 1;
	while (card.more) {
		if (dlp_ReadStorageInfo(sd, card.card + 1, &card) < 0)
			break;
		ram_free += card.ramFree;
	}
	if (ram_free > 0 && (unsigned long)sbuf.st_size > ram_free) {
		emit_begin("failed");
		emit_str("file", name, 0);
		emit_str("reason", "notEnoughSpace", 0);
		emit_int("needed", (long)sbuf.st_size);
		emit_int("available", (long)ram_free);
		emit_end();
		pi_file_close(pf);
		return;
	}

	if (pi_file_install(pf, sd, 0, install_progress) < 0) {
		emit_begin("failed");
		emit_str("file", name, 0);
		emit_str("reason", "palmError", 0);
		emit_int("error", pi_error(sd));
		emit_int("palmOSError", pi_palmos_error(sd));
		emit_end();
	} else {
		emit_begin("installed");
		emit_str("file", name, 0);
		emit_int("bytes", (long)sbuf.st_size);
		emit_end();
	}
	pi_file_close(pf);
}

/* ---- Sitzung ------------------------------------------------------------ */

static int connect_palm(const char *port, int timeout)
{
	int listen_sd, sd;

	listen_sd = pi_socket(PI_AF_PILOT, PI_SOCK_STREAM, PI_PF_DLP);
	if (listen_sd < 0) {
		emit_error("socket", "unable to create socket");
		return -1;
	}
	if (pi_bind(listen_sd, port) < 0) {
		emit_error("bind", "unable to bind to %s", port);
		pi_close(listen_sd);
		return -1;
	}
	if (pi_listen(listen_sd, 1) < 0) {
		emit_error("listen", "unable to listen on %s", port);
		pi_close(listen_sd);
		return -1;
	}

	emit_begin("listening");
	emit_str("port", port, 0);
	emit_end();

	/* Kein Palm innerhalb des Timeouts meldet libpisock je Anschluss anders:
	 * - USB: u_wait_for_device liefert 0, pi_usb_accept reicht das durch -
	 *   pi_accept_to gibt 0 zurück (nie ein gültiger Socket, das ist stdin)
	 *   und lässt den Listener offen.
	 * - seriell: PI_ERR_SOCK_TIMEOUT; bei negativen Werten hat pi_accept_to
	 *   den Listener schon selbst geschlossen. */
	sd = pi_accept_to(listen_sd, NULL, NULL, timeout);
	if (sd == 0) {
		pi_close(listen_sd);
		emit_begin("timeout");
		emit_end();
		return -2;
	}
	if (sd == PI_ERR_SOCK_TIMEOUT) {
		emit_begin("timeout");
		emit_end();
		return -2;
	}
	if (sd < 0) {
		emit_error("accept", "error accepting data on %s (%d)", port, sd);
		return -1;
	}
	return sd;
}

/* Der beim Verbinden gelesene Benutzer: "setuser" ändert nur Name und ID
 * und schreibt die übrigen Felder unverändert zurück. */
static struct PilotUser palm_user;

static int report_identity(int sd)
{
	struct SysInfo sys;
	struct PilotUser user;

	if (dlp_ReadSysInfo(sd, &sys) < 0) {
		emit_error("sysinfo", "unable to read system info");
		return -1;
	}
	if (dlp_ReadUserInfo(sd, &user) < 0) {
		emit_error("userinfo", "unable to read user info");
		return -1;
	}

	palm_user = user;

	emit_begin("connected");
	emit_str("user", user.username, 1);
	emit_int("userId", (long)user.userID);
	emit_int("romVersion", (long)sys.romVersion);
	emit_end();
	return 0;
}

/* Gibt einem Palm ohne Benutzer die Identität seines Profils:
 * "setuser <ID> <Name>". Danach erkennt HotSync ihn an der ID wieder. */
static void write_user(int sd, const char *args)
{
	char *end;
	unsigned long id = strtoul(args, &end, 10);
	struct PilotUser user = palm_user;

	if (end == args || *end != ' ' || id == 0) {
		emit_error("setuser", "usage: setuser <ID> <name>");
		return;
	}
	utf8_to_cp1252(end + 1, user.username, sizeof(user.username));
	user.userID = id;
	user.viewerID = 0;
	user.lastSyncPC = 0;

	if (dlp_WriteUserInfo(sd, &user) < 0) {
		emit_error("setuser", "unable to write user info (%d, PalmOS 0x%04x)",
			pi_error(sd), pi_palmos_error(sd));
		return;
	}
	palm_user = user;

	emit_begin("userWritten");
	emit_str("user", user.username, 1);
	emit_int("userId", (long)user.userID);
	emit_end();
}

/* Liest Anweisungen bis "end" oder EOF. Bei EOF (App weg) wird die
 * Sitzung trotzdem sauber beendet, damit der Palm nicht hängen bleibt. */
static void run_commands(int sd)
{
	char line[4096];

	while (fgets(line, sizeof(line), stdin) != NULL) {
		line[strcspn(line, "\r\n")] = '\0';

		if (strncmp(line, "install ", 8) == 0) {
			install_file(sd, line + 8);
		} else if (strncmp(line, "setuser ", 8) == 0) {
			write_user(sd, line + 8);
		} else if (strncmp(line, "log ", 4) == 0) {
			char entry[1024];
			utf8_to_cp1252(line + 4, entry, sizeof(entry));
			/* Der Palm zeigt jeden Eintrag als eigene Zeile im HotSync-Log */
			strncat(entry, "\n", sizeof(entry) - strlen(entry) - 1);
			dlp_AddSyncLogEntry(sd, entry);
		} else if (strcmp(line, "end") == 0) {
			break;
		} else if (line[0] != '\0') {
			emit_error("command", "unknown command: %s", line);
		}
	}
}

int main(int argc, char **argv)
{
	const char *port = NULL;
	int timeout = 0;
	int sd, i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--port") == 0 && i + 1 < argc)
			port = argv[++i];
		else if (strcmp(argv[i], "--timeout") == 0 && i + 1 < argc)
			timeout = atoi(argv[++i]);
		else {
			fprintf(stderr, "usage: %s --port PORT [--timeout SECONDS]\n", argv[0]);
			return 1;
		}
	}
	if (port == NULL) {
		fprintf(stderr, "usage: %s --port PORT [--timeout SECONDS]\n", argv[0]);
		return 1;
	}

	sd = connect_palm(port, timeout);
	if (sd == -2)
		return 2;
	if (sd < 0)
		return 1;

	if (report_identity(sd) < 0) {
		pi_close(sd);
		return 1;
	}

	if (dlp_OpenConduit(sd) < 0) {
		emit_error("conduit", "cancelled on the Palm");
		pi_close(sd);
		return 1;
	}

	run_commands(sd);

	dlp_EndOfSync(sd, dlpEndCodeNormal);
	pi_close(sd);

	emit_begin("finished");
	emit_end();
	return 0;
}
