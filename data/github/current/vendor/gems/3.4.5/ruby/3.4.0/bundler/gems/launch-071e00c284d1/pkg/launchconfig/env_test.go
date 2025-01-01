package launchconfig

import (
	"fmt"
)

func ExampleParseEnv() {
	fmt.Println(ParseEnv("production"))
	fmt.Println(ParseEnv("lab"))
	fmt.Println(ParseEnv("development"))
	fmt.Println(ParseEnv("test"))
	fmt.Println(ParseEnv("other"))
	fmt.Println(ParseEnv("labs"))
	// Output:
	// production <nil>
	// lab <nil>
	// development <nil>
	// test <nil>
	//  "other" is not a valid app environment
	//  "labs" is not a valid app environment
}
