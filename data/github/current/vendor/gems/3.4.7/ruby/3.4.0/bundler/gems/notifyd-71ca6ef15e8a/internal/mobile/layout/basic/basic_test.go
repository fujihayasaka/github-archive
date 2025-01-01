package basic

import (
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	pbany "google.golang.org/protobuf/types/known/anypb"

	"github.com/github/notifyd/internal/mobile/clients"
	"github.com/github/notifyd/internal/pkg/layouts"
	pg_mobile "github.com/github/notifyd/proto/layouts/mobile"
)

func TestRender(t *testing.T) {
	r := require.New(t)
	tests := []*struct {
		name             string
		description      string
		layoutData       pg_mobile.Basic
		notificationType string
		expected         clients.Notification
	}{
		{
			name:        "All attributes provided",
			description: "It should return Notification struct with all the expected fields",
			layoutData: pg_mobile.Basic{
				Title:             "mikrobi wants your attention",
				Subtitle:          "He's blocked on xyz",
				Body:              "Open this notification to read more about mikrobis issues",
				Url:               "https://example.com/blockers",
				AvatarUrl:         "https://github.com/mikrobi.png",
				AuthorProfileName: "Jakob",
				AuthorUsername:    "mikrobi",
				ThreadId:          "12345",
				ThreadType:        "Issue",
				SubjectId:         "cdIUTEIUYEYIY",
			},
			notificationType: "mention",
			expected: clients.Notification{
				Title:             "mikrobi wants your attention",
				SubTitle:          "He's blocked on xyz",
				Body:              "Open this notification to read more about mikrobis issues",
				URL:               "https://example.com/blockers",
				Type:              "mention",
				AvatarURL:         "https://github.com/mikrobi.png",
				AuthorProfileName: "Jakob",
				AuthorUsername:    "mikrobi",
				ThreadID:          "12345",
				ThreadType:        "Issue",
				SubjectID:         "cdIUTEIUYEYIY",
			},
		},
		{
			name:        "Fields contain nil values",
			description: "It should unmarshall nil fields into empty strings",
			layoutData: pg_mobile.Basic{ // Fields like URL are empty on purpose
				Title:    "P = NP solved with one simple trick!",
				Subtitle: "Click here to learn more.",
				Body:     "Let N = 1",
			},
			notificationType: "",
			expected: clients.Notification{
				Title:             "P = NP solved with one simple trick!",
				SubTitle:          "Click here to learn more.",
				Body:              "Let N = 1",
				URL:               "",
				Type:              "",
				AvatarURL:         "",
				AuthorProfileName: "",
				AuthorUsername:    "",
				ThreadID:          "",
				ThreadType:        "",
				SubjectID:         "",
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			layoutBytes, err := proto.Marshal(&test.layoutData)
			r.NoError(err)

			packedData := &pbany.Any{
				TypeUrl: TypeURL,
				Value:   layoutBytes,
			}

			notification, err := Render(packedData, test.notificationType)

			r.NoError(err, test.description)
			r.Equal(test.expected, *notification, test.description)
		})
	}
}

func TestRenderProtoError(t *testing.T) {
	r := require.New(t)
	randomBytes := []byte{23, 67, 102, 56}
	packedData := &pbany.Any{
		TypeUrl: TypeURL,
		Value:   randomBytes,
	}

	notification, err := Render(packedData, "")

	r.Nil(notification)
	var unmarshallingErr layouts.UnmarshallingError
	r.ErrorAs(err, &unmarshallingErr)
}

func TestRenderTypeUrlError(t *testing.T) {
	r := require.New(t)
	packedData := &pbany.Any{
		TypeUrl: "testing/not-a-layout",
		Value:   []byte{},
	}

	notification, err := Render(packedData, "")

	r.Nil(notification)
	var typeErr layouts.TypeError
	r.ErrorAs(err, &typeErr)
}
