package aqueduct_api_v1

//go:generate sh -c "cd .. && go run github.com/github/proto-gen-go@v1.4.0 -- --proto_path=$(pwd) --go_out=$(pwd) --twirp_out=$(pwd) --go_opt=paths=source_relative --go_opt=Mproto/api.proto=github.com/github/aqueduct-client-go/aqueduct_api_v1 proto/api.proto"
