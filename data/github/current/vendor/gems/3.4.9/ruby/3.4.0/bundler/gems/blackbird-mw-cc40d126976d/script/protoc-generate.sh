#! /usr/bin/env bash
#
# Intended to be run in the blackbird-proto docker container
set -euo pipefail

echo "Linting protos. See proto/buf.yaml for settings."
buf lint
# buf breaking --against '.git#branch=main'

echo ""
echo "Generating code..."
go version
protoc --version

goOut=gen/go
rubyOut=ruby/lib
mkdir -p $goOut
for pkg in query admin; do
    echo ""
    echo "Generating go and ruby clients for $pkg..."
    protos=$(find ./proto/$pkg -name '*.proto')
    protoc \
        --proto_path=./proto/ \
        --twirp_out=$goOut \
        --go_out=$goOut \
        --go_opt=Mhydro/schemas/blackbird/v0/entities/symbol_kind.proto=github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities \
        --go_opt=Mhydro/schemas/blackbird/v0/entities/epoch_mode.proto=github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities \
        --go_opt=Mhydro/schemas/blackbird/v0/entities/accessible_resources.proto=github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities \
        $protos
    protoc \
        --proto_path=./proto/ \
        --ruby_out=$rubyOut \
        --twirp_ruby_out=$rubyOut \
        $protos \
        proto/hydro/schemas/blackbird/v0/entities/symbol_kind.proto \
        proto/hydro/schemas/blackbird/v0/entities/epoch_mode.proto \
        proto/hydro/schemas/blackbird/v0/entities/accessible_resources.proto
done

# Copy to internal/ for local dependency
cp -r $goOut/* internal/proto
rm internal/proto/query/go.mod internal/proto/admin/go.mod

chown -R $UID:$GID $goOut
chmod -R g+w $goOut
chown -R $UID:$GID $rubyOut
chmod -R g+w $rubyOut

echo "Done"
