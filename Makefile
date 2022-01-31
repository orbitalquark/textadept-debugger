# Copyright 2007-2022 Mitchell. See LICENSE.

ta = ../..
ta_src = $(ta)/src
ta_lua = $(ta_src)/lua/src

CC = gcc
CFLAGS = -std=gnu99 -pedantic -fPIC -Wall -I$(ta_lua) -fvisibility=hidden
LDFLAGS = -Wl,--retain-symbols-file -Wl,$(ta_src)/lua.sym
luasocket_flags = -DLUASOCKET_NODEBUG -DLUA_NOCOMPAT_MODULE

all: $(addprefix lua/socket/, core.so core.dll core-curses.dll coreosx.so)
clean: ; rm -f luasocket/*.o lua/socket/*.so lua/socket/*.dll

# Platform objects.

CROSS_WIN = i686-w64-mingw32-
CROSS_OSX = x86_64-apple-darwin17-cc

luasocket_objs = $(addprefix luasocket/, luasocket.o timeout.o buffer.o io.o auxiliar.o options.o \
  inet.o usocket.o except.o select.o tcp.o udp.o)
luasocket_win_objs = $(subst usocket,wsocket, $(addsuffix -win.o, $(basename $(luasocket_objs))))
luasocket_osx_objs = $(addsuffix -osx.o, $(basename $(luasocket_objs)))

lua/socket/core.so: $(luasocket_objs)
	$(CC) -shared $(CFLAGS) -o $@ $^ $(LDFLAGS)
lua/socket/core.dll: $(luasocket_win_objs) luasocket/lua.la
	$(CROSS_WIN)$(CC) -shared -static-libgcc -static-libstdc++ $(CFLAGS) -o $@ $^ $(LDFLAGS) -lws2_32
lua/socket/core-curses.dll: $(luasocket_win_objs) luasocket/lua-curses.la
	$(CROSS_WIN)$(CC) -shared -static-libgcc -static-libstdc++ $(CFLAGS) -o $@ $^ $(LDFLAGS) -lws2_32
lua/socket/coreosx.so: $(luasocket_osx_objs)
	$(CROSS_OSX) -shared $(CFLAGS) -undefined dynamic_lookup -o $@ $^

$(luasocket_objs): %.o: %.c
	$(CC) -c $(CFLAGS) $(luasocket_flags) -DLUASOCKET_API='__attribute__((visibility("default")))' \
		$< -o $@
$(luasocket_win_objs): %-win.o: %.c
	$(CROSS_WIN)$(CC) -c $(CFLAGS) $(luasocket_flags) -DLUASOCKET_INET_PTON -DWINVER=0x0501 \
		-DLUASOCKET_API='__declspec(dllexport)' $< -o $@
$(luasocket_osx_objs): %-osx.o: %.c
	$(CROSS_OSX) -c $(CFLAGS) $(luasocket_flags) -DUNIX_HAS_SUN_LEN \
		-DLUASOCKET_API='__attribute__((visibility("default")))' $< -o $@

luasocket/lua.def:
	echo LIBRARY \"textadept.exe\" > $@ && echo EXPORTS >> $@
	grep -v "^#" $(ta_src)/lua.sym >> $@
luasocket/lua.la: luasocket/lua.def ; $(CROSS_WIN)dlltool -d $< -l $@
luasocket/lua-curses.def:
	echo LIBRARY \"textadept-curses.exe\" > $@ && echo EXPORTS >> $@
	grep -v "^#" $(ta_src)/lua.sym >> $@
luasocket/lua-curses.la: luasocket/lua-curses.def
	$(CROSS_WIN)dlltool -d $< -l $@

# Documentation.

cwd = $(shell pwd)
docs: luadoc README.md
README.md: init.lua
	cd $(ta)/scripts && luadoc --doclet markdowndoc $(cwd)/$< > $(cwd)/$@
	sed -i -e '1,+4d' -e '6c# Debugger' -e '7d' -e 's/^##/#/;' $@
luadoc: init.lua
	cd $(ta)/modules && luadoc -d $(cwd) --doclet lua/tadoc $(cwd)/$< \
		--ta-home=$(shell readlink -f $(ta))
	sed -i 's/_HOME.\+\?_HOME/_HOME/;' tags

# External dependencies.

deps: luasocket lua/mobdebug.lua

luasocket_zip = v3.0-rc1.zip
mobdebug_zip = 0.70.zip

$(luasocket_zip): ; wget https://github.com/diegonehab/luasocket/archive/$@
luasocket: | $(luasocket_zip)
	unzip -d $@ -j $| "*/src/*"
	mv luasocket/socket.lua lua
	patch -p1 < luasocket.patch
$(mobdebug_zip): ; wget https://github.com/pkulchenko/MobDebug/archive/$@
lua/mobdebug.lua: | $(mobdebug_zip) ; unzip -d $(dir $@) -j $| "*/src/$(notdir $@)"

# Releases.

ifneq (, $(shell hg summary 2>/dev/null))
  archive = hg archive -X ".hg*" $(1)
else
  archive = git archive HEAD --prefix $(1)/ | tar -xf -
endif

release: debugger | $(luasocket_zip) $(mobdebug_zip)
	cp $| $<
	make -C $< deps && make -C $< -j ta="../../.."
	zip -r $<.zip $< -x "*.zip" "$</.git*" "$</luasocket*" && rm -r $<
debugger: ; $(call archive,$@)
