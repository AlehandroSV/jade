.PHONY: test lint integration benchmark clean release

test:
	lua spec/run.lua

lint:
	luacheck src/

integration:
	lua spec/integration/run.lua

benchmark:
	lua bench/run.lua

clean:
	rm -rf coverage/
	rm -f *.rock

install:
	luarocks make jade-scm-1.rockspec

# Release commands
release-patch:
	@echo "Usage: make release-patch VERSION=x.y.z"
	@echo "Example: make release-patch VERSION=0.1.1"

release:
	@echo "To release a new version:"
	@echo "1. Update version in src/jade/_VERSION.lua"
	@echo "2. Update version in jade-scm-1.rockspec"
	@echo "3. git add . && git commit -m 'release: vx.y.z'"
	@echo "4. git tag vx.y.z"
	@echo "5. git push origin master --tags"
	@echo ""
	@echo "The GitHub Action will automatically publish to LuaRocks!"
