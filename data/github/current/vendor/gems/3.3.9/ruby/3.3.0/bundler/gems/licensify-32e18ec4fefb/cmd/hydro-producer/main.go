// This is the main entry point for the hydro-producer service.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"

	hydroPkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/hydro"
	"github.com/github/licensify/internal/testproducer"
)

func main() {
	if err := runProducer(); err != nil {
		fmt.Printf("failed to run the producer: %v\n", err)
		os.Exit(1)
	}
}

func runProducer() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	if cfg.IsProduction() {
		return fmt.Errorf("this producer should not be run in a production environment")
	}

	ctx := context.Background()

	kc, err := hydro.NewKafkaConfig(ctx, cfg)
	if err != nil {
		return err
	}

	sink, err := hydroPkg.NewKafkaSink(*kc)
	if err != nil {
		return err
	}

	publisher, err := hydroPkg.NewPublisher(sink)
	if err != nil {
		return err
	}

	testProducer := testproducer.NewTestProducer(cfg, publisher)

	messageType := flag.String("message-type", "", "Specify which Hydro message to use")
	action := flag.String("action", "ACTION_UNKNOWN", "Specify which action to use")
	membershipUpdateContext := flag.String("context", "CONTEXT_UNKNOWN", "Specify which context to use")
	organizationID := flag.Int64("organization-id", -1, "Optionally override the organization ID in the message")
	flag.Parse()

	if *messageType == "" {
		return fmt.Errorf("message-type is required")
	}

	log.Printf("Processing %s message", *messageType)

	switch *messageType {
	case "MembershipUpdate":
		err = testProducer.HandleMembershipUpdate(*membershipUpdateContext, *action)
	case "OrganizationAdd":
		err = testProducer.HandleOrganizationAdd(*organizationID)
	default:
		err = fmt.Errorf("message not supported")
	}

	if err != nil {
		return err
	}

	log.Println("Successfully published message")

	return nil
}
