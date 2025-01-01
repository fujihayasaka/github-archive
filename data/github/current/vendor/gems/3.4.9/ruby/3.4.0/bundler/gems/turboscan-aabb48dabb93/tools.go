//go:build tools
// +build tools

// This is one approach to using private, Go-based tools in CI:
// - The import statements record the version information of the tools in go.mod
// - In CI, we can explicitly build the tools from `/vendor` without depending on the network
// - The build constraint prevents normal builds from actually importing the tools
// https://github.com/golang/go/wiki/Modules#how-can-i-track-tool-dependencies-for-a-module

package tools

import (
	_ "github.com/fatih/faillint"
	_ "github.com/github/go-json-dumper/cmd/go-json-dumper"
	_ "github.com/globusdigital/deep-copy"
	_ "github.com/mailru/easyjson/easyjson"
	_ "go.uber.org/mock/mockgen"
	_ "google.golang.org/protobuf/cmd/protoc-gen-go"

	_ "github.com/arthurnn/twirp-ruby/protoc-gen-twirp_ruby"
	_ "github.com/github/gh-kustomize/v3"
	_ "github.com/pseudomuto/protoc-gen-doc/cmd/protoc-gen-doc"
	_ "github.com/rneatherway/godeps"
	_ "github.com/simon-engledew/generate/cmd/schema-generate"
	_ "github.com/twitchtv/twirp/protoc-gen-twirp"
	_ "github.com/yoheimuta/protolint/cmd/protolint"
)
