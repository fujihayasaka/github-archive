package jobs

//go:generate sh -c "go run github.com/github/proto-gen-go@v1.7.0 -- --proto_path=$(pwd) --go_out=$(pwd) --go_opt=paths=source_relative agent_job.proto api_job.proto event_job.proto"
