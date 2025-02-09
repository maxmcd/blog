


submodules:
	git submodule update --init --recursive

deploy: submodules
	./tools/deploy.sh

serve: submodules
	hugo serve --disableFastRender --noHTTPCache --ignoreCache --disableFastRender --bind 0.0.0.0

install_hugo:
	go install github.com/gohugoio/hugo@v0.143.1