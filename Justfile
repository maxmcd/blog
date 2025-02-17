


submodules:
	git submodule update --init --recursive

deploy: submodules
	./tools/deploy.sh

serve: submodules
	hugo serve --disableFastRender --noHTTPCache --ignoreCache --disableFastRender --bind 0.0.0.0

install_hugo:
	CGO_ENABLED=1 go install -tags extended github.com/gohugoio/hugo@v0.143.1