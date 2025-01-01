package store

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	apimodels "github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/mobiledeviceauth"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
	"gopkg.in/guregu/null.v4"
)

// MobileDeviceAuthRequestsStore store for looking up and acting on mobile device auth request records
type MobileDeviceAuthRequestsStore interface {
	// InsertMobileAuthRequest inserts a mobile auth record as long as the user has 0 outstanding mobile auth requests
	InsertMobileAuthRequest(ctx context.Context, record *models.MobileAuthRequest, skipChallenge bool, now time.Time) (apimodels.RequestDeviceAuthResult, null.Int, error)
	// ExpireMobileAuthRequestByID expires a mobile auth requests using the given id.
	ExpireMobileAuthRequestByID(ctx context.Context, id uint64, now time.Time) error
	// FindMobileAuthRequestByIdAndUserId returns a mobile auth requests using the id and user ID
	FindMobileAuthRequestByIdAndUserId(ctx context.Context, id uint64, userId uint64) (*models.MobileAuthRequest, error)
	// FindActiveMobileAuthRequestByUserID returns an active mobile auth requests using the given user ID if found. Returns nil otherwise. Returns an error if more than one record is found.
	FindActiveMobileAuthRequestByUserID(ctx context.Context, userID uint64, now time.Time) (*models.MobileAuthRequest, error)
	// CompleteMobileAuthRequest approves or rejects a given auth request by ID
	CompleteMobileAuthRequest(ctx context.Context, id uint64, completionType apimodels.CompleteDeviceAuthType, now time.Time) (apimodels.CompleteDeviceAuthResult, error)
	// HasExpiredMobileAuthRequestByUserID returns true if there are any expired mobile auth requests for a given user ID
	HasExpiredMobileAuthRequestByUserID(ctx context.Context, userID uint64, now time.Time) (bool, error)
}

func (s *store) InsertMobileAuthRequest(ctx context.Context, request *models.MobileAuthRequest, skipChallenge bool, now time.Time) (apimodels.RequestDeviceAuthResult, null.Int, error) {
	ctx = mysql.WithQueryTableName(ctx, "mobile_auth_requests")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.InsertMobileAuthRequest")
	defer span.End()

	var resp apimodels.RequestDeviceAuthResult
	ex := s.resolver.WriteExecutorForTable("mobile_auth_requests")
	err := ex.WithTransaction(ctx, func(ex mysql.Executor) error {
		// check if there is an outstanding request for this user
		// We want to compare the expiry time of any records found with the created date of the given request
		// It was previously comparing with the expiry time of the given request, but you would never get any existing records back doing that
		requests, err := findActiveAuthRequests(ctx, ex, request.UserId, request.CreatedAt)

		if err != nil {
			resp = apimodels.RequestDeviceAuthResult_Error
			return errors.WithStack(err)
		}
		s.trackFindResult(ctx, ex.ConnectionName(), "create_mobile_auth_record_precondition", timer, err)
		if err != nil {
			if err != sql.ErrNoRows {
				return errors.WithStack(err)
			}
		}

		// if there is an outstanding request, expire the outstanding request, force challenge, and continue
		if len(requests) > 0 {
			// if there is an outstanding request, expire them
			for _, req := range requests {
				err = s.ExpireMobileAuthRequestByID(ctx, req.ID, now)
				if err != nil {
					return errors.WithStack(err)
				}
			}
			// if there was an outstanding request, we never allow skipping the challenge
			skipChallenge = false
		}

		if !skipChallenge {
			challengeNumber, err := mobiledeviceauth.GenerateChallengeNumber()
			if err != nil {
				return err
			}
			request.ChallengeNumber = null.IntFrom(int64(challengeNumber))
		}

		result, err := ex.ExecContext(ctx, `
		INSERT INTO mobile_auth_requests
		(user_id, payload, challenge_number, created_at_utc, expires_at_utc, type, from_ip_address, from_display_name)
		VALUES
		(?, ?, ?, ?, ?, ?, ?, ?)
		`,
			request.UserId,
			request.Payload,
			request.ChallengeNumber,
			request.CreatedAt,
			request.ExpiresAt,
			request.Type,
			request.FromIpAddress,
			request.FromDisplayName,
		)
		s.trackWriteResult(ctx, ex.ConnectionName(), "create_mobile_auth_record", timer, err)
		if err != nil {
			resp = apimodels.RequestDeviceAuthResult_Error
			return errors.WithStack(err)
		}

		id, err := result.LastInsertId()
		if err != nil {
			resp = apimodels.RequestDeviceAuthResult_Error
			return errors.WithStack(err)
		}

		request.ID = uint64(id)
		resp = apimodels.RequestDeviceAuthResult_Success
		return nil
	})

	return resp, request.ChallengeNumber, err
}

