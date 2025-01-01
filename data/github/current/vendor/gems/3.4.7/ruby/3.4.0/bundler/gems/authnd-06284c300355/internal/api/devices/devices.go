package devices

import (
	"time"

	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/publisher"
	"github.com/github/authnd/internal/common/store"
	layoutProto "github.com/github/notifyd/proto/layouts/mobile"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/twitchtv/twirp"
)

type mobileDeviceStore interface {
	store.MobileDeviceKeysStore
	store.MobileDeviceAuthRequestsStore
}

// A MobileDeviceManager implements the MobileDeviceManager protobuf service.
type MobileDeviceManager struct {
	store     mobileDeviceStore
	publisher publisher.NotificationPublisher
	nowFunc   func() time.Time
}

func NewSignInRequestLayoutData() *layoutProto.Basic {
	return &layoutProto.Basic{
		Title: "Sign In Request",
		Body:  "Verify your identity to approve signing in to GitHub.",
	}
}

func NewDeviceVerificationLayoutData() *layoutProto.Basic {
	return &layoutProto.Basic{
		Title: "Sign-in Verification",
		Body:  "Verify your unrecognized sign-in to finish signing in to GitHub.",
	}
}

func NewPasswordResetLayoutData() *layoutProto.Basic {
	return &layoutProto.Basic{
		Title: "Password Reset Request",
		Body:  "Verify your identity to continue the GitHub password reset process.",
	}
}
func NewSudoChallengeLayoutData() *layoutProto.Basic {
	return &layoutProto.Basic{
		Title: "Sudo Mode Request",
		Body:  "Verify your identity to escalate to sudo mode.",
	}
}

// NewMobileDeviceManagerServer creates a new MobileDeviceManager and uses the provided Twirp ServerHooks to create a TwirpServer that can host it.
func NewMobileDeviceManagerServer(store store.Store, publisher publisher.NotificationPublisher, hooks *twirp.ServerHooks) pb.TwirpServer {
	manager := &MobileDeviceManager{
		store,
		publisher,
		func() time.Time {
			return time.Now().UTC()
		},
	}
	return pb.NewMobileDeviceManagerServer(manager, hooks)
}

// canUseDeviceKeyForAuthRequestCompletion returns true if the device key can be used to complete an authentication request.
func canUseDeviceKeyForAuthRequestCompletion(deviceKey *models.MobileDeviceKey, authRequest *models.MobileAuthRequest) bool {
	// the device key can only be used if the auth request was created after the device key was created
	return !authRequest.CreatedAt.Time.Before(deviceKey.CreatedAt.Time)
}
