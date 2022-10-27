FROM alpine:latest
RUN apk add --no-cache lua5.3 openssl3 \
	&& apk add --no-cache m4 lua5.3-dev musl-dev luarocks5.3 git gcc openssl3-dev make sudo bsd-compat-headers \
	&& for i in lunajson jnet http luafilesystem; do sudo -H luarocks-5.3 install $i; done \
	&& apk del --no-cache m4 lua5.3-dev musl-dev luarocks5.3 git gcc openssl3-dev make sudo bsd-compat-headers
WORKDIR /tptmp
ADD . .
EXPOSE 34403/tcp, 34406/tcp
ENTRYPOINT ["./server.lua"]