func (s *store) ExpireMobileAuthRequestByID(ctx context.Context, id uint64, now time.Time) error {
	ctx = mysql.WithQueryTableName(ctx, "mobile_auth_requests")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.ExpireMobileAuthRequestByID")
	defer span.End()

	ex := s.resolver.WriteExecutorForTable("mobile_auth_requests")
	_, err := ex.ExecContext(ctx, "UPDATE mobile_auth_requests SET expires_at_utc = ? WHERE id = ?", now, id)
	s.trackFindResult(ctx, ex.ConnectionName(), "expire_mobile_auth_request_by_id", timer, err)
	if err != nil {
		return errors.WithStack(err)
	}
	return nil
}

func (s *store) FindMobileAuthRequestByIdAndUserId(ctx context.Context, id uint64, userId uint64) (*models.MobileAuthRequest, error) {
	ctx = mysql.WithQueryTableName(ctx, "mobile_auth_requests")

	// always read from primary when replication lag is high
	ctx = mysql.ContextPrimaryReadFallbackOnLag(ctx)

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindMobileAuthRequestByIdAndUserId")
	defer span.End()

	var mobileAuthRequest models.MobileAuthRequest
	ex := s.resolver.ReadOnlyExecutorForTable("mobile_auth_requests")
	err := ex.GetContext(ctx, &mobileAuthRequest, "SELECT * FROM mobile_auth_requests WHERE id = ? AND user_id = ?", id, userId)
	s.trackFindResult(ctx, ex.ConnectionName(), "find_mobile_auth_request_by_id_and_user_id", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return &mobileAuthRequest, nil
}

func (s *store) CompleteMobileAuthRequest(ctx context.Context, id uint64, completionType apimodels.CompleteDeviceAuthType, now time.Time) (apimodels.CompleteDeviceAuthResult, error) {
	ctx = mysql.WithQueryTableName(ctx, "mobile_auth_requests")

	// always read from primary when replication lag is high
	ctx = mysql.ContextPrimaryReadFallbackOnLag(ctx)

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.CompleteMobileAuthRequest")
	defer span.End()

	var columnName string
	switch {
	case completionType == apimodels.CompleteDeviceAuthType_Approve:
		columnName = `approved_at_utc`
	case completionType == apimodels.CompleteDeviceAuthType_Reject:
		columnName = `rejected_at_utc`
	default:
		return apimodels.CompleteDeviceAuthResult_Error, nil
	}

	query := fmt.Sprintf(`
	UPDATE mobile_auth_requests
	SET %s = ?
	WHERE (
		id = ?
		AND (approved_at_utc IS NULL OR approved_at_utc > ?)
		AND (rejected_at_utc IS NULL OR rejected_at_utc > ?)
		AND (expires_at_utc IS NULL OR expires_at_utc > ?)
	)
	`, columnName)
	ex := s.resolver.WriteExecutorForTable("mobile_auth_requests")
	result, err := ex.ExecContext(ctx, query, models.NullMysqlDateTimeFromTime(now), id, now, now, now)

	s.trackWriteResult(ctx, ex.ConnectionName(), "complete_mobile_auth_request", timer, err)
	if err != nil {
		return apimodels.CompleteDeviceAuthResult_Error, errors.WithStack(err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return apimodels.CompleteDeviceAuthResult_Error, errors.WithStack(err)
	}

	if rowsAffected == 0 {
		var result int64
		query = `
			SELECT 1 FROM mobile_auth_requests
			WHERE id = ?
			LIMIT 1
		`
		err := ex.GetContext(ctx, &result, query, id)
		if err != nil {
			if !errors.Is(err, sql.ErrNoRows) {
				return apimodels.CompleteDeviceAuthResult_Error, errors.WithStack(err)
			}
			return apimodels.CompleteDeviceAuthResult_NotFound, nil
		} else {
			return apimodels.CompleteDeviceAuthResult_NotActive, nil
		}
	} else if rowsAffected > 1 {
		diagnostics.Statter(ctx).Counter("authnd.mobile_auth_complete.more_than_one", nil, 1)
	}

	return apimodels.CompleteDeviceAuthResult_Success, nil
}

func (s *store) FindActiveMobileAuthRequestByUserID(ctx context.Context, userID uint64, now time.Time) (*models.MobileAuthRequest, error) {
	ctx = mysql.WithQueryTableName(ctx, "mobile_auth_requests")

	// always read from primary when replication lag is high
	ctx = mysql.ContextPrimaryReadFallbackOnLag(ctx)

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindActiveMobileAuthRequestByUserID")
	defer span.End()

	ex := s.resolver.ReadOnlyExecutorForTable("mobile_auth_requests")
	mobileAuthRequests, err := findActiveAuthRequests(ctx, ex, userID, models.NullMysqlDateTimeFromTime(now))

	if err == nil {
		if len(mobileAuthRequests) == 0 {
			err = sql.ErrNoRows
		} else if len(mobileAuthRequests) > 1 {
			err = common.StoreErrUnexpectedMultipleResults
		}
	}
	s.trackFindResult(ctx, ex.ConnectionName(), "find_mobile_auth_request_by_user_id", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return &mobileAuthRequests[0], nil
}

func (s *store) HasExpiredMobileAuthRequestByUserID(ctx context.Context, userID uint64, now time.Time) (bool, error) {
	ctx = mysql.WithQueryTableName(ctx, "mobile_auth_requests")

	// always read from primary when replication lag is high
	ctx = mysql.ContextPrimaryReadFallbackOnLag(ctx)

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.HasExpiredMobileAuthRequestByUserID")
	defer span.End()

	ex := s.resolver.ReadOnlyExecutorForTable("mobile_auth_requests")

	expiryDateComparison := models.NullMysqlDateTimeFromTime(now)

	var expired = []int{}

	err := ex.SelectContext(ctx, &expired, `
		SELECT 1 FROM mobile_auth_requests
		WHERE (
			user_id=?
			AND (expires_at_utc < ?)
			AND (approved_at_utc IS NULL)
			AND (rejected_at_utc IS NULL)
		) LIMIT 1`,
		userID,
		expiryDateComparison,
	)

	s.trackFindResult(ctx, ex.ConnectionName(), "has_expired_mobile_auth_request_by_user_id", timer, err)
	if err != nil {
		return false, errors.WithStack(err)
	}
	return len(expired) > 0, nil
}

func findActiveAuthRequests(ctx context.Context, ex mysql.Executor, userId uint64, expiryDateComparison models.NullMysqlDateTime) ([]models.MobileAuthRequest, error) {
	ctx = mysql.WithQueryTableName(ctx, "mobile_auth_requests")

	// always read from primary when replication lag is high
	ctx = mysql.ContextPrimaryReadFallbackOnLag(ctx)

	var requests []models.MobileAuthRequest
	err := ex.SelectContext(ctx, &requests, `
		SELECT * FROM mobile_auth_requests
		WHERE (
			user_id=?
			AND (approved_at_utc IS NULL)
			AND (rejected_at_utc IS NULL)
			AND (expires_at_utc > ?)
		)`,
		userId,
		expiryDateComparison,
	)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	return requests, nil
}

// Not implemented in enterprise store
func (s *enterpriseStore) InsertMobileAuthRequest(ctx context.Context, record *models.MobileAuthRequest, skipChallenge bool, now time.Time) (apimodels.RequestDeviceAuthResult, null.Int, error) {
	return -1, null.Int{}, errors.New("not implemented")
}

func (s *enterpriseStore) ExpireMobileAuthRequestByID(ctx context.Context, id uint64, now time.Time) error {
	return errors.New("not implemented")
}

func (s *enterpriseStore) FindMobileAuthRequestByIdAndUserId(ctx context.Context, id uint64, userId uint64) (*models.MobileAuthRequest, error) {
	return nil, errors.New("not implemented")
}

func (s *enterpriseStore) FindActiveMobileAuthRequestByUserID(ctx context.Context, userID uint64, now time.Time) (*models.MobileAuthRequest, error) {
	return nil, errors.New("not implemented")
}

func (s *enterpriseStore) CompleteMobileAuthRequest(ctx context.Context, id uint64, completionType apimodels.CompleteDeviceAuthType, now time.Time) (apimodels.CompleteDeviceAuthResult, error) {
	return apimodels.CompleteDeviceAuthResult_Error, errors.New("not implemented")
}

func (s *enterpriseStore) HasExpiredMobileAuthRequestByUserID(ctx context.Context, userID uint64, now time.Time) (bool, error) {
	return false, errors.New("not implemented")
}
