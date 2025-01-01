// Package cli unifies certain pieces of CLIs. Every CLI should include the
// following calls in their main() functions:
//
//	func main() {
//	    cli.SetupLogging()
//	    cli.ParseFlags()
//	}
//
// This will ensure the `log` package and `flag` package are setup
// properly.
//
// If the CLI accepts arguments, set `cli.Arguments`:
//
//	cli.Arguments = "REPO [OPTIONS]"
package cli
