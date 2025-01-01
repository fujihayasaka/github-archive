package v2_test

import (
	"context"
	"errors"
	"testing"

	"github.com/benbjohnson/clock"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	v2 "github.com/github/notifyd/internal/api/devicetokensserver/v2"
	"github.com/github/notifyd/internal/pkg/devicetokens"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	pb "github.com/github/notifyd/proto/services/devicetokens/v2"
)

func TestSet_OK(t *testing.T) {
	storage := devicetokens.NewStorageMock(t)
	storage.On("Set", mock.Anything, int64(1), int64(2), "a token").Once().Return(true, nil)

	server := v2.NewServer(clock.NewMock(), logs.NullTelem, storage)
	set, err := server.Set(context.Background(), &pb.SetRequest{UserId: 1, OauthAccessId: 2, Token: "a token"})
	require.NoError(t, err)
	require.True(t, set.GetValue())
}

func TestSet_OverLimit(t *testing.T) {
	storage := devicetokens.NewStorageMock(t)
	storage.On("Set", mock.Anything, int64(1), int64(2), "a token").Once().Return(false, nil)

	server := v2.NewServer(clock.NewMock(), logs.NullTelem, storage)
	set, err := server.Set(context.Background(), &pb.SetRequest{UserId: 1, OauthAccessId: 2, Token: "a token"})
	require.NoError(t, err)
	require.False(t, set.GetValue())
}

func TestSet_Error(t *testing.T) {
	storage := devicetokens.NewStorageMock(t)
	storage.On("Set", mock.Anything, int64(1), int64(2), "a token").Once().Return(false, errors.New("an error"))

	server := v2.NewServer(clock.NewMock(), logs.NullTelem, storage)
	_, err := server.Set(context.Background(), &pb.SetRequest{UserId: 1, OauthAccessId: 2, Token: "a token"})
	require.Error(t, err)
}

func TestDelete_OK(t *testing.T) {
	storage := devicetokens.NewStorageMock(t)
	storage.On("Delete", mock.Anything, int64(1), "a token").Once().Return(nil)

	server := v2.NewServer(clock.NewMock(), logs.NullTelem, storage)
	_, err := server.Delete(context.Background(), &pb.DeleteRequest{UserId: 1, Token: "a token"})
	require.NoError(t, err)
}

func TestDelete_Error(t *testing.T) {
	storage := devicetokens.NewStorageMock(t)
	storage.On("Delete", mock.Anything, int64(1), "a token").Once().Return(errors.New("an error"))

	server := v2.NewServer(clock.NewMock(), logs.NullTelem, storage)
	_, err := server.Delete(context.Background(), &pb.DeleteRequest{UserId: 1, Token: "a token"})
	require.Error(t, err)
}

func TestDeleteAll_OK(t *testing.T) {
	storage := devicetokens.NewStorageMock(t)
	storage.On("DeleteAll", mock.Anything, int64(1)).Once().Return(nil)

	server := v2.NewServer(clock.NewMock(), logs.NullTelem, storage)
	_, err := server.DeleteAll(context.Background(), &pb.DeleteAllRequest{UserId: 1})
	require.NoError(t, err)
}

func TestDeleteAll_Error(t *testing.T) {
	storage := devicetokens.NewStorageMock(t)
	storage.On("DeleteAll", mock.Anything, int64(1)).Once().Return(errors.New("an error"))

	server := v2.NewServer(clock.NewMock(), logs.NullTelem, storage)
	_, err := server.DeleteAll(context.Background(), &pb.DeleteAllRequest{UserId: 1})
	require.Error(t, err)
}
