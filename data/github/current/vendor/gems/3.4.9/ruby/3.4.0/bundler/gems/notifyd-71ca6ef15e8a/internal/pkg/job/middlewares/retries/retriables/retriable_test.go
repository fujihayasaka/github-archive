package retriables

import (
	"testing"

	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"

	pb0 "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	pb1 "github.com/github/notifyd/hydro/schemas/notifyd/v1"
	"github.com/github/notifyd/internal/pkg/aqueduct"
)

func Test_Notify(t *testing.T) {
	r := require.New(t)
	notificationID := "/org/repo/issues/1"
	retriableMsg := Notify{Notify: &pb0.Notify{NotificationId: notificationID}}

	encoded, err := retriableMsg.Encode()
	r.NoError(err)

	var envelope hydro_pb.Envelope
	err = proto.Unmarshal(encoded, &envelope)
	r.NoError(err)

	r.Equal(NotifyType, MsgType(envelope.TypeUrl))

	var notify pb0.Notify
	err = proto.Unmarshal(envelope.Message, &notify)
	r.NoError(err)

	r.Equal(notificationID, notify.NotificationId)
	r.Equal(aqueduct.QueueNotify, retriableMsg.Queue())
}

func Test_Notify_UpdateRetries(t *testing.T) {
	r := require.New(t)
	retriableMsg := Notify{Notify: &pb0.Notify{}}
	r.Equal(int32(0), retriableMsg.GetAttempts())
	retriableMsg.UpdateRetries()

	r.Equal(int32(1), retriableMsg.GetAttempts())
}

func Test_MobilePush(t *testing.T) {
	r := require.New(t)
	notificationID := "/org/repo/issues/1"
	msg := &pb0.DeliverMobilePush{NotificationId: notificationID}
	retriableMsg := MobilePush{DeliverMobilePush: msg}

	encoded, err := retriableMsg.Encode()
	r.NoError(err)

	var envelope hydro_pb.Envelope
	err = proto.Unmarshal(encoded, &envelope)
	r.NoError(err)

	r.Equal(DeliverMobilePushType, MsgType(envelope.TypeUrl))

	var notify pb0.DeliverMobilePush
	err = proto.Unmarshal(envelope.Message, &notify)
	r.NoError(err)

	r.Equal(notificationID, notify.NotificationId)
	r.Equal(aqueduct.QueueDeliverMobilePush, retriableMsg.Queue())
}

func Test_Email(t *testing.T) {
	r := require.New(t)
	notificationID := "/org/repo/issues/1"
	msg := &pb0.DeliverEmail{NotificationId: notificationID}
	retriableMsg := Email{DeliverEmail: msg}

	encoded, err := retriableMsg.Encode()
	r.NoError(err)

	var envelope hydro_pb.Envelope
	err = proto.Unmarshal(encoded, &envelope)
	r.NoError(err)

	r.Equal(DeliverEmailType, MsgType(envelope.TypeUrl))

	var notify pb0.DeliverEmail
	err = proto.Unmarshal(envelope.Message, &notify)
	r.NoError(err)

	r.Equal(notificationID, notify.NotificationId)
	r.Equal(aqueduct.QueueDeliverEmail, retriableMsg.Queue())
}

func Test_DeleteRepository(t *testing.T) {
	r := require.New(t)
	msg := &pb1.DeleteRepository{RepositoryId: 1}
	retriableMsg := DeleteRepository{DeleteRepository: msg}

	encoded, err := retriableMsg.Encode()
	r.NoError(err)

	var envelope hydro_pb.Envelope
	err = proto.Unmarshal(encoded, &envelope)
	r.NoError(err)

	r.Equal(DeleteRepositoryType, MsgType(envelope.TypeUrl))

	var notify pb1.DeleteRepository
	err = proto.Unmarshal(envelope.Message, &notify)
	r.NoError(err)

	r.Equal(int64(1), notify.RepositoryId)
	r.Equal(aqueduct.QueueDeleteRepository, retriableMsg.Queue())
}

func Test_DeleteRepositoryForUsers(t *testing.T) {
	r := require.New(t)
	msg := &pb1.DeleteRepositoryForUsers{RepositoryId: 1}
	retriableMsg := DeleteRepositoryForUsers{DeleteRepositoryForUsers: msg}

	encoded, err := retriableMsg.Encode()
	r.NoError(err)

	var envelope hydro_pb.Envelope
	err = proto.Unmarshal(encoded, &envelope)
	r.NoError(err)

	r.Equal(DeleteRepositoryForUsersType, MsgType(envelope.TypeUrl))

	var notify pb1.DeleteRepositoryForUsers
	err = proto.Unmarshal(envelope.Message, &notify)
	r.NoError(err)

	r.Equal(int64(1), notify.RepositoryId)
	r.Equal(aqueduct.QueueDeleteRepositoryForUsers, retriableMsg.Queue())
}

func Test_DeleteUser(t *testing.T) {
	r := require.New(t)
	msg := &pb1.DeleteUser{UserId: 1}
	retriableMsg := DeleteUser{DeleteUser: msg}

	encoded, err := retriableMsg.Encode()
	r.NoError(err)

	var envelope hydro_pb.Envelope
	err = proto.Unmarshal(encoded, &envelope)
	r.NoError(err)

	r.Equal(DeleteUserType, MsgType(envelope.TypeUrl))

	var notify pb1.DeleteUser
	err = proto.Unmarshal(envelope.Message, &notify)
	r.NoError(err)

	r.Equal(int64(1), notify.UserId)
	r.Equal(aqueduct.QueueDeleteUser, retriableMsg.Queue())
}

func Test_DeleteUserRepositories(t *testing.T) {
	r := require.New(t)
	msg := &pb1.DeleteUserRepositories{UserId: 1}
	retriableMsg := DeleteUserRepositories{DeleteUserRepositories: msg}

	encoded, err := retriableMsg.Encode()
	r.NoError(err)

	var envelope hydro_pb.Envelope
	err = proto.Unmarshal(encoded, &envelope)
	r.NoError(err)

	r.Equal(DeleteUserRepositoriesType, MsgType(envelope.TypeUrl))

	var notify pb1.DeleteUserRepositories
	err = proto.Unmarshal(envelope.Message, &notify)
	r.NoError(err)

	r.Equal(int64(1), notify.UserId)
	r.Equal(aqueduct.QueueDeleteUserRepositories, retriableMsg.Queue())
}
