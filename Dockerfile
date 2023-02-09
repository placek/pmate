FROM alpine:latest

RUN apk add --update --no-cache openssh tmux bash

EXPOSE 2222
ENTRYPOINT /usr/local/bin/pmate entrypoint

ADD https://raw.githubusercontent.com/placek/pmate/master/pmate /usr/local/bin/pmate
