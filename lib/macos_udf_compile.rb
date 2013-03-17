# BINDIR=/usr/lib64
# 
# all:
#   gcc -g -shared -DHAVE_DLOPEN -fPIC -I/usr/include/mysql -o libudf_arrayfunc.so udf_arrayfunc.c
#   gcc -g -shared -DHAVE_DLOPEN -fPIC -I/usr/include/mysql -o libudf_constellation.so udf_constellation.c
# 
# install-dependency:
#   mkdir -p $(BINDIR)
# 
# install: install-dependency
#   cp -f libudf_arrayfunc.so $(BINDIR)/libudf_arrayfunc.so
#   cp -f libudf_constellation.so $(BINDIR)/libudf_constellation.so
# 
# clean:
#   rm -f *.so

LIBRARIES = ["udf_arrayfunc", "udf_constellation"]
ARCHES    = "" #"-m32 -m64 -arch i386 -arch x86_64"
# XCODEFLAGS="GCC_VERSION=com.apple.compilers.llvm.clang.1_0"

def compile
  LIBRARIES.each do |library|
    system "gcc -march=x86_64 -Wall -bundle -bundle_loader /usr/local/mysql/bin/mysqld -o #{library}.so `/usr/local/mysql/bin/mysql_config –cflags` #{library}.c"
  end
end

compile