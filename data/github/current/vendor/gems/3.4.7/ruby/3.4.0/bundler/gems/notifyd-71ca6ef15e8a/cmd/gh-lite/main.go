// Package main implements the entrypoint for the gh-lite server.
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"time"

	authzd_pb "github.com/github/authzd/pkg/proto"
	ghlog "github.com/github/github-telemetry-go/log"
	ghconfig "github.com/github/go-config"
	"github.com/github/go-http/v2/middleware/hmac"

	"github.com/github/notifyd/internal/pkg/config"
	"github.com/github/notifyd/internal/pkg/shutdown"
	notifyd_pb "github.com/github/notifyd/proto/notifyd/v1"
)

func main() {
	config.LoadDotEnv()
	cfg := Config{}
	if err := ghconfig.Load(&cfg); err != nil {
		log.Fatalln(err)
	}

	hmacValidator := &hmac.Validator{
		Secrets: []string{cfg.MonolithTwirpAPIHmacKey},
		Logger:  ghlog.NewNullLogger(),
	}

	mux := http.NewServeMux()
	mux.Handle(
		notifyd_pb.NotifydAPIPathPrefix,
		hmacValidator.Handler(
			notifyd_pb.NewNotifydAPIServer(&svc{}),
		),
	)
	mux.Handle(
		authzd_pb.AuthorizerPathPrefix,
		authzd_pb.NewAuthorizerServer(&authzSvc{}),
	)

	srv := http.Server{
		Addr:              ":8088",
		Handler:           mux,
		ReadHeaderTimeout: 2 * time.Second,
	}

	log.Print("starting GH lite")
	log.Printf("serving monolith-twirp: %s", notifyd_pb.NotifydAPIPathPrefix)
	log.Printf("serving authzd: %s", authzd_pb.AuthorizerPathPrefix)

	go func() {
		err := srv.ListenAndServe()
		log.Fatalln(err)
	}()
	sd := shutdown.New(5*time.Second, ghlog.NewNullLogger())
	sd.Register(srv.Shutdown)

	log.Println("shutting down gracefully, press Ctrl+C again to force")
	if err := sd.Wait(context.Background()); err != nil {
		fmt.Println(err)
	}
}

type authzSvc struct{}

func (s *authzSvc) Authorize(ctx context.Context, req *authzd_pb.Request) (*authzd_pb.Decision, error) {
	log.Print("[Authorize] authorizing the recipient")

	return &authzd_pb.Decision{Result: authzd_pb.Result_ALLOW}, nil
}

func (s *authzSvc) BatchAuthorize(ctx context.Context, req *authzd_pb.BatchRequest) (*authzd_pb.BatchDecision, error) {
	log.Printf("[BatchAuthorize] authorizing %d recipients", len(req.Requests))

	decisions := make([]*authzd_pb.Decision, 0, len(req.Requests))
	for range req.Requests {
		decisions = append(
			decisions,
			&authzd_pb.Decision{Result: authzd_pb.Result_ALLOW},
		)
	}
	return &authzd_pb.BatchDecision{Decisions: decisions}, nil
}

type svc struct{}

func (s *svc) CheckDeliverMobilePushPolicy(ctx context.Context, req *notifyd_pb.CheckDeliverMobilePushPolicyRequest) (*notifyd_pb.CheckDeliverMobilePushPolicyResponse, error) {
	log.Print("[CheckDeliverMobilePushPolicy] authorizing the push notification")

	return &notifyd_pb.CheckDeliverMobilePushPolicyResponse{IsDeliverable: true}, nil
}

func (s *svc) CheckDeliverEmailPolicy(ctx context.Context, req *notifyd_pb.CheckDeliverEmailPolicyRequest) (*notifyd_pb.CheckDeliverEmailPolicyResponse, error) {
	log.Print("[CheckDeliverMobilePushPolicy] authorizing the email notification")

	return &notifyd_pb.CheckDeliverEmailPolicyResponse{
		IsDeliverable: true,
		Email:         "user@email.com",
		Login:         "user",
	}, nil
}

func (s *svc) BatchCheckNotifyPolicy(ctx context.Context, req *notifyd_pb.BatchCheckNotifyPolicyRequest) (*notifyd_pb.BatchCheckNotifyPolicyResponse, error) {
	log.Printf("[BatchCheckNotifyPolicy] authorizing %d recipients", len(req.Recipients))

	resp := make([]*notifyd_pb.CheckNotifyPolicyResponse, 0, len(req.Recipients))
	for _, r := range req.Recipients {
		resp = append(resp, &notifyd_pb.CheckNotifyPolicyResponse{
			UserId: r.GetUserId(),
			Notify: true,
		})
	}
	return &notifyd_pb.BatchCheckNotifyPolicyResponse{Responses: resp}, nil
}

func (s *svc) BatchCheckIgnoredRepository(ctx context.Context, req *notifyd_pb.BatchCheckIgnoredRepositoryRequest) (*notifyd_pb.BatchCheckIgnoredRepositoryResponse, error) {
	log.Printf("[BatchCheckIgnoredRepository] checking ignored repository status for %d recipients", len(req.Recipients))

	resp := make([]*notifyd_pb.CheckNotifyPolicyResponse, 0, len(req.Recipients))
	for _, r := range req.Recipients {
		resp = append(resp, &notifyd_pb.CheckNotifyPolicyResponse{
			UserId: r.GetUserId(),
			Notify: true,
		})
	}
	return &notifyd_pb.BatchCheckIgnoredRepositoryResponse{Responses: resp}, nil
}

func (s *svc) PostProcessEmailContent(ctx context.Context, req *notifyd_pb.PostProcessEmailContentRequest) (*notifyd_pb.PostProcessEmailContentResponse, error) {
	log.Print("[PostProcessEmailContent] redelivering received html")
	return &notifyd_pb.PostProcessEmailContentResponse{ProcessedHtml: req.RawHtml}, nil
}

func (s *svc) GetDeliverEmailData(ctx context.Context, req *notifyd_pb.GetDeliverEmailDataRequest) (*notifyd_pb.GetDeliverEmailDataResponse, error) {
	log.Print("[GetAuthTokens] fetching user auth tokens")
	return &notifyd_pb.GetDeliverEmailDataResponse{
		IsDeliverable: true,
		Email:         "user@email.com",
		Login:         "user",
		AuthTokens:    []*notifyd_pb.AuthToken{{Scope: "mute_auth", Token: "token_mute_auth"}},
	}, nil
}
