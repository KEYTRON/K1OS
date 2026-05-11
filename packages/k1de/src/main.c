#define _POSIX_C_SOURCE 200112L
#include "k1de.h"
#include <getopt.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
	wlr_log_init(WLR_DEBUG, NULL);

	char *startup_cmd = NULL;
	int c;
	while ((c = getopt(argc, argv, "s:h")) != -1) {
		switch (c) {
		case 's':
			startup_cmd = optarg;
			break;
		default:
			printf("Usage: %s [-s startup command]\n", argv[0]);
			return 0;
		}
	}
	if (optind < argc) {
		printf("Usage: %s [-s startup command]\n", argv[0]);
		return 0;
	}

	wlr_log(WLR_INFO, "K1DE Desktop Environment - compositor starting...");

	struct k1de_server server;
	server_init(&server, startup_cmd);
	server_run(&server);
	server_finish(&server);

	return 0;
}
