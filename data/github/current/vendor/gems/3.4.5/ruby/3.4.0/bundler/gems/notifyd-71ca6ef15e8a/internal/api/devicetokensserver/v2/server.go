// Package v2 implements version 2 of the device tokens server.
package v2

import (
	"context"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/emptypb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/api"
	"github.com/github/notifyd/internal/pkg/devicetokens"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	pb "github.com/github/notifyd/proto/services/devicetokens/v2"
)

// Server represents a device tokens server.
type Server struct {
	telem   *telemetry.Provider
	storage devicetokens.Storage
}

// NewServer creates a new device tokens server.
func NewServer(clock clockpkg.Clock, telem *telemetry.Provider, storage devicetokens.Storage) Server {
	return Server{telem: telem, storage: storage}
}

// Handler returns a handler for the device tokens server.
func (s Server) Handler(hooks *twirp.ServerHooks) api.Handler {
	return pb.NewDeviceTokensV2Server(s, hooks)
}

// Set sets a device token for a user.
func (s Server) Set(ctx context.Context, req *pb.SetRequest) (*wrapperspb.BoolValue, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "devicetokensserver")
	ctx = o11y.CtxSetMethod(ctx, "set")

	userID := req.GetUserId()
	ctx = o11y.CtxSetUserID(ctx, userID)
	s.telem.Logger.WithContext(ctx).Info("request received")

	set, err := s.storage.Set(ctx, userID, req.GetOauthAccessId(), req.GetToken())
	if err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Error("unable to set the device token")
		return nil, errors.Mask(err, "Unable to set the device token")
	}

	return wrapperspb.Bool(set), nil
}

// Delete deletes a device token for a user.
func (s Server) Delete(ctx context.Context, req *pb.DeleteRequest) (*emptypb.Empty, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "devicetokensserver")
	ctx = o11y.CtxSetMethod(ctx, "delete")

	userID := req.GetUserId()
	ctx = o11y.CtxSetUserID(ctx, userID)
	s.telem.Logger.WithContext(ctx).Info("request received")

	if err := s.storage.Delete(ctx, userID, req.GetToken()); err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Error("unable to delete the device token")
		return nil, errors.Mask(err, "Unable to delete the device token")
	}

	return &emptypb.Empty{}, nil
}

// DeleteAll deletes all device tokens for a user.
func (s Server) DeleteAll(ctx context.Context, req *pb.DeleteAllRequest) (*emptypb.Empty, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "devicetokensserver")
	ctx = o11y.CtxSetMethod(ctx, "delete")

	userID := req.GetUserId()
	ctx = o11y.CtxSetUserID(ctx, userID)
	s.telem.Logger.WithContext(ctx).Info("request received")

	if err := s.storage.DeleteAll(ctx, userID); err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Error("unable to delete all device tokens")
		return nil, errors.Mask(err, "Unable to delete all device tokens")
	}

	return &emptypb.Empty{}, nil
}
