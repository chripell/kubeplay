#!/usr/bin/env bash
set -o errexit

# Build a completely statically linked Go binary.
GOOS=linux CGO_ENABLED=0 go build -a hello.go

# Build the container my-hello.
wc=$(buildah from scratch)
buildah copy $wc hello
buildah config --cmd "/hello" $wc
buildah config --port 8080/tcp $wc
buildah commit $wc localhost/my-hello:latest
buildah rm $wc

# Push to the local registry.
buildah push --tls-verify=false localhost/my-hello:latest localhost:5000/my-hello:latest
