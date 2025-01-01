package main

import (
	"context"
	"log"
	"syscall"
	"time"

	"github.com/github/go-ctxutil/sigctx"
	"github.com/github/hydro-client-go/v3/pkg/hydro"
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"

	"github.com/github/launch/cli"
	ghschemas "github.com/github/launch/hydro/schemas/github/v1"
	ghentities "github.com/github/launch/hydro/schemas/github/v1/entities"
)

type config struct {
	kafka hydro.KafkaConfig
}

func main() {
	cli.ParseFlags()
	kafka, err := hydro.NewKafkaConfig([]string{"localhost:9092"})
	if err != nil {
		log.Fatalf("error creating kafka config: %v", err)
	}

	cfg := &config{
		kafka: *kafka,
	}

	ctx := sigctx.WithSignal(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	if err := runKafkaSinkSource(ctx, cfg); err != nil {
		log.Fatalf("error running kafka sink: %v", err)
	}
}

func runKafkaSinkSource(ctx context.Context, cfg *config) error {
	g, ctx := errgroup.WithContext(ctx)

	g.Go(func() error {
		sink, err := hydro.NewKafkaSink(cfg.kafka)
		if err != nil {
			return errors.Wrap(err, "error creating kafka file")
		}

		log.Println("Starting Kafka sink")
		return produce(ctx, sink)
	})

	return g.Wait()
}

func produce(ctx context.Context, sink hydro.Sink) error {
	p, err := hydro.NewPublisher(sink, hydro.Localhost, hydro.WithTopicSite(hydro.CP1IAD))
	if err != nil {
		return errors.Wrap(err, "error creating hydro publisher")
	}
	defer func() {
		log.Println("stopping publisher...")
		if err := p.Close(); err != nil {
			log.Printf("error closing publisher: %v", err)
		}
	}()

	t := time.NewTicker(500 * time.Millisecond)
	defer t.Stop()
	log.Println("we're running this producer")
	for {
		select {
		case <-ctx.Done():
			log.Println("finishing up here")
			return ctx.Err()
		case <-t.C:
			msg := &ghschemas.RepositoryDeleted{
				DeletedRepository: &ghentities.Repository{
					Id:            1,
					Name:          "docker-actions",
					GlobalRelayId: "R_kgAB",
				},
			}
			if err := p.Publish(msg); err != nil {
				log.Printf("error publishing repository deleted message: %s\n", err.Error())
				return errors.Wrap(err, "error publishing message")
			}

			otherMsg := &ghschemas.UserDestroy{
				User: &ghentities.User{
					Id:            2,
					Type:          ghentities.User_ORGANIZATION,
					Login:         "monalisa",
					GlobalRelayId: "U_kgAC",
				},
			}
			if err := p.Publish(otherMsg); err != nil {
				log.Printf("error publishing user destroy message: %s\n", err.Error())
				return errors.Wrap(err, "error publishing message")
			}
		}
	}
}
