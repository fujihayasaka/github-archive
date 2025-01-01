// Package subscriptionsserver implements the subscriptions server.
package subscriptionsserver

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/twitchtv/twirp"

	"github.com/github/notifyd/internal/api"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/pagination"
	"github.com/github/notifyd/internal/pkg/subscriptions"
	pb "github.com/github/notifyd/proto/services/subscriptions"
)

// Server represents a subscription twirp server
type Server struct {
	service subscriptions.Service
	telem   *telemetry.Provider
}

// NewServer creates a new subscription server.
func NewServer(service subscriptions.Service, telem *telemetry.Provider) *Server {
	return &Server{
		service: service,
		telem:   telem,
	}
}

// Handler returns a handler for the subscriptions server.
func (s *Server) Handler(hooks *twirp.ServerHooks) api.Handler {
	return pb.NewSubscriptionsServer(s, hooks)
}

// BatchReplace first deletes subscriptions by searching through subscriptions that contain ALL of the given custom fields
// and then creates the given subscriptions. If any of the operations fail, the entire transaction will be rolled back.
// The endpoint will only work for one user, if multiple users' subscriptions are provided the endpoint will return an error
func (s *Server) BatchReplace(ctx context.Context, request *pb.BatchReplaceRequest) (*pb.BatchReplaceResponse, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "subscriptionsserver")
	ctx = o11y.CtxSetMethod(ctx, "batchreplace")
	userID := int64(request.UserId)

	if err := batchReplaceValidations(request); err != nil {
		if !errors.Is(err, errNoUserID) {
			ctx = o11y.CtxSetUserID(ctx, userID)
		}
		s.telem.Logger.WithContext(ctx).WithError(err).Error("failed to validate request")
		return nil, errors.Mask(err, "Error validating the request, please check the request contents")
	}

	ctx = o11y.CtxSetUserID(ctx, userID)

	createdMetaIDs, err := s.service.BatchReplace(
		ctx,
		userID,
		pbNewSubscriptionsToMetaSubscriptions(userID, request.NewSubscriptions),
		pbToCustomFields(request.ReplaceByCustomFields),
	)
	if err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Error("failed to batch replace subsriptions")
		return nil, errors.Mask(err, "Failed to batch replace subscriptions")
	}

	return &pb.BatchReplaceResponse{CreatedIds: createdMetaIDs}, nil
}

// Get is a twirp endpoint to get subscriptions
func (s *Server) Get(ctx context.Context, request *pb.GetRequest) (*pb.GetResponse, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "subscriptionsserver")
	ctx = o11y.CtxSetMethod(ctx, "get")
	userID := int64(request.UserId)
	ctx = o11y.CtxSetUserID(ctx, userID)

	if err := getValidation(request); err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Error("failed to validate request")
		return nil, errors.Mask(err, "Error validating the request, please check the request contents")
	}

	customFields := extractCustomFields(request)
	pageRequest := request.GetPage()

	var page pagination.Page
	if pageRequest != nil {
		page = pagination.NewStandardPage(pageRequest.GetCursor(), pageRequest.GetLimit())
	} else {
		// TODO: Replace with FirstPage after we update the monolith
		page = pagination.NewNoLimitPage()
	}

	var subs []*subscriptions.MetaSubscription
	var pages pagination.Pages
	var err error
	if userID > 0 {
		subs, pages, err = s.service.GetSubscriptionsForUser(ctx, userID, customFields, page)
	} else {
		subs, pages, err = s.service.GetSubscriptions(ctx, customFields, page)
	}

	switch {
	case errors.As(err, &pagination.LimitExceededError{}):
		s.telem.Logger.WithContext(ctx).WithError(err).Warn("pagination limit exceeded", kvp.Int64("gh.notifyd.pagination.limit", page.Limit()))
		return nil, errors.Mask(err, err.Error())
	case err != nil:
		s.telem.Logger.WithContext(ctx).WithError(err).Error("failed to get subscriptions")
		return nil, errors.Mask(err, "Failed to get subscriptions")
	}

	pbSubscriptions := make([]*pb.Subscription, len(subs))
	for idx, subscription := range subs {
		customFields := make([]*pb.CustomField, len(subscription.Details.CustomFields))
		for idx, cf := range subscription.Details.CustomFields {
			customFields[idx] = &pb.CustomField{
				Name:  cf.Name,
				Value: cf.Value,
			}
		}
		pbSubscriptions[idx] = &pb.Subscription{
			Id: subscription.ID,
			//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
			UserId:       int32(subscription.UserID),
			CustomFields: customFields,
			Reason:       subscription.Details.Reason,
			CreatedAt:    subscription.CreatedAt.Unix(),
		}
	}

	response := &pb.GetResponse{
		Subscriptions: pbSubscriptions,
	}

	if pages.ReturnNextCursor() {
		response.Pages = &pb.Pages{Next: pages.NextCursor()}
	}

	return response, nil
}

// BatchCreateAndDelete is deprecated. Use BatchReplace instead.
func (s *Server) BatchCreateAndDelete(ctx context.Context, request *pb.BatchCreateAndDeleteRequest) (*pb.BatchCreateAndDeleteResponse, error) {
	_, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	return nil, errors.New("this endpoint is deprecated, use BatchReplace instead")
}

func extractCustomFields(request *pb.GetRequest) []subscriptions.CustomField {
	var fields = make([]subscriptions.CustomField, len(request.FilterByCustomFields))

	for i, field := range request.FilterByCustomFields {
		fields[i] = subscriptions.CustomField{
			Name:  field.Name,
			Value: field.Value,
		}
	}

	return fields
}
