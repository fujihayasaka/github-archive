package launchconfig

import (
	"fmt"
)

func ExampleParseMode() {
	fmt.Println(ParseMode("unknown"))
	fmt.Println(ParseMode(""))
	fmt.Println(ParseMode("hosted"))
	fmt.Println(ParseMode("enterprise"))
	// Output:
	// hosted
	// hosted
	// hosted
	// enterprise
}
