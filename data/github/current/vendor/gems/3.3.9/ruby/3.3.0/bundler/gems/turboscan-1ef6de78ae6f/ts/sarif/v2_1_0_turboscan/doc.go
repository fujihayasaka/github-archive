// This package has turboscan subset of SARIF that we use in our application.
// The following go:generate comment will be used to generate the structs in the generated.go file

//go:generate schema-generate --skipValidation -p v210turboscan -o generated.go v2_1_0_turboscan.json
//go:generate easyjson ./

// Package v210turboscan provides go:generated structs for a subset of the SARIF specification used by Turboscan.
package v210turboscan
