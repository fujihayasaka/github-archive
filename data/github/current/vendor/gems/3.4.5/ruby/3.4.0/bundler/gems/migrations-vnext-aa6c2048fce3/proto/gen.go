// Package proto is a shim for generating the protobuf files.
package proto

//go:generate sh -c "cd .. && go run github.com/github/proto-gen-go@v1.7.0 -- --proto_path=$(pwd)/proto --proto_path=$(pwd)/internal/proto/octoshift --go_out=$(pwd)/pkg --twirp_out=$(pwd)/pkg --go_opt=paths=source_relative --twirp_opt=paths=source_relative mvnd/v1/migrations.proto mvnd/v1/resources.proto mvnd/v1/events.proto mvnd/v1/context.proto"
