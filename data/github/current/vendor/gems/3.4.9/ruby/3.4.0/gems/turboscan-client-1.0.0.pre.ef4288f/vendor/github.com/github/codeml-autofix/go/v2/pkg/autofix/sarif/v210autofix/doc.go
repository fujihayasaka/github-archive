// This package has the autofix subset of SARIF that we use in our application.
// The following go:generate comment will be used to generate the structs in the generated.go file

//go:generate schema-generate --skipValidation -p v210autofix -o generated.go v2_1_0_autofix_schema.json
//go:generate easyjson ./

// Package v210autofix provides go:generated structs for a subset of the SARIF specification used by Turboscan.
package v210autofix
