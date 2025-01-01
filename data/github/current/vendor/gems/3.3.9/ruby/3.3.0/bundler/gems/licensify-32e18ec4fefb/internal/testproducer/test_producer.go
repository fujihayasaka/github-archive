// Package testproducer provides a way to publish Hydro messages for testing purposes.
package testproducer

import (
	"fmt"

	hydroPkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/testing/stubs"
	"google.golang.org/protobuf/reflect/protoreflect"
)

// TestProducer is a producer that publishes Hydro messages for testing purposes.
type TestProducer struct {
	cfg       *config.Config
	publisher *hydroPkg.Publisher
}

// NewTestProducer creates a new TestProducer.
func NewTestProducer(cfg *config.Config, publisher *hydroPkg.Publisher) *TestProducer {
	return &TestProducer{
		cfg:       cfg,
		publisher: publisher,
	}
}

// HandleOrganizationAdd publishes a new OrganizationAdd message.
func (tp *TestProducer) HandleOrganizationAdd(organizationID int64) error {
	message := stubs.NewOrganizationAddHydroMsg()
	if organizationID >= 0 {
		message.Organization.Id = uint64(organizationID)
	}

	return tp.publish(message)
}

// HandleMembershipUpdate publishes a new MembershipUpdate message.
func (tp *TestProducer) HandleMembershipUpdate(context, action string) error {
	contextInt, contextExists := githubv1.MembershipUpdate_Context_value[context]
	if !contextExists {
		return fmt.Errorf("invalid context: %s", context)
	}
	contextVal := githubv1.MembershipUpdate_Context(contextInt)

	actionInt, actionExists := githubv1.MembershipUpdate_Action_value[action]
	if !actionExists {
		return fmt.Errorf("invalid action: %s", action)
	}
	actionVal := githubv1.MembershipUpdate_Action(actionInt)

	message := stubs.NewMembershipUpdateHydroMsg(contextVal, actionVal)

	return tp.publish(message)
}

// publish publishes a Hydro message.
func (tp *TestProducer) publish(message protoreflect.ProtoMessage) error {
	if tp.cfg.IsProduction() {
		return fmt.Errorf("this producer should not be run in a production environment")
	}

	err := tp.publisher.Publish(message)
	if err != nil {
		return err
	}

	return nil
}
