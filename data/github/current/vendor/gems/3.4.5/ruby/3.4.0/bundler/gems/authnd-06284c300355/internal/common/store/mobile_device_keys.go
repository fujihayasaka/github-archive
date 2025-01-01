package store

import (
	"context"
	"database/sql"
	"time"

	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/go-stats"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
)

// MobileDeviceKeyStore store for looking up and acting on mobile device key records
type MobileDeviceKeysStore interface {
	// InsertMobileDeviceKey inserts the provided key
	// deviceKey.ID is ignored and if no error is returned, deviceKey.ID will be populated with the new record's ID
	InsertMobileDeviceKey(ctx context.Context, deviceKey *models.MobileDeviceKey, now time.Time) (int64, error)
	// RevokeMobileDeviceKeysByOauthAccessId revokes all device keys for a given oauth access ID.
	RevokeMobileDeviceKeysByOauthAccessId(ctx context.Context, deviceKeyType models.DeviceKeyType, oauthAccessId uint64, now time.Time) (int64, error)
	// FindMobileDeviceKeyByUserIdAndOauthAccessId finds a mobile device key (non expired, non revoked) with the given oauth access Id and user Id.
	FindMobileDeviceKeyByUserIdAndOauthAccessId(ctx context.Context, deviceKeyType models.DeviceKeyType, userId uint64, oauthAccessId uint64, now time.Time) (*models.MobileDeviceKey, error)
	// FindMobileDeviceKeysByUserId finds all mobile device keys (non expired, non revoked) from the given user ID.
	FindMobileDeviceKeysByUserId(ctx context.Context, deviceKeyType models.DeviceKeyType, userId uint64, now time.Time) ([]*models.MobileDeviceKey, error)
	// TouchMobileDeviceKey updates the last_used_at timestamp for the key with the given ID.
	TouchMobileDeviceKey(ctx context.Context, id uint64, now time.Time) error
	// RevokeMobileDeviceKeyById revokes a key with the given ID, if any.
	RevokeMobileDeviceKeyById(ctx context.Context, keyId uint64, now time.Time) error
	// RevokeMobileDeviceKeysByIds revokes all device keys with the given IDs.
	RevokeMobileDeviceKeysByIds(ctx context.Context, keyIds []int64, now time.Time) (int64, error)
	// RevokeMobileDeviceKeysByUserId revokes all device keys for a given user id
	RevokeMobileDeviceKeysByUserId(ctx context.Context, deviceKeyType models.DeviceKeyType, userId uint64, now time.Time) ([]int64, error)
	// RevokeMobileDeviceKeysByOauthAccessIds revokes all device keys for the given oauth access ids
	RevokeMobileDeviceKeysByOauthAccessIds(ctx context.Context, oauthAccessIds []int64, now time.Time) (int64, error)
}

