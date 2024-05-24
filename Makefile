


submodules:
	git submodule update --init --recursive

deploy: submodules
	./tools/deploy.sh

serve: submodules
	hugo serve --disableFastRender --noHTTPCache --ignoreCache --disableFastRender --bind 0.0.0.0
