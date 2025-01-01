//go:build tools

//go:generate protoc -I proto -I monolith-twirp-proto/turboghas/v1 --proto_path=. --twirp_ruby_out=ruby/lib --ruby_out=ruby/lib --twirp_out=proto --go_out=proto proto/turboghas.proto
//go:generate protoc --proto_path=monolith-twirp-proto --twirp_opt=paths=source_relative --go_opt=paths=source_relative  --twirp_out=internal/monolith_twirp --go_out=internal/monolith_twirp monolith-twirp-proto/turboghas/v1/turboghas.proto monolith-twirp-proto/turboghas/v1/entity_type.proto

package tools

import (
	_ "github.com/arthurnn/twirp-ruby/protoc-gen-twirp_ruby"
	_ "github.com/github/gh-kustomize/v3"
	_ "github.com/github/go-upgrades/cmd/create-transition"
	_ "github.com/simon-engledew/check-go-version"
	_ "github.com/twitchtv/twirp/protoc-gen-twirp"
	_ "google.golang.org/protobuf/cmd/protoc-gen-go"
)
