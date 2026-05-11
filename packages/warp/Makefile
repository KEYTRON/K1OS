WARP_DIR ?= /home/keytron46/git/WARP

.PHONY: all clean install install-service install-volunteer uninstall

all:
	$(MAKE) -C $(WARP_DIR)

$(TARGET):
	$(MAKE) -C $(WARP_DIR) $(TARGET)

install:
	install -Dm755 $(WARP_DIR)/warp $(DESTDIR)/usr/bin/warp
	install -dm755 $(DESTDIR)/var/lib/warp
	@echo "Installed: $(DESTDIR)/usr/bin/warp"

install-service:
	@chmod +x $(INIT_DIR)/install-service.sh
	$(INIT_DIR)/install-service.sh seed

install-volunteer:
	@chmod +x $(INIT_DIR)/install-service.sh
	$(INIT_DIR)/install-service.sh volunteer

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/warp

clean:
	rm -f $(OBJS) $(TARGET)
