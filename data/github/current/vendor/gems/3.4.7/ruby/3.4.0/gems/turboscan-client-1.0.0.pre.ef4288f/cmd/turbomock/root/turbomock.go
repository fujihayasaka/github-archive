// Package root is a package to keep all functionality related to `turbomock` in one place.
package root

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"time"

	"google.golang.org/protobuf/encoding/prototext"
	"google.golang.org/protobuf/proto"

	"github.com/twitchtv/twirp"

	"github.com/github/turboscan/cmd/turbomock/data"
	"github.com/github/turboscan/cmd/turbomock/root/services"
	tsproto "github.com/github/turboscan/ts/proto"
	"github.com/spf13/cobra"
)

func handler(cassettePath string) http.Handler {
	opt := twirp.WithServerInterceptors(func(next twirp.Method) twirp.Method {
		return func(ctx context.Context, req any) (any, error) {
			name, ok := twirp.MethodName(ctx)
			args, err := prototext.Marshal(req.(proto.Message))
			if ok && err == nil {
				log.Printf("↪️ %s(%s)", name, string(args))
			}

			return next(ctx, req)
		}
	})

	resultsSvc := tsproto.NewResultsServer(&services.ResultsResponses{}, opt)
	insightsSvc := tsproto.NewInsightsServer(&services.InsightsResponses{}, opt)
	managedAnalysesSvc := tsproto.NewManagedAnalysesServer(&services.ManagedAnalysesResponses{}, opt)
	suggestedFixesSvc := tsproto.NewSuggestedFixesServer(&services.SuggestedFixesResponses{}, opt)

	mux := http.NewServeMux()
	mux.Handle(resultsSvc.PathPrefix(), resultsSvc)
	mux.Handle(insightsSvc.PathPrefix(), insightsSvc)
	mux.Handle(managedAnalysesSvc.PathPrefix(), managedAnalysesSvc)
	mux.Handle(suggestedFixesSvc.PathPrefix(), suggestedFixesSvc)

	return data.Mux(cassettePath, mux)

}

const DefaultCassettePath = "ruby/spec/fixtures/vcr_cassettes/code-scanning"

var TurbomockCmd = &cobra.Command{
	Use:   "turbomock",
	Short: "Turbomock creates and runs a mock server to be used for development",
	Long:  `Turbomock creates and runs a mock server to be used for development.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		host, err := cmd.Flags().GetString("host")
		if err != nil {
			return err
		}
		log.SetFlags(0)
		log.SetPrefix("[turbomock] ")

		log.SetOutput(cmd.OutOrStderr())

		cassettePath := DefaultCassettePath

		if len(args) == 1 {
			cassettePath = args[0]
		}

		addr := fmt.Sprintf("%s:8888", host)

		log.Printf("Starting listener on %s...", addr)

		srv := &http.Server{
			Handler:      handler(cassettePath),
			Addr:         addr,
			ReadTimeout:  2 * time.Second,
			WriteTimeout: 2 * time.Second,
		}

		if err := srv.ListenAndServe(); err != nil {
			return err
		}
		return nil
	},
}

func init() {
	TurbomockCmd.Flags().String("host", "127.0.0.1", "host address")
}

func Execute() error {
	return TurbomockCmd.Execute()
}
