FROM alpine:latest

RUN apk add --update --no-cache openssh tmux

EXPOSE 2222
ENTRYPOINT /usr/local/bin/pmate entrypoint

ADD pmate.sh /usr/local/bin/pmate
