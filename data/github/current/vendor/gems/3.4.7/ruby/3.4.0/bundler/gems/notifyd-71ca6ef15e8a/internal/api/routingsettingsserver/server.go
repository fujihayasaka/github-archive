// Package routingsettingsserver implements the routing settings server.
package routingsettingsserver

import (
	"context"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	gostats "github.com/github/go-stats"
	"github.com/twitchtv/twirp"

	"github.com/github/notifyd/internal/api"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/pagination"
	"github.com/github/notifyd/internal/pkg/routing"
	pb "github.com/github/notifyd/proto/services/routingsettings"
)

// Server represents a routing settings twirp server
type Server struct {
	service routing.SettingsService
	telem   *telemetry.Provider
	statter gostats.Client
	clock   clockpkg.Clock
}

// NewServer returns a server configured with the given database client
func NewServer(service routing.SettingsService, telem *telemetry.Provider, statter gostats.Client, clock clockpkg.Clock) *Server {
	return &Server{
		service: service,
		telem:   telem,
		statter: statter,
		clock:   clock,
	}
}

// Handler builds a new handler for the Twirp server API.
func (s Server) Handler(hooks *twirp.ServerHooks) api.Handler {
	return pb.NewRoutingSettingsServer(s, hooks)
}

// Get implements the service interface
func (s Server) Get(ctx context.Context, request *pb.GetRequest) (*pb.GetResponse, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	userID := int64(request.UserId)
	ctx = o11y.CtxSetPackage(ctx, "routingsettingsserver")
	ctx = o11y.CtxSetMethod(ctx, "get")
	ctx = o11y.CtxSetUserID(ctx, userID)

	var userIDs []int64
	if userID > 0 {
		userIDs = append(userIDs, userID)
	}

	return s.processGetRequest(ctx, userIDs, request.FilterByCustomFields, request.GetPage())
}

// BatchGet implements the service interface
func (s Server) BatchGet(ctx context.Context, request *pb.BatchGetRequest) (*pb.GetResponse, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "routingsettingsserver")
	ctx = o11y.CtxSetMethod(ctx, "batchget")

	var users []int64
	for _, u := range request.UserIds {
		users = append(users, int64(u))
	}
	return s.processGetRequest(ctx, users, request.FilterByCustomFields, request.GetPage())
}

func (s Server) processGetRequest(ctx context.Context, userIDs []int64, fields []*pb.CustomField, pageRequest *pb.Page) (*pb.GetResponse, error) {
	if err := validateGetRequest(userIDs); err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Error("failed to validate request")
		return nil, errors.Mask(err, "Failed to get routing settings")
	}

	// convert custom fields from pb to dto format
	customFields := make([]routing.CustomField, len(fields))
	for i, field := range fields {
		customFields[i] = routing.CustomField{
			Name: field.Name, Value: field.Value,
		}
	}

	var page pagination.Page
	if pageRequest != nil {
		page = pagination.NewStandardPage(pageRequest.GetCursor(), pageRequest.GetLimit())
	} else {
		// TODO: Replace with FirstPage after we update the monolith
		page = pagination.NewNoLimitPage()
	}

	var settings []*routing.MetaSetting
	var pages pagination.Pages
	var err error
	if len(userIDs) > 0 {
		settings, pages, err = s.service.GetSettingsForUsers(ctx, userIDs, customFields, page)
	} else {
		settings, pages, err = s.service.GetSettings(ctx, customFields, page)
	}
	switch {
	case errors.As(err, &pagination.LimitExceededError{}):
		s.telem.Logger.WithContext(ctx).WithError(err).Warn("pagination limit exceeded", kvp.Int64("gh.notifyd.pagination.limit", page.Limit()))
		return nil, errors.Mask(err, err.Error())
	case err != nil:
		s.telem.Logger.WithContext(ctx).WithError(err).Error("failed to get routing settings")
		return nil, errors.Mask(err, "Failed to get routing settings")
	}

	var rs []*pb.RoutingSetting
	for _, setting := range settings {
		rs = append(rs, routingSettingToPB(setting))
	}

	response := &pb.GetResponse{RoutingSetting: rs}
	if pages.ReturnNextCursor() {
		response.Pages = &pb.Pages{Next: pages.NextCursor()}
	}

	return response, nil
}

func validateGetRequest(userIDs []int64) error {
	// validate we don't allow user ID <= 0
	for _, id := range userIDs {
		if id <= 0 {
			return errors.New("user ID can't be 0 or less")
		}
	}
	return nil
}

// BatchCreateAndDelete implements the service interface
func (s Server) BatchCreateAndDelete(ctx context.Context, request *pb.BatchCreateAndDeleteRequest) (*pb.BatchCreateAndDeleteResponse, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "routingsettingsserver")
	ctx = o11y.CtxSetMethod(ctx, "batchcreateanddelete")

	ts := mysql.NewTimestamps(s.clock)
	toCreate := pbToSettingsToCreate(request, ts)
	toDelete := pbToIDsToDelete(request)

	created, err := s.service.BatchCreateAndDelete(ctx, toCreate, toDelete)
	if err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Error("failed to create and delete routing settings")
		return nil, errors.Mask(err, "Failed to create and delete routing settings")
	}

	ids := make([]int64, 0, len(created))
	for _, routingSettings := range created {
		ids = append(ids, routingSettings.ID)
	}

	return &pb.BatchCreateAndDeleteResponse{CreatedIds: ids}, nil
}

// BatchReplace existing settings, by providing a query to delete existing
// settings a sequence of new settings to create.
// It has some constraints:
//   - The settings can only be replaced for a single userID, indicated in the
//     request and in each of the new settings to create (the userID must
//     match).
//   - The settings to replace are restricted what can be currently expressed by
//     custom fields. When that's not enough BatchCreateAndDelete can be used
//     instead, without transactional guarantees.
//
// BatchReplace can also be used to create new settings (by providing empty
// custom fields) or to delete existing ones (by providing an empty sequence of
// new settings).
func (s Server) BatchReplace(ctx context.Context, request *pb.BatchReplaceRequest) (*pb.BatchReplaceResponse, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "routingsettingsserver")
	ctx = o11y.CtxSetMethod(ctx, "batchreplace")
	userID := int64(request.UserId)

	if err := batchReplaceValidations(request); err != nil {
		if !errors.Is(err, errNoUserID) {
			ctx = o11y.CtxSetUserID(ctx, userID)
		}
		s.telem.Logger.
			WithContext(ctx).
			WithError(err).
			Error("failed to validate batch replace request")

		return nil, errors.Wrap(err, "validation")
	}

	ids, err := s.service.BatchReplace(
		ctx,
		userID,
		pbNewRoutingSettingToMetaSettings(userID, request.Settings),
		pbToCustomFields(request.ReplaceByCustomFields),
	)

	if err != nil {
		errorWithDetails := errors.Wrap(err, "Failed to batch replace routing settings")
		return nil, errors.Mask(errorWithDetails, "Failed to batch replace settings")
	}

	return &pb.BatchReplaceResponse{CreatedIds: ids}, nil
}
