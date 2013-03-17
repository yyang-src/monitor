BINDIR=/usr/lib64

all:
	gcc -g -shared -DHAVE_DLOPEN -fPIC -I/usr/include/mysql -o libudf_arrayfunc.so udf_arrayfunc.c
	gcc -g -shared -DHAVE_DLOPEN -fPIC -I/usr/include/mysql -o libudf_constellation.so udf_constellation.c

install-dependency:
	mkdir -p $(BINDIR)

install: install-dependency
	cp -f libudf_arrayfunc.so $(BINDIR)/libudf_arrayfunc.so
	cp -f libudf_constellation.so $(BINDIR)/libudf_constellation.so

clean:
	rm -f *.so
