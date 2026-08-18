FROM ubuntu:24.04

ARG GODOT_VERSION=4.7.1-stable

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 unzip wget \
    && rm -rf /var/lib/apt/lists/* \
    && wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /opt/godot \
    && mv /opt/godot/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -rf /tmp/godot.zip /opt/godot

WORKDIR /app
COPY . /app

ENV PORT=9080
EXPOSE 9080

CMD ["godot", "--headless", "--path", "/app", "--scene", "server_main.tscn"]
