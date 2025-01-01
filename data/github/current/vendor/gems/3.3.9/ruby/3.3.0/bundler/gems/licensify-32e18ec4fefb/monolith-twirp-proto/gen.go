// Package proto is used for code generation.
package proto

//go:generate sh -c "cd .. && go run github.com/github/proto-gen-go@v1.5.0 -- --proto_path=$(pwd)/monolith-twirp-proto --go_out=$(pwd)/lib/monolith-twirp --twirp_out=$(pwd)/lib/monolith-twirp $(pwd)/monolith-twirp-proto/customers/v1/*.proto"
//go:generate sh -c "cd .. && go run github.com/github/proto-gen-go@v1.5.0 -- --proto_path=$(pwd)/monolith-twirp-proto --go_out=$(pwd)/lib/monolith-twirp --twirp_out=$(pwd)/lib/monolith-twirp $(pwd)/monolith-twirp-proto/repositories/v1/*.proto"
