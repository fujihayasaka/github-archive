// Package newsiesserver implements the server for the newsiesservice service.
package newsiesserver

import (
	"context"
	"strconv"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/twitchtv/twirp"

	"github.com/github/notifyd/internal/api"
	"github.com/github/notifyd/internal/api/newsiesservice"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	pb "github.com/github/notifyd/proto/services/newsies"
)

// Server struct implements the necessary endpoints for the newsiesservice.Newsies interface for the
// server.
type Server struct {
	svc   *newsiesservice.Service
	telem *telemetry.Provider
}

// New returns a new server
func New(svc *newsiesservice.Service, telem *telemetry.Provider) *Server {
	return &Server{
		svc:   svc,
		telem: telem,
	}
}

// Handler returns a handler for the newsies server.
func (s *Server) Handler(hooks *twirp.ServerHooks) api.Handler {
	return pb.NewNewsiesServer(s, hooks)
}

// Watch implements the workflow that newsies follows to watch a List/ThreadType but translating it
// into notifyd terms (that is, subscriptions + routing settings equivalent)
func (s *Server) Watch(ctx context.Context, req *pb.WatchRequest) (*pb.WatchResponse, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "newsies")
	ctx = o11y.CtxSetMethod(ctx, "watch")
	ctx = o11y.CtxSetUserID(ctx, req.UserId)
	ctx = o11y.CtxSetSubjectType(ctx, req.RefType)
	ctx = o11y.CtxSetSubjectValue(ctx, strconv.FormatInt(req.RefId, 10))

	types, err := threadTypesAdapter(req.GetThreadTypes())
	if err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Error("failed to parse thread types")
		return nil, errors.Mask(err, "Error validating thread types in the request")
	}
	customFields := subscriptionsCustomFieldsAdapter(req.GetCustomFields())

	if err = s.svc.Watch(ctx, req.GetUserId(), req.GetRefId(), req.GetRefType(), types, customFields); err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Error("failed to watch")
		return nil, errors.Mask(err, "Failed to complete Watch request")
	}

	return &pb.WatchResponse{
		UserId:  req.GetUserId(),
		RefId:   req.GetRefId(),
		RefType: req.GetRefType(),
	}, nil
}

// Unwatch implements handling an unwatch request.
func (s *Server) Unwatch(ctx context.Context, req *pb.UnwatchRequest) (*pb.UnwatchResponse, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "newsies")
	ctx = o11y.CtxSetMethod(ctx, "unwatch")
	ctx = o11y.CtxSetUserID(ctx, req.UserId)
	ctx = o11y.CtxSetSubjectType(ctx, req.RefType)
	ctx = o11y.CtxSetSubjectValue(ctx, strconv.FormatInt(req.RefId, 10))

	if err := validateUnwatchRequest(req); err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Error("failed to unwatch")
		return nil, errors.Mask(err, "Validation of Unwatch request failed")
	}

	var refIDs []int64
	if req.GetRefId() > 0 {
		refIDs = []int64{req.GetRefId()}
	} else {
		refIDs = req.GetRefIds()
	}

	if err := s.svc.Unwatch(ctx, req.GetUserId(), refIDs, req.GetRefType()); err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Error("failed to unwatch")
		return nil, errors.Mask(err, "Failed to complete Unwatch request")
	}

	return &pb.UnwatchResponse{
		UserId:  req.GetUserId(),
		RefId:   req.GetRefId(),
		RefIds:  req.GetRefIds(),
		RefType: req.GetRefType(),
	}, nil
}

// UnwatchAll implements handling an unwatch all request.
func (s *Server) UnwatchAll(ctx context.Context, req *pb.UnwatchAllRequest) (*pb.UnwatchAllResponse, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "newsies")
	ctx = o11y.CtxSetMethod(ctx, "unwatch_all")
	ctx = o11y.CtxSetUserID(ctx, req.UserId)
	ctx = o11y.CtxSetSubjectType(ctx, req.RefType)

	if err := s.svc.UnwatchAll(ctx, req.GetUserId(), req.GetRefType()); err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Error("failed to unwatch")
		return nil, errors.Mask(err, "Failed to complete Unwatch request")
	}

	return &pb.UnwatchAllResponse{
		UserId:  req.GetUserId(),
		RefType: req.GetRefType(),
	}, nil
}

// Ignore implements handling an ignore request.
func (s *Server) Ignore(ctx context.Context, req *pb.IgnoreRequest) (*pb.IgnoreResponse, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "newsies")
	ctx = o11y.CtxSetMethod(ctx, "ignore")
	ctx = o11y.CtxSetUserID(ctx, req.UserId)
	ctx = o11y.CtxSetSubjectType(ctx, req.RefType)
	ctx = o11y.CtxSetSubjectValue(ctx, strconv.FormatInt(req.RefId, 10))

	customFields := settingsCustomFieldsAdapter(req.GetCustomFields())
	if err := s.svc.Ignore(ctx, req.GetUserId(), req.GetRefId(), req.GetRefType(), customFields); err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Error("failed to ignore")
		return nil, errors.Mask(err, "Failed to complete Ignore request")
	}

	return &pb.IgnoreResponse{
		UserId:  req.GetUserId(),
		RefId:   req.GetRefId(),
		RefType: req.GetRefType(),
	}, nil
}

func validateUnwatchRequest(req *pb.UnwatchRequest) error {
	if req.RefId != 0 && len(req.RefIds) != 0 {
		return errors.New("You must specify either RefIds or RefId property")
	}

	if req.RefId != 0 && len(req.RefIds) != 0 {
		return errors.New("You cannot specify both RefIds and RefId property")
	}

	return nil
}
