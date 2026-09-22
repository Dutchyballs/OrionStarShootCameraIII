CC ?= cc
PREFIX ?= /usr/local
LIBDIR ?= $(PREFIX)/lib/indigo
CFLAGS ?= -O2 -g
CPPFLAGS ?=
LDFLAGS ?=
WARNINGS = -Wall -Wextra -Werror
TARGET = indigo_ccd_orion.so

.PHONY: all clean install
all: $(TARGET)

$(TARGET): indigo_ccd_orion.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARNINGS) -std=gnu11 -fPIC -shared $(LDFLAGS) -o $@ $< -lindigo -lpthread -lm

install: $(TARGET)
	install -d "$(DESTDIR)$(LIBDIR)"
	install -m 755 $(TARGET) "$(DESTDIR)$(LIBDIR)/$(TARGET).new"
	mv -f "$(DESTDIR)$(LIBDIR)/$(TARGET).new" "$(DESTDIR)$(LIBDIR)/$(TARGET)"

clean:
	rm -f $(TARGET)
