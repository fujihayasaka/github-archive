// Package proto is used for code generation.
package proto

//go:generate sh -c "cd .. && go run github.com/github/proto-gen-go@v1.5.0 -- --proto_path=$(pwd)/proto --go_out=$(pwd) --twirp_out=$(pwd) --ruby_out=$(pwd)/ruby/lib --twirp_ruby_out=$(pwd)/ruby/lib $(pwd)/proto/licensify/services/v1/*.proto"
