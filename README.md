# `pmate`

This project is a sketch for universal pair-programming tool for dockerized projects.

### Etymology

`pmate` stands for:

1. **p**air-programming **mate**, or
2. **p**oor t**mate** (it is highly influenced by [tmate](https://tmate.io/)), or
3. **p**roject shared with your **mate**, or
4. **p**rivate session with your **mate**.

### Assumptions

To start a pair programming session we need:

1. *Tools* - developers should have a bunch of tools that they are able to use during the pair programming session.
2. *Sandbox* - no matter who starts a session, the environment should contain ONLY the necessary content (tools, files, etc.). Developers should be allowed to do EVERYTHING they need inside the environment without worrying about breaking it. If the environment breaks it should be able to be reset. The environment should be isolated from a host environment and not affecting it.
3. *The project* - of course developers need to share the same project. After session the changes should be applied, so any alterations made during the session should not be lost. Although it should be also possible to revert changes afterall.
4. *Connection* - pair programming should be available for anyone using internet connection. To start a session we need to use some tools that allows to work over the net. The connection has to be secured from any kind of unwanted information leakage or exploits.

### Implementation

To acomplish those goals we will use _ssh_ + _docker_ + _tmux_.

Docker allows to build images cointaining the required set of tools. The images are easily managable and can be shared on need between developers.

Every docker container provides a sandbox environment that is isolated from the host OS. The container can be launched and reset at will.

Many nowadays projects are already dockerized, so the idea is to extend already existing environments by adding pair programming capabilities in some use cases.

To share the code we will apply the _volume_ to the docker container. Volumes are accessable form container as well as from host. The scope of the volume will be constrained to the project directory only, allowing no access beyond that scope.

To access the sandbox we will use an _sshd_ service inside the container. To follow changes made by other programmers we will use _tmux_ sessions.

### Getting started

#### Install docker

To install docker simply follow instructions on [docker site](https://docs.docker.com/get-docker/).

Probably you have it already.

#### Adjust the docker image of your project

In order to use `pmate` in your setup, you need to:

1.  Ensure that you have the following tools installed for the image:
  *. openssh
  *. busybox
  *. getent
  *. tmux

2. Add a `pmate.sh` script to your image at `$PATH`, like:

```docker
ADD <path_to_pmate.sh> /usr/local/bin/pmate
```

3. Set entrypoint to pmate:

```docker
ENTRYPOINT /usr/local/bin/pmate
```

4. Tell docker to expose the ssh entry port:

```docker
EXPOSE 2222
```

An example (minimal) dockerfile:

```docker
FROM alpine:latest

RUN apk add --update --no-cache openssh tmux

EXPOSE 2222
ENTRYPOINT /usr/local/bin/pmate entrypoint

ADD bin/pmate.sh /usr/local/bin/pmate
```

#### Using docker compose

When using `docker-compose` you can avoid some changes in `Dockerfile` and introduce them in docker compose configuration.

For instance setting up an entrypoint can be done by providing custom `volume` and `entrypoint` options, like:

```yaml
...
services:
  my-awesome-project:
    volumes:
      - ./bin/pmate.sh:/usr/local/bin/pmate
      ...
    entrypoint: pmate
    ports:
      - 2222:2222
...
```

### Pair programming session

#### Create a new branch in repo

Before you start session, set up the repository:

    $ cd <project_path>
    $ git checkout -B pair/with_placek

###### NOTE:
This point is optional, but it will keep the main branches clean and every change made during the session managable at will.

#### Set up authorized keys

`pmate` looks up the SSH keys of pair programming developers in a file called `.authorized_keys` in the root of the project. The format of that file is a [simplified format of standard `authorized_keys` file](https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server) used by SSH daemon. It consists of public SSH keys - one line per key. The file does not support additional parameters like `command`.

Remember to add your key to the `.authorized_keys` file.

It's a good practice to add `.authorized_keys` line to `.gitignore`.

#### Start a session

To start a session, simply run the `pmate` script with `start` parameter in the root of the project directory, like:

```
$ <path_to_pmate.sh> start <your_projects_docker_image_with_pmate_entrypoint>
```

`pmate` script sets up the container name, volumes, necessary environment variables and ports.

The container name is in format `pmate-<name_of_projects_root_directory>` and can be futher manipulated with docker commands.

#### Attach to the container

Now you can use the `pair` user on the container. To attach to the container simply use `ssh`:

```
$ ssh -p 2222 pair@localhost
```

The pair-programming partner should be able to connect to the container with:

```
$ ssh -p <port> pair@<your_ip>
```

After connecting to the container, SSH deamon attaches you to the `tmux` session called `pmate`. In the result you can follow every move of your partner (and they can too).

Escaping from `tmux` session ends the `ssh` session.

###### NOTE (using external tunneling)

If you are not able to use the VPN you can tunnel the SSH session via [ngrok](https://ngrok.com).

###### NOTE (known hosts problem)

Since docker containers based on the `pmate` will have different host key on each execution (generated with `ssh-keygen` in the entrypoint) there can appear the problem with caching those keys on every client machine.

By default hosts keys are being kept in `$HOME/.ssh/known_hosts` on docker host and they are being appended to this file on very first connenction to host.

After the pair programming session will be launched on docker container every client will add it's host key to `known_hosts`. But later on container restart the host key will differ and `ssh` will cowardly disconnect throwing a warning. You can avoid it by removing the kept key from `$HOME/.ssh/known_hosts`.

Alternatively you can launch `ssh` in "non-checking-known-host mode", using:

```
$ ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p <port> pair@<your_ip>
```

In the end it's recommended to use `pmate`'s `connect` command:

```
$ <path_to_pmate.sh> connect <your_ip>
```

#### Stoping session

To end session use `pmate`'s `stop` command:

```
$ <path_to_pmate.sh> stop
```

After that the pair-programming partner has no access to the code.

### Read more

1. [`tmux` cheat-sheet](https://tmuxcheatsheet.com/)
2. [`ngrok` usage](https://ngrok.com/docs/getting-started)
3. _old article_ [Remote Pair Programming Made Easy with SSH and tmux](http://hamvocke.com/blog/remote-pair-programming-with-tmux/)
