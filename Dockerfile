FROM ubuntu:21.10
WORKDIR /opt/nalux
COPY . .
ENTRYPOINT ["bash", "docker_build.sh"]
