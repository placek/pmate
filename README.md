# pmate

This project is a sketch for universal pair-programming tool for dockerized
projects.

![image](https://user-images.githubusercontent.com/161099/217799226-c6cf03c7-0949-4bfb-b4a0-85c60f3d94ab.png)

### Etymology

`pmate` stands for:

1. **p**air-programming **mate**;
2. **p**oor t**mate** (it is highly influenced by [tmate](https://tmate.io/));
3. **p**roject shared with your **mate**;
4. **p**rivate session with your **mate**.

### Assumptions

To start a pair programming session we need:

1. *Tools* - developers should have a bunch of tools that they are able to use
   during the pair programming session.
2. *Sandbox* - no matter who starts a session, the environment should contain
   ONLY the necessary content (configs, ENVs, etc.).  Developers should be
   allowed to do EVERYTHING they need inside the environment without worrying
   about breaking it.  If the environment breaks it should be able to be reset.
   Thus the environment should be isolated from a host environment and not
   affecting it.
3. *The project* - of course developers need to share the same project.  After
   session the changes should be applied, so any alterations made during the
   session should not be lost.  Although it should be also possible to revert
   changes afterall.
4. *Connection* - pair programming should be available for anyone using internet
   connection.  To start a session we need to use some tools that allows to work
   over the net.  The connection has to be secured from any kind of unwanted
   information leakage or exploits.  Only users choosed by the pair-programming
   session owner should be allowed to join the session.

### Implementation

To acomplish those goals we will use _ssh_ + _docker_ + _tmux_.

Docker allows to build images cointaining the required set of tools.  The images
are easily managable and can be shared on need between developers.

Every docker container provides a sandbox environment that is isolated from the
host OS.  The container can be launched and reset at will.

Many nowadays projects are already dockerized, so the idea is to extend already
existing environments by adding pair programming capabilities in some use cases.

To share the code we will apply the _volume_ to the docker container.  Volumes
are accessable form container as well as from host.  The scope of the volume
will be constrained to the project directory only, allowing no access beyond
that scope.

To access the sandbox we will use an _sshd_ service inside the container.  To
follow changes made by other programmers we will use _tmux_ sessions.

### Getting started

To start working on pair-programming session with `pmate` do the following:
1. Set the `.authorized_keys` file in your repo.
2. Prepare a docker file for pair-programming environment only.
3. Build the image and start the session container.

#### Set up authorized keys

`pmate` looks up the SSH keys of pair programming developers in a file called
`.authorized_keys` in the root directory of the project.

Each participant of pair-programming session has to be authorized.  The
authorisation is possible using the SSH public key of the participant.

The format of that file is a [simplified format](https://github.com/placek/pmate/blob/master/pmate#L84)
of [standard `authorized_keys` file](https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server)
used by SSH daemon.  It consists of public SSH keys - one line per key.  The
file does not support additional parameters like `command`.

The comment section of the SSH key entry (the string at the end of the line) is
used by `pmate` as a name of the participant.

Remember to add your key to the `.authorized_keys` file.

It's a good practice to add `.authorized_keys` to `.gitignore`.

#### Export `USER_ID` and `GROUP_ID`

Export info about your user's IDs:

    $ export USER_ID=`id -u`
    $ export GROUP_ID=`id -g`

#### Install docker

Probably you have it already.

If not, to install docker simply follow instructions on [docker site](https://docs.docker.com/get-docker/).

#### Create a dedicated docker file

In order to use `pmate` in your setup, you need to create a dedicated image for
pair programming purposes.  To acomplish that:

1.  Ensure that you have the following tools installed for the image:
  * bash
  * tmux
  * openssh
2. Add a `pmate` script to your image at `$PATH`.
3. Set the `ENTRYPOINT` to `pmate entrypoint` script on container.

An example `Dockerfile.pmate` file:

```docker
FROM alpine # FIXME: provide a base image of your choice: use here the name of the project image

RUN apk add --update --no-cache openssh tmux # FIXME: use the OS specific package system
                                             # add here the packages you need (git, vim, etc.)

EXPOSE 2222
ENTRYPOINT /usr/local/bin/pmate entrypoint

ADD https://raw.githubusercontent.com/placek/pmate/master/pmate /usr/local/bin/pmate
RUN chmod +x /usr/local/bin/pmate
```

#### Build image and start container

##### Using pure docker

In project's root directory type the following:

    $ docker build --tag pmate --file Dockerfile.pmate .

When the image is ready then type:

    $ docker run \
        --detach \
        --rm \
        --hostname "$(basename `pwd`)" \
        --name "pmate-session" \
        --publish "2222:2222" \
        --env GROUP_ID \
        --env USER_ID \
        --mount "type=bind,source=$(pwd),target=/pmate/project" \
        --mount "type=bind,source=$(pwd)/.authorized_keys,target=/pmate/keys" \
        pmate

The container called `pmate-session` is created.  It mounts the project under
`/pmate/project` path and uses `.authorized_keys` at `/pmate/keys`.  Container
can be accessed via ssh session using port `2222`.  The ENVs `USER_ID` and
`GROUP_ID` are set to prevent issue with changing permissions of the files
under volume.

To kill the session type:

    $ docker rm -f pmate-session

##### Using docker compose

Add a `pmate` service to your list, like:

```yaml
…
services:
  <main service name>: &base # The main service of the stack - the one you want to replicate and work on in the session.
                             # The `&base` term is a [YAML node anchor](https://yaml.org/spec/1.2.2/#692-node-anchors) used to remove redundancy.
    image: <base image name> # The name used in `Dockerfile.pmate`.
    …

  pmate:
    <<: *base                # Re-usage of YAML anchor. It's optional - instead you can provide full onfo about service specific setup.
    environment:
      - GROUP_ID
      - USER_ID
    image: <pmate image name>
    build:
      context: .
      dockerfile: Dockerfile.pmate
    volumes:
      - .:/pmate/project:cached
      - ./.authorized_keys:/pmate/keys
    ports:
      - "2222:2222"
…
```

To build the container type:

    $ docker-compose build pmate

Once the image is build, type:

    $ docker-compose up -d pmate

in order to bring the pmate service up.

When session is done you can stop the container with:

    $ docker-compose rm -sfv pmate

### Pair programming session

To connect to the pmate container, type:

    $ TERM=xterm-256color ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 pmate@<HOST>

The `<HOST>` parameter is the host name or IP of the machine the container is
working on.  If it's your machine then use `localhost`.

After connecting to the container, SSH deamon attaches you to the `tmux` session
called `pmate`.  In the result you can follow every move of your partner (and
they can follow as well).

###### NOTE (using external tunneling)

If you are not able to use the public IP of your mate then go for the VPN
solution or you can tunnel the SSH session via [ngrok](https://ngrok.com).

###### NOTE (known hosts problem)

Since docker containers based on the `pmate` will have different host key on
each execution (generated with `ssh-keygen` in the entrypoint) there can appear
the problem with caching those keys on every client machine.

By default hosts keys are being kept in `$HOME/.ssh/known_hosts` on docker host
and they are being appended to this file on very first connenction to host.

After the pair programming session will be launched on docker container every
client will add it's host key to `known_hosts`.  But later on container restart
the host key will differ and `ssh` will cowardly disconnect throwing a warning.
You can avoid it by removing the kept key from `$HOME/.ssh/known_hosts`.

Alternatively you can launch `ssh` in "non-checking-known-host mode", using
`StrictHostKeyChecking=no` and `UserKnownHostsFile=/dev/null` options (see
above).

### Read more

1. [`tmux` cheat-sheet](https://tmuxcheatsheet.com/)
2. [`ngrok` usage](https://ngrok.com/docs/getting-started)
3. _old article_ [Remote Pair Programming Made Easy with SSH and tmux](http://hamvocke.com/blog/remote-pair-programming-with-tmux/)

### Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md)
