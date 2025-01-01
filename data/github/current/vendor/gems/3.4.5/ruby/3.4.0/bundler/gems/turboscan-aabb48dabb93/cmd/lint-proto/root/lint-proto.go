// Package root contains the main logic for the lint-proto command.
// The lint-proto command checks if hydro schemas have gone out of sync.
package root

import (
	"fmt"

	"github.com/spf13/cobra"

	hydro_schemas_turboscan_v0 "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"
	tsproto "github.com/github/turboscan/ts/proto"
)

var LintProtoCmd = &cobra.Command{
	Use:   "lint-proto",
	Short: "Checks if hydro schemas have gone out of sync",
	Long:  "Checks if hydro schemas have gone out of sync.",
	Run: func(cmd *cobra.Command, args []string) {
		twirp := (&tsproto.Result{}).ProtoReflect().Descriptor().Fields()
		hydro := (&hydro_schemas_turboscan_v0.AlertEvent_Result{}).ProtoReflect().Descriptor().Fields()

		// everything in a twirp result should also be in the webhook alert event
		for i := 0; i < twirp.Len(); i++ {
			name := twirp.Get(i).Name()

			if hydro.ByName(name) == nil {
				fmt.Printf("::warning file=ts/hydro/schemas/turboscan/v0/alert_event.pb.go::missing field: %s\n", name)
			}
		}
	},
}
