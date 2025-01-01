package shared

import (
	"fmt"
	"reflect"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
)

func PrintAttributes(attributes ...*pb.Attribute) {
	for _, attr := range attributes {
		if attr.Value == nil {
			fmt.Printf("%v = [nil]\n", attr.Id)
		} else {
			unwrapped, err := attr.Value.Unwrap()
			if err != nil {
				fmt.Printf("%v = [error: %v]\n", attr.Id, err)
			}

			typ := reflect.TypeOf(unwrapped)
			if t, ok := unwrapped.(*time.Time); ok {
				// format times as human-readable strings
				unwrapped = t.Format(time.RFC3339)
			}

			fmt.Printf("%v = [%s] %v\n", attr.Id, typ.Name(), unwrapped)
		}
	}
}
