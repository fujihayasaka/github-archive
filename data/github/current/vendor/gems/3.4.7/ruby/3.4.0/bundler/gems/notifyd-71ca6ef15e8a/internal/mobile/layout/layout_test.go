package layout

import (
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/github/notifyd/internal/mobile/clients"
	"github.com/github/notifyd/internal/pkg/layouts"
)

func TestRenderCallsLayout(t *testing.T) {
	r := require.New(t)
	prevRegistry := registry
	defer func() { registry = prevRegistry }()

	expectedNotification := clients.Notification{
		Title:    "test title",
		SubTitle: "test subtitle",
		URL:      "https://example.com/test-url",
	}

	registry["testing/a-type-url"] = func(layoutData *anypb.Any, notificationType string) (*clients.Notification, error) {
		return &expectedNotification, nil
	}

	packedData := &anypb.Any{
		TypeUrl: "testing/a-type-url",
		Value:   []byte{},
	}

	notification, err := Render(packedData, "")

	r.NoError(err)
	r.Equal(&expectedNotification, notification)
}

func TestRenderMissingType(t *testing.T) {
	r := require.New(t)
	packedData := &anypb.Any{
		TypeUrl: "testing/not-a-layout",
		Value:   []byte{},
	}

	notification, err := Render(packedData, "")

	r.Nil(notification)
	var typeErr layouts.TypeError
	r.ErrorAs(err, &typeErr)
}
