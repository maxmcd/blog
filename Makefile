


deploy:
	./tools/deploy.sh


submodules:
	git submodule update --init --recursive

serve: submodules
	hugo serve
