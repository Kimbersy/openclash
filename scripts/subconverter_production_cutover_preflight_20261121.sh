#!/bin/sh
# Read-only, secret-safe pre-cutover snapshot for known iStoreOS subconverter deployment.
# Do not print environment values, private subscription URLs, or Docker auth settings.
set -eu

OLD='nostalgic_pasteur'
NEW='asdlokj1qpi23/subconverter:0.9.9'
command -v docker >/dev/null 2>&1 || { echo 'HOLD: docker missing'; exit 1; }
command -v sed >/dev/null 2>&1 || { echo 'HOLD: sed missing'; exit 1; }

docker inspect -f 'OLD_RUNNING={{.State.Running}} OLD_IMAGE={{.Image}} NETWORK={{.HostConfig.NetworkMode}} RESTART={{.HostConfig.RestartPolicy.Name}} PORT_BINDINGS={{json .HostConfig.PortBindings}} MOUNTS={{len .Mounts}} PRIVILEGED={{.HostConfig.Privileged}} READONLY_ROOTFS={{.HostConfig.ReadonlyRootfs}} HOST_BIND_COUNT={{len .HostConfig.Binds}} DEVICE_COUNT={{len .HostConfig.Devices}}' "$OLD" || exit 1
docker inspect -f 'OLD_ENTRYPOINT={{json .Config.Entrypoint}} OLD_CMD={{json .Config.Cmd}} OLD_USER={{.Config.User}} OLD_WORKDIR={{.Config.WorkingDir}} OLD_EXPOSED_PORTS={{json .Config.ExposedPorts}}' "$OLD" || exit 1

echo '=== Old container environment variable NAMES ONLY (no values) ==='
docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$OLD" | sed 's/=.*//' || exit 1

docker image inspect -f 'NEW_IMAGE={{.Id}} NEW_PLATFORM={{.Os}}/{{.Architecture}}' "$NEW" || exit 1
echo 'PREFLIGHT_RESULT=READ_ONLY_METADATA_COLLECTED_NO_PRODUCTION_CHANGE'
