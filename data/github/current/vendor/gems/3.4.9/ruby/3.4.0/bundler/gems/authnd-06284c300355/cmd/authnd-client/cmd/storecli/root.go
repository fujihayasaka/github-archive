package storecli

import (
	"database/sql"
	"fmt"
	"reflect"
	"strconv"
	"strings"

	"github.com/github/authnd/internal/common/config"
	"github.com/github/authnd/internal/common/db"
	"github.com/github/authnd/internal/common/db/schemas"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
	"github.com/spf13/cobra"
)

func NewStoreRootCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "store",
		Short: "Execute MySQL store operations on local DB instance.",
	}

	// dynamically register a subcommand for each exported method of the store.Store interface
	var store store.Store
	typ := reflect.TypeOf(&store).Elem()
	for i := 0; i < typ.NumMethod(); i++ {
		cmd.AddCommand(newStoreCmd(typ.Method(i)))
	}

	return cmd
}

type storeCmd struct{}

func (sc *storeCmd) RunFunc(method reflect.Method) func(cmd *cobra.Command, args []string) error {
	return func(cmd *cobra.Command, args []string) error {
		fmt.Printf(">> executing store.%s\n", method.Name)

		cfg, err := config.NewCommonConfigFromEnvironment()
		if err != nil {
			return err
		}

		ctx := cmd.Context()
		verbose, err := cmd.Flags().GetBool("verbose")
		if err == nil && verbose {
			logger := cfg.NewLogger()
			ctx = diagnostics.WithLogger(ctx, logger)
		}

		store, err := newMySQLStore(cfg)
		if err != nil {
			return err
		}
		storeVal := reflect.ValueOf(store)

		// Because Cobra provides all positional args as strings, we need to explicitly cast them to the
		// correct types before passing them into reflect.Method.Call.
		argVals := make([]reflect.Value, len(args)+1)
		argVals[0] = reflect.ValueOf(ctx)
		for ix, arg := range args {
			expectedType := method.Type.In(ix + 1)
			switch prim := expectedType.Name(); prim {
			case "string":
				argVals[ix+1] = reflect.ValueOf(arg)

			case "int64", "uint64":
				argInt, err := strconv.Atoi(arg)
				if err != nil {
					return errors.Errorf("expected arg %d to store.%s to have type %v, but found %v: %v",
						ix+1, method.Name, prim, arg, err)
				}
				if prim == "int64" {
					argVals[ix+1] = reflect.ValueOf(int64(argInt))
				} else {
					argVals[ix+1] = reflect.ValueOf(uint64(argInt))
				}

			default:
				return errors.Errorf("unexpected arg type %s found in store.%s", prim, method.Name)
			}
		}

		resultVals := storeVal.MethodByName(method.Name).Call(argVals)

		// grab the last return arg, which should be an error
		resultErr, ok := resultVals[len(resultVals)-1].Interface().(error)
		if ok && resultErr != nil {
			if errors.Is(resultErr, sql.ErrNoRows) {
				// silence the stack trace for well-known MySQL error
				return errors.New("no rows found")
			}
			return resultErr
		}

		// print the returned values
		for i := 0; i < len(resultVals)-1; i++ {
			val := resultVals[i]
			fmt.Printf("[%d] (%v) = %+v\n", i+1, val.Type(), val)
		}
		return nil
	}
}

func newStoreCmd(method reflect.Method) *cobra.Command {
	// generate the command usage to include the concrete types of the positional args.
	var usage strings.Builder
	usage.WriteString(method.Name)
	for ix := 1; ix < method.Type.NumIn(); ix++ {
		usage.WriteString(" <")
		usage.WriteString(method.Type.In(ix).Name())
		usage.WriteString(">")
	}
	var (
		sc  storeCmd
		cmd = &cobra.Command{
			Use:  usage.String(),
			Long: fmt.Sprintf(`Executes the store.%s method.  Positional args should match function signature, minus context.Context.`, method.Name),
			Args: cobra.ExactArgs(method.Type.NumIn() - 1), // exclude the context.Context
			RunE: sc.RunFunc(method),
		}
	)

	return cmd
}

func newMySQLStore(cfg *config.CommonConfig) (store.Store, error) {
	provider, err := db.NewProvider(cfg, schemas.All(), log.NewNullLogger(), stats.NullStatter)
	if err != nil {
		return nil, err
	}

	return store.NewStore(provider, false)
}
