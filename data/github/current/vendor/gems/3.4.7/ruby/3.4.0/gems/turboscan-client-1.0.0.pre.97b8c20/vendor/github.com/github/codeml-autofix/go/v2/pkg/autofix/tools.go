//go:build tools
// +build tools

// This is one approach to using private, Go-based tools in CI:
// - The import statements record the version information of the tools in go.mod
// - In CI, we can explicitly build the tools from `/vendor` without depending on the network
// - The build constraint prevents normal builds from actually importing the tools
// https://github.com/golang/go/wiki/Modules#how-can-i-track-tool-dependencies-for-a-module

package tools

import (
	_ "github.com/mailru/easyjson/easyjson"
	_ "github.com/simon-engledew/generate/cmd/schema-generate"
)
