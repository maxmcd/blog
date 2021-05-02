


submodules:
	git submodule update --init --recursive

deploy: submodules
	./tools/deploy.sh

serve: submodules
	hugo serve --bind 0.0.0.0 --baseURL "/" --appendPort=false
