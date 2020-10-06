# Copyright 2007-2020 Mitchell. See LICENSE.

# Documentation.

ta = ../..
cwd = $(shell pwd)
docs: luadoc README.md
README.md: init.lua
	cd $(ta)/scripts && luadoc --doclet markdowndoc $(cwd)/$< > $(cwd)/$@
	sed -i -e '1,+4d' -e '6c# Debugger' -e '7d' -e 's/^##/#/;' $@
luadoc: init.lua
	cd $(ta)/modules && luadoc -d $(cwd) --doclet lua/tadoc $(cwd)/$< \
		--ta-home=$(shell readlink -f $(ta))
	sed -i 's/_HOME.\+\?_HOME/_HOME/;' tags

# External MobDebug dependency.

deps: lua/mobdebug.lua

mobdebug_zip = 0.70.zip
$(mobdebug_zip): ; wget https://github.com/pkulchenko/MobDebug/archive/$@
lua/mobdebug.lua: | $(mobdebug_zip)
	unzip -d $(dir $@) -j $| "*/src/$(notdir $@)"

