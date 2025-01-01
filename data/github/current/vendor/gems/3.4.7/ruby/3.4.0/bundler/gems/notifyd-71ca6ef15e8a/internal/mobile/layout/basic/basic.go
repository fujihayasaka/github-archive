// Package basic implements the basic mobile layout processor.
package basic

import (
	"google.golang.org/protobuf/proto"
	pbAny "google.golang.org/protobuf/types/known/anypb"

	"github.com/github/notifyd/internal/mobile/clients"
	"github.com/github/notifyd/internal/pkg/layouts"
	pb_mobile "github.com/github/notifyd/proto/layouts/mobile"
)

// TypeURL is the type url for the basic layout.
var TypeURL = "type.googleapis.com/notifyd.layouts.mobile.Basic"

// Render takes layout data and renders a notification.
func Render(layoutData *pbAny.Any, notificationType string) (*clients.Notification, error) {
	var data pb_mobile.Basic

	if typeURL := layoutData.GetTypeUrl(); typeURL != TypeURL {
		return nil, layouts.NewTypeError(typeURL)
	}

	err := proto.Unmarshal(layoutData.GetValue(), &data)

	if err != nil {
		return nil, layouts.NewUnmarshallingError(err, TypeURL)
	}

	return &clients.Notification{
		SubjectID:         data.GetSubjectId(),
		Title:             data.GetTitle(),
		SubTitle:          data.GetSubtitle(),
		Body:              data.GetBody(),
		URL:               data.GetUrl(),
		Type:              notificationType,
		AvatarURL:         data.GetAvatarUrl(),
		AuthorProfileName: data.GetAuthorProfileName(),
		AuthorUsername:    data.GetAuthorUsername(),
		ThreadID:          data.GetThreadId(),
		ThreadType:        data.GetThreadType(),
	}, nil
}
