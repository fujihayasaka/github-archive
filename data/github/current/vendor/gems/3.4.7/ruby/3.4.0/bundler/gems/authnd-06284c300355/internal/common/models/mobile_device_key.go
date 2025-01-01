package models

import (
	"time"
)

type DeviceKeyType string

const (
	DeviceKeyType_Auth     DeviceKeyType = "auth"
	DeviceKeyType_Recovery DeviceKeyType = "recovery"
)

type MobileDeviceKey struct {
	ID                   uint64            `db:"id"`
	UserId               uint64            `db:"user_id"`
	OauthAccessId        uint64            `db:"oauth_access_id"`
	DeviceName           string            `db:"device_name"`
	DeviceModel          string            `db:"device_model"`
	DeviceOs             string            `db:"device_os"`
	IsHardwareBacked     bool              `db:"is_hardware_backed"`
	PublicKey            string            `db:"public_key"`
	PublicKeyFingerprint string            `db:"public_key_fingerprint"`
	Type                 string            `db:"type"`
	CreatedAt            NullMysqlDateTime `db:"created_at_utc"`
	UpdatedAt            NullMysqlDateTime `db:"updated_at_utc"`
	LastUsedAt           NullMysqlDateTime `db:"last_used_at_utc"`
	ExpiresAt            NullMysqlDateTime `db:"expires_at_utc"`
	RevokedAt            NullMysqlDateTime `db:"revoked_at_utc"`
}

// IsExpired returns true if expires_at is set and before or equal current time (UTC)
func (mdk *MobileDeviceKey) IsExpired(currentTimeUTC time.Time) bool {
	return mdk.ExpiresAt.Valid && !mdk.ExpiresAt.Time.After(currentTimeUTC)
}

// IsRevoked returns true if revoked_at is set and before or equal current time (UTC)
func (mdk *MobileDeviceKey) IsRevoked(currentTimeUTC time.Time) bool {
	return mdk.RevokedAt.Valid && !mdk.RevokedAt.Time.After(currentTimeUTC)
}

// IsValid returns true if the key is in a valid state to be used
func (mdk *MobileDeviceKey) IsValid(currentTimeUTC time.Time) bool {
	return !mdk.IsRevoked(currentTimeUTC) && !mdk.IsExpired(currentTimeUTC)
}

// IsAuthKey returns true if the type of device key is for authentication
func (mdk *MobileDeviceKey) IsAuthKey() bool {
	return mdk.Type == string(DeviceKeyType_Auth)
}

// IsRecoveryKey returns true if the type of device key is for recovery
func (mdk *MobileDeviceKey) IsRecoveryKey() bool {
	return mdk.Type == string(DeviceKeyType_Recovery)
}
