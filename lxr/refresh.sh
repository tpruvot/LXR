if [ -z $* ]; then
	./genxref --help
else
	./genxref --url=http://localhost:888/lxr $*
fi