func (s *store) InsertMobileDeviceKey(ctx context.Context, device *models.MobileDeviceKey, now time.Time) (int64, error) {
	ctx = mysql.WithQueryTableName(ctx, "mobile_device_keys")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.InsertMobileDeviceKey")
	defer span.End()

	var id int64
	ex := s.resolver.WriteExecutorForTable("mobile_device_keys")
	err := ex.WithTransaction(ctx, func(ex mysql.Executor) error {
		// first, make sure there are no valid keys with same fingerprint and oauth_access_id.
		var keys []models.MobileDeviceKey
		err := ex.SelectContext(ctx, &keys, `
		SELECT *
		FROM mobile_device_keys
		WHERE (
			public_key_fingerprint=?
			AND (
				oauth_access_id!=? -- only allow duplicate keys for the same oauth access id
				OR
				(
					oauth_access_id=? AND
					(revoked_at_utc IS NULL OR revoked_at_utc > ?) AND
					(expires_at_utc IS NULL OR expires_at_utc > ?)
				) -- and make sure we don't allow the same oauth access id to have multiple, valid keys with the same fingerprint
			)
		)`,
			device.PublicKeyFingerprint,
			device.OauthAccessId,
			device.OauthAccessId,
			// The expires_at and revoked_at datetimes have default precision (0) which truncates to the nearest second, so we need
			// to exclude very recently revoked tokens (i.e. within the last second).
			now.Add(1*time.Second),
			now.Add(1*time.Second),
		)
		s.trackFindResult(ctx, ex.ConnectionName(), "insert_mobile_device_key_precondition", timer, err)
		if err != nil {
			if err != sql.ErrNoRows {
				return errors.WithStack(err)
			}
		}

		if len(keys) > 0 {
			return errors.New("duplicate fingerprint")
		}

		// insert the key
		result, err := ex.ExecContext(ctx, `
		INSERT INTO mobile_device_keys
		(
			user_id,
			oauth_access_id,
			device_name,
			device_model,
			device_os,
			is_hardware_backed,
			type,
			public_key,
			public_key_fingerprint,
			created_at_utc,
			expires_at_utc
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			device.UserId,
			device.OauthAccessId,
			device.DeviceName,
			device.DeviceModel,
			device.DeviceOs,
			device.IsHardwareBacked,
			device.Type,
			device.PublicKey,
			device.PublicKeyFingerprint,
			device.CreatedAt,
			device.ExpiresAt,
		)

		s.trackWriteResult(ctx, ex.ConnectionName(), "insert_mobile_device_key", timer, err)
		if err != nil {
			return errors.WithStack(err)
		}

		id, err = result.LastInsertId()
		if err != nil {
			return errors.WithStack(err)
		}

		return nil
	})

	return id, err
}

func (s *store) RevokeMobileDeviceKeysByOauthAccessId(ctx context.Context, deviceKeyType models.DeviceKeyType, oauthAccessId uint64, now time.Time) (int64, error) {
	ctx = mysql.WithQueryTableName(ctx, "mobile_device_keys")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.RevokeMobileDeviceKeysByOauthAccessId")
	defer span.End()
	bufferUtc := now.Add(-1 * time.Minute)

	ex := s.resolver.WriteExecutorForTable("mobile_device_keys")
	result, err := ex.ExecContext(ctx, `
		UPDATE mobile_device_keys
		SET revoked_at_utc = ?, updated_at_utc = ?
		WHERE (
			type = ?
			AND oauth_access_id = ?
			AND (revoked_at_utc IS NULL OR revoked_at_utc > ?)
			AND (expires_at_utc IS NULL OR expires_at_utc > ?)
		)`,
		models.NullMysqlDateTimeFromTime(now),
		models.NullMysqlDateTimeFromTime(now),
		string(deviceKeyType),
		oauthAccessId,
		bufferUtc,
		bufferUtc,
	)

	s.trackWriteResult(ctx, ex.ConnectionName(), "revoke_mobile_device_keys_by_oauth_access_id", timer, err)
	if err != nil {
		return 0, errors.WithStack(err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return 0, errors.WithStack(err)
	}

	return rowsAffected, nil
}

func (s *store) FindMobileDeviceKeysByUserId(ctx context.Context, deviceKeyType models.DeviceKeyType, userId uint64, now time.Time) ([]*models.MobileDeviceKey, error) {
	ctx = mysql.WithQueryTableName(ctx, "mobile_device_keys")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindMobileDeviceKeysByUserId")
	defer span.End()

	var deviceKeys []*models.MobileDeviceKey
	ex := s.resolver.ReadOnlyExecutorForTable("mobile_device_keys")
	err := ex.SelectContext(ctx, &deviceKeys, `SELECT * FROM mobile_device_keys
		WHERE (
			type = ?
			AND user_id = ?
			AND (revoked_at_utc IS NULL OR revoked_at_utc > ?)
			AND (expires_at_utc IS NULL OR expires_at_utc > ?)
		)`,
		string(deviceKeyType),
		userId,
		now,
		now,
	)
	s.trackFindResult(ctx, ex.ConnectionName(), "find_mobile_device_keys_by_user_id", timer, err)

	if err == nil && len(deviceKeys) == 0 {
		err = sql.ErrNoRows
	}

	if err != nil {
		return nil, errors.WithStack(err)
	}

	return deviceKeys, nil
}

func (s *store) FindMobileDeviceKeyByUserIdAndOauthAccessId(ctx context.Context, deviceKeyType models.DeviceKeyType, userId uint64, oauthAccessId uint64, now time.Time) (*models.MobileDeviceKey, error) {
	ctx = mysql.WithQueryTableName(ctx, "mobile_device_keys")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindMobileDeviceKeyByUserIdAndOauthAccessId")
	defer span.End()

	var deviceKeys []models.MobileDeviceKey
	ex := s.resolver.ReadOnlyExecutorForTable("mobile_device_keys")
	err := ex.SelectContext(ctx, &deviceKeys, `SELECT * FROM mobile_device_keys
		WHERE (
			type = ?
			AND user_id = ?
			AND oauth_access_id = ?
		) ORDER BY created_at_utc DESC, id DESC LIMIT 2`,
		string(deviceKeyType),
		userId,
		oauthAccessId,
	)
	if err == nil {
		switch {
		case len(deviceKeys) == 0:
			err = sql.ErrNoRows
		case isDeviceKeyResultAmbiguous(deviceKeys, now):
			err = common.StoreErrUnexpectedMultipleResults
		case deviceKeys[0].IsRevoked(now):
			err = common.StoreErrDeviceKeyUnexpectedRevoked
		case deviceKeys[0].IsExpired(now):
			err = common.StoreErrDeviceKeyUnexpectedExpired
		}
	}
	s.trackFindResult(ctx, ex.ConnectionName(), "find_mobile_device_key_by_user_id_and_oauth_access_id", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	return &deviceKeys[0], nil
}

func (s *store) TouchMobileDeviceKey(ctx context.Context, id uint64, now time.Time) error {
	ctx = mysql.WithQueryTableName(ctx, "mobile_device_keys")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.TouchMobileDeviceKey")
	defer span.End()

	ex := s.resolver.WriteExecutorForTable("mobile_device_keys")
	_, err := ex.ExecContext(ctx, `
		UPDATE mobile_device_keys
		SET last_used_at_utc = ?
		WHERE id = ?`,
		models.NullMysqlDateTimeFromTime(now),
		id,
	)

	s.trackWriteResult(ctx, ex.ConnectionName(), "touch_mobile_device_key", timer, err)
	if err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func (s *store) RevokeMobileDeviceKeyById(ctx context.Context, id uint64, now time.Time) error {
	ctx = mysql.WithQueryTableName(ctx, "mobile_device_keys")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.RevokeMobileDeviceKeyById")
	defer span.End()

	ex := s.resolver.WriteExecutorForTable("mobile_device_keys")
	_, err := ex.ExecContext(ctx, `
		UPDATE mobile_device_keys
		SET revoked_at_utc = ?, updated_at_utc = ?
		WHERE id = ?`,
		models.NullMysqlDateTimeFromTime(now),
		models.NullMysqlDateTimeFromTime(now),
		id,
	)

	s.trackWriteResult(ctx, ex.ConnectionName(), "revoke_mobile_device_key", timer, err)
	if err != nil {
		return errors.WithStack(err)
	}

	return nil
}

func (s *store) RevokeMobileDeviceKeysByIds(ctx context.Context, keyIds []int64, now time.Time) (int64, error) {
	ctx = mysql.WithQueryTableName(ctx, "mobile_device_keys")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.RevokeMobileDeviceKeysByIds")
	defer span.End()

	query, args, err := sqlx.In(`
		UPDATE mobile_device_keys
		SET revoked_at_utc = ?, updated_at_utc = ?
		WHERE (
			id IN (?)
			AND (revoked_at_utc IS NULL OR revoked_at_utc > ?)
			AND (expires_at_utc IS NULL OR expires_at_utc > ?)
		)`,
		models.NullMysqlDateTimeFromTime(now),
		models.NullMysqlDateTimeFromTime(now),
		keyIds,
		now,
		now,
	)
	if err != nil {
		return 0, errors.WithStack(err)
	}
	ex := s.resolver.WriteExecutorForTable("mobile_device_keys")
	result, err := ex.ExecContext(ctx, query, args...)

	s.trackWriteResult(ctx, ex.ConnectionName(), "revoke_mobile_device_keys_by_ids", timer, err)
	if err != nil {
		return 0, errors.WithStack(err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return 0, errors.WithStack(err)
	}

	return rowsAffected, nil
}

func (s *store) RevokeMobileDeviceKeysByUserId(ctx context.Context, deviceKeyType models.DeviceKeyType, userId uint64, now time.Time) ([]int64, error) {
	ctx = mysql.WithQueryTableName(ctx, "mobile_device_keys")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.RevokeMobileDeviceKeysByUserId")
	defer span.End()

	var oauthAccessIds []int64
	ex := s.resolver.WriteExecutorForTable("mobile_device_keys")
	err := ex.WithTransaction(ctx, func(ex mysql.Executor) error {
		err := ex.SelectContext(ctx, &oauthAccessIds,
			`SELECT oauth_access_id
			FROM mobile_device_keys
			WHERE (
				type = ?
				AND user_id = ?
				AND (revoked_at_utc IS NULL OR revoked_at_utc > ?)
				AND (expires_at_utc IS NULL OR expires_at_utc > ?)
			)`,
			string(deviceKeyType),
			userId,
			now,
			now,
		)

		s.trackFindResult(ctx, ex.ConnectionName(), "revoke_mobile_device_keys_find", timer, err)

		if err != nil {
			return errors.WithStack(err)
		}

		// if the user does not have any mobile_device_keys available to revoke, there is no need to update the database
		if len(oauthAccessIds) == 0 {
			return nil
		}

		_, err = ex.ExecContext(ctx, `
		UPDATE mobile_device_keys
		SET revoked_at_utc = ?, updated_at_utc = ?
		WHERE (
			type = ?
			AND user_id = ?
			AND (revoked_at_utc IS NULL OR revoked_at_utc > ?)
			AND (expires_at_utc IS NULL OR expires_at_utc > ?)
		)`,
			models.NullMysqlDateTimeFromTime(now),
			models.NullMysqlDateTimeFromTime(now),
			string(deviceKeyType),
			userId,
			now,
			now,
		)
		s.trackWriteResult(ctx, ex.ConnectionName(), "revoke_mobile_device_keys", timer, err)

		if err != nil {
			return errors.WithStack(err)
		}

		return nil
	})

	return oauthAccessIds, err
}

func (s *store) RevokeMobileDeviceKeysByOauthAccessIds(ctx context.Context, oauthAccessIds []int64, now time.Time) (int64, error) {
	ctx = mysql.WithQueryTableName(ctx, "mobile_device_keys")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.RevokeMobileDeviceKeysByOauthAccessIds")
	defer span.End()

	query, args, err := sqlx.In(`
		UPDATE mobile_device_keys
		SET revoked_at_utc = ?, updated_at_utc = ?
		WHERE (
			oauth_access_id IN (?)
			AND (revoked_at_utc IS NULL OR revoked_at_utc > ?)
			AND (expires_at_utc IS NULL OR expires_at_utc > ?)
		)`,
		models.NullMysqlDateTimeFromTime(now),
		models.NullMysqlDateTimeFromTime(now),
		oauthAccessIds,
		now,
		now,
	)
	if err != nil {
		return 0, errors.WithStack(err)
	}

	ex := s.resolver.WriteExecutorForTable("mobile_device_keys")
	result, err := ex.ExecContext(ctx, query, args...)
	s.trackWriteResult(ctx, ex.ConnectionName(), "revoke_mobile_device_keys_by_oauth_access_ids", timer, err)
	if err != nil {
		return 0, errors.WithStack(err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return 0, errors.WithStack(err)
	}

	return rowsAffected, nil
}

func isDeviceKeyResultAmbiguous(deviceKeys []models.MobileDeviceKey, now time.Time) bool {
	count := 0
	for _, deviceKey := range deviceKeys {
		if deviceKey.IsValid(now) {
			count += 1
		}
	}
	return count > 1
}

// Not implemented in enterprise store
func (s *enterpriseStore) InsertMobileDeviceKey(ctx context.Context, device *models.MobileDeviceKey, now time.Time) (int64, error) {
	return -1, errors.New("not implemented")
}

func (s *enterpriseStore) RevokeMobileDeviceKeysByOauthAccessId(ctx context.Context, deviceKeyType models.DeviceKeyType, oauthAccessId uint64, now time.Time) (int64, error) {
	return -1, errors.New("not implemented")
}

func (s *enterpriseStore) FindMobileDeviceKeysByUserId(ctx context.Context, deviceKeyType models.DeviceKeyType, userId uint64, now time.Time) ([]*models.MobileDeviceKey, error) {
	return nil, errors.New("not implemented")
}

func (s *enterpriseStore) FindMobileDeviceKeyByUserIdAndOauthAccessId(ctx context.Context, deviceKeyType models.DeviceKeyType, userId uint64, oauthAccessId uint64, now time.Time) (*models.MobileDeviceKey, error) {
	return nil, errors.New("not implemented")
}

func (s *enterpriseStore) TouchMobileDeviceKey(ctx context.Context, id uint64, now time.Time) error {
	return errors.New("not implemented")
}

func (s *enterpriseStore) RevokeMobileDeviceKeyById(ctx context.Context, id uint64, now time.Time) error {
	return errors.New("not implemented")
}

func (s *enterpriseStore) RevokeMobileDeviceKeysByIds(ctx context.Context, keyIds []int64, now time.Time) (int64, error) {
	return 0, errors.New("not implemented")
}

func (s *enterpriseStore) RevokeMobileDeviceKeysByUserId(ctx context.Context, deviceKeyType models.DeviceKeyType, userId uint64, now time.Time) ([]int64, error) {
	return nil, errors.New("not implemented")
}

func (s *enterpriseStore) RevokeMobileDeviceKeysByOauthAccessIds(ctx context.Context, oauthAccessIds []int64, now time.Time) (int64, error) {
	return 0, errors.New("not implemented")
}
