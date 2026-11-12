package proto

// monolith-twirp API definition, so that sweagentd can call the monolith
//go:generate sh -c "go run github.com/github/proto-gen-go@v1.7.0 -- --proto_path=$(pwd)/ --go_out=$(pwd) --twirp_out=$(pwd) --go_opt=paths=source_relative sweagentd/v1/*.proto"

// sweagentd API definition, so that other services can call sweagentd
//go:generate sh -c "go run github.com/github/proto-gen-go@v1.7.0 -- --proto_path=$(pwd)/ --go_out=$(pwd) --twirp_out=$(pwd) --go_opt=paths=source_relative jobs/v1/*.proto"

// Jobs API - Go client
//go:generate sh -c "cd .. && go run github.com/github/proto-gen-go@v1.7.0 -- --proto_path=$(pwd)/ --go_out=$(pwd)/pkg --twirp_out=$(pwd)/pkg proto/jobs/v1/*.proto"

// Jobs API - Ruby client
//go:generate sh -c "cd .. && go run github.com/github/proto-gen-go@v1.6.1 -- --proto_path=$(pwd) --ruby_out=$(pwd)/ruby/lib --twirp_ruby_out=$(pwd)/ruby/lib --ruby_opt=paths=source_relative proto/jobs/v1/*.proto"
