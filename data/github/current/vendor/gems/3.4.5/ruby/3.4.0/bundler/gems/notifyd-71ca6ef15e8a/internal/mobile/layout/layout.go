// Package layout implements the layout processing of mobile push notifications.
package layout

import (
	pbAny "google.golang.org/protobuf/types/known/anypb"

	"github.com/github/notifyd/internal/mobile/clients"
	"github.com/github/notifyd/internal/mobile/layout/basic"
	"github.com/github/notifyd/internal/pkg/layouts"
)

type renderFn func(layoutData *pbAny.Any, notificationType string) (*clients.Notification, error)

// Registry of type urls to render functions, new layouts should be added here
var registry = map[string]renderFn{
	basic.TypeURL: basic.Render,
}

// Render a specific layout. Determines the correct layout template to use from the type url
// in the layout data
func Render(layoutData *pbAny.Any, notificationType string) (*clients.Notification, error) {
	typeURL := layoutData.GetTypeUrl()

	renderFn, ok := registry[typeURL]

	if !ok {
		return nil, layouts.NewTypeError(typeURL)
	}

	return renderFn(layoutData, notificationType)
}
