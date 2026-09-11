.PHONY: app run debug clean measure install
app:      ## build release .app into ./build
	@scripts/build-app.sh
run: app  ## build and launch
	@open build/MatterMemory.app
debug:    ## quick debug build (no bundle; notifications disabled)
	swift build
measure:  ## memory footprint of the running app vs Electron Mattermost
	@scripts/measure.sh
clean:
	rm -rf .build build
install: app ## copy the built app into /Applications
	@rm -rf /Applications/MatterMemory.app
	@cp -R build/MatterMemory.app /Applications/
	@echo "installed /Applications/MatterMemory.app"
