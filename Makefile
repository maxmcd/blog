


submodules:
	git submodule update --init --recursive

deploy: submodules
	./tools/deploy.sh

serve: submodules
	hugo serve
