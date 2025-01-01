package testfixtures

import (
	"crypto/ecdsa"
	"crypto/sha256"
	"time"

	"github.com/github/authnd/internal/common/crypto"
	"github.com/github/authnd/internal/common/models"
)

type MobileDeviceKeysWithPrivateKey struct {
	PrivateKey *ecdsa.PrivateKey
	*models.MobileDeviceKey
}

const (
	OauthAccessIdNotBelongingToMobileDeviceKey = 9876000
	UserIdWithoutMobileDevicesKey              = 112233
	UserIdWithMultipleValidDeviceKeys          = 778899 // 3 valid auth records, 1 expired auth record, 1 revoked auth record, 1 valid recovery record, 1 expired recovery record
	UserIdWithMultipleKeys                     = 98700  // 1 valid, 1 expired, 1 revoked
	UserIdForOauthExpirationExtension          = 56003
)

var MobileDeviceKeyReferences = []*MobileDeviceKeysWithPrivateKey{
	ValidMobileDeviceAuthKeyForUserWithMultipleKeys,
	RevokedMobileDeviceAuthKeyForUserWithMultipleKeys,
	ExpiredMobileDeviceAuthKeyForUserWithMultipleKeys,
	ExpiredMobileDeviceAuthKeyForUser7,
	RevokedMobileDeviceAuthKeyForUser8,
	ValidMobileDeviceAuthKeyForUser1,
	ValidMobileDeviceAuthKeyForUser9,
	ValidMobileDeviceAuthKeyForUser10,
	ValidMobileDeviceAuthKeyForUser11,
	ValidMobileDeviceAuthKeyForUser12,
	ValidMobileDeviceAuthKey1,
	ValidMobileDeviceAuthKey2,
	ValidMobileDeviceAuthKey3,
	ValidMobileDeviceRecoveryKey1,
	ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId,
	ValidMobileDeviceAuthKey2ForUser2WithMultipleValidKeysForOauthAccessId,
	ValidMobileDeviceAuthKeyWithOauthAccessId60,
	RevokedMobileDeviceAuthKeyWithOauthAccessId60,
	ValidMobileDeviceRecoveryKeyWithOauthAccessId60,
	RevokedMobileDeviceAuthKeyWithOauthAccessId50,
	ValidMobileDeviceAuthKeyWithOauthAccessId50,
	ValidSecondMobileDeviceAuthKeyWithOauthAccessId50,
}

var (
	unregisteredAuthenticationPrivateKey                    = crypto.MustCreateECDSAPrivateKey()
	ValidUnregisteredMobileDeviceKey                        = crypto.MustGetBase64EncodedPublicKey(unregisteredAuthenticationPrivateKey)
	ValidUnregisteredMobileDeviceKeyVerificationMessage     = `hello_ecdsa`
	validUnregisteredMobileDeviceKeyVerificationMessageHash = sha256.Sum256([]byte(ValidUnregisteredMobileDeviceKeyVerificationMessage))
	ValidUnregisteredMobileDeviceKeyVerificationSignature   = crypto.MustSignMessageHash(unregisteredAuthenticationPrivateKey, validUnregisteredMobileDeviceKeyVerificationMessageHash[:])
)

func GetMobileDeviceKeys() []*models.MobileDeviceKey {
	deviceKeys := []*models.MobileDeviceKey{}
	for _, mdr := range MobileDeviceKeyReferences {
		deviceKeys = append(deviceKeys, mdr.MobileDeviceKey)
	}
	return deviceKeys
}

func createMobileDeviceKeyTestReference(deviceKey *models.MobileDeviceKey) *MobileDeviceKeysWithPrivateKey {
	privateKey := crypto.MustCreateECDSAPrivateKey()
	deviceKey.PublicKey = crypto.MustGetBase64EncodedPublicKey(privateKey)
	deviceKey.PublicKeyFingerprint = crypto.MustGenerateECDSAFingerprint(deviceKey.PublicKey)
	return &MobileDeviceKeysWithPrivateKey{
		PrivateKey:      privateKey,
		MobileDeviceKey: deviceKey,
	}
}

func CreateMobileDeviceKey(id uint64, userId uint64, oauthAccessId uint64, keyType models.DeviceKeyType, createdAt time.Time) *MobileDeviceKeysWithPrivateKey {
	return createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
		ID:               id,
		UserId:           userId,
		OauthAccessId:    oauthAccessId,
		DeviceName:       "user1 iphone2",
		DeviceModel:      "iphone 2s",
		DeviceOs:         "iOS",
		IsHardwareBacked: true,
		Type:             string(keyType),
		ExpiresAt:        models.NullMysqlDateTimeFromTime(createdAt.Add(time.Hour * 24)),
		RevokedAt:        models.NullMysqlDateTimeFromTime(createdAt),
		CreatedAt:        models.NullMysqlDateTimeFromTime(createdAt),
	})
}

var ValidMobileDeviceAuthKeyForUserWithMultipleKeys = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               1,
	UserId:           UserIdWithMultipleKeys,
	OauthAccessId:    1,
	DeviceName:       "user1 iphone1",
	DeviceModel:      "iphone 1s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
},
)

var RevokedMobileDeviceAuthKeyForUserWithMultipleKeys = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               2,
	UserId:           UserIdWithMultipleKeys,
	OauthAccessId:    2,
	DeviceName:       "user1 iphone2",
	DeviceModel:      "iphone 2s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	RevokedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
	UpdatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
})

var ExpiredMobileDeviceAuthKeyForUserWithMultipleKeys = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               3,
	UserId:           UserIdWithMultipleKeys,
	OauthAccessId:    3,
	DeviceName:       "user1 iphone3",
	DeviceModel:      "iphone 3s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(-300 * time.Hour)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
	UpdatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
})

var ExpiredMobileDeviceAuthKeyForUser7 = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               4,
	UserId:           uint64(7),
	OauthAccessId:    7,
	DeviceName:       "some iphone4",
	DeviceModel:      "iphone 4s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(-300 * time.Hour)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
})

var RevokedMobileDeviceAuthKeyForUser8 = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               5,
	UserId:           uint64(8),
	OauthAccessId:    8,
	DeviceName:       "some iphone5",
	DeviceModel:      "iphone 5s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	RevokedAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(-300 * time.Hour)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
})

var ValidMobileDeviceAuthKeyForUser9 = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               6,
	UserId:           uint64(9),
	OauthAccessId:    9,
	DeviceName:       "some iphone6",
	DeviceModel:      "iphone 6s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
	LastUsedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
})

var ValidMobileDeviceAuthKeyForUser10 = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               7,
	UserId:           uint64(10),
	OauthAccessId:    10,
	DeviceName:       "some iphone7",
	DeviceModel:      "iphone 7s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
})

var ValidMobileDeviceAuthKeyForUser11 = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               8,
	UserId:           uint64(11),
	OauthAccessId:    11,
	DeviceName:       "some iphone8",
	DeviceModel:      "iphone 8s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
})

var ValidMobileDeviceAuthKeyForUser12 = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               9,
	UserId:           uint64(12),
	OauthAccessId:    12,
	DeviceName:       "some iphone9",
	DeviceModel:      "iphone 9s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
})

var ValidMobileDeviceAuthKey1 = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               10,
	UserId:           UserIdWithMultipleValidDeviceKeys,
	OauthAccessId:    10,
	DeviceName:       "some iphone10",
	DeviceModel:      "iphone 10s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
})

var ValidMobileDeviceAuthKey2 = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               11,
	UserId:           UserIdWithMultipleValidDeviceKeys,
	OauthAccessId:    11,
	DeviceName:       "some iphone11",
	DeviceModel:      "iphone 11s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
})

var ValidMobileDeviceAuthKey3 = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               12,
	UserId:           UserIdWithMultipleValidDeviceKeys,
	OauthAccessId:    12,
	DeviceName:       "some android12",
	DeviceModel:      "android 12s",
	DeviceOs:         "Android",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
})

var ValidMobileDeviceRecoveryKey1 = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               13,
	UserId:           UserIdWithMultipleValidDeviceKeys,
	OauthAccessId:    13,
	DeviceName:       "some android13",
	DeviceModel:      "android 13s",
	DeviceOs:         "Android",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Recovery),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
})

var ValidMobileDeviceAuthKeyForUser1 = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               14,
	UserId:           uint64(1),
	OauthAccessId:    14,
	DeviceName:       "some iphone",
	DeviceModel:      "iphone 6s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
})

var ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               15,
	UserId:           uint64(2),
	OauthAccessId:    77,
	DeviceName:       "some iphone",
	DeviceModel:      "iphone 6s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
})

var ValidMobileDeviceAuthKey2ForUser2WithMultipleValidKeysForOauthAccessId = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               16,
	UserId:           uint64(2),
	OauthAccessId:    77,
	DeviceName:       "some iphone",
	DeviceModel:      "iphone 6s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(-1 * time.Minute)),
})

var (
	ValidMobileDeviceAuthKeyWithOauthAccessId60ExpiresAtTime = models.NullMysqlDateTimeFromTime(time.Date(2022, 1, 1, 0, 0, 0, 0, time.UTC))
	ValidMobileDeviceAuthKeyWithOauthAccessId60              = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
		ID:               17,
		UserId:           UserIdWithMultipleValidDeviceKeys,
		OauthAccessId:    60,
		DeviceName:       "some android12",
		DeviceModel:      "android 12s",
		DeviceOs:         "Android",
		IsHardwareBacked: true,
		Type:             string(models.DeviceKeyType_Auth),
		ExpiresAt:        ValidMobileDeviceAuthKeyWithOauthAccessId60ExpiresAtTime,
		CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
	})
)

var (
	RevokedMobileDeviceAuthKeyWithOauthAccessId60ExpiresAtTime = models.NullMysqlDateTimeFromTime(time.Date(2022, 1, 1, 0, 0, 0, 0, time.UTC))
	RevokedMobileDeviceAuthKeyWithOauthAccessId60              = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
		ID:               18,
		UserId:           UserIdWithMultipleValidDeviceKeys,
		OauthAccessId:    60,
		DeviceName:       "some android12",
		DeviceModel:      "android 12s",
		DeviceOs:         "Android",
		IsHardwareBacked: true,
		Type:             string(models.DeviceKeyType_Auth),
		ExpiresAt:        RevokedMobileDeviceAuthKeyWithOauthAccessId60ExpiresAtTime,
		RevokedAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(-300 * time.Hour)),
		CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
	})
)

var (
	ValidMobileDeviceRecoveryKeyWithOauthAccessId60ExpiresAtTime = models.NullMysqlDateTimeFromTime(time.Date(2022, 1, 1, 0, 0, 0, 0, time.UTC))
	ValidMobileDeviceRecoveryKeyWithOauthAccessId60              = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
		ID:               19,
		UserId:           UserIdWithMultipleValidDeviceKeys,
		OauthAccessId:    60,
		DeviceName:       "some android12",
		DeviceModel:      "android 12s",
		DeviceOs:         "Android",
		IsHardwareBacked: true,
		Type:             string(models.DeviceKeyType_Recovery),
		ExpiresAt:        ValidMobileDeviceRecoveryKeyWithOauthAccessId60ExpiresAtTime,
		CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
	})
)

var (
	RevokedMobileDeviceAuthKeyWithOauthAccessId50ExpiresAtTime = models.NullMysqlDateTimeFromTime(time.Date(2022, 1, 1, 0, 0, 0, 0, time.UTC))
	RevokedMobileDeviceAuthKeyWithOauthAccessId50              = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
		ID:               20,
		UserId:           UserIdForOauthExpirationExtension,
		OauthAccessId:    50,
		DeviceName:       "some android12",
		DeviceModel:      "android 12s",
		DeviceOs:         "Android",
		IsHardwareBacked: true,
		Type:             string(models.DeviceKeyType_Auth),
		ExpiresAt:        RevokedMobileDeviceAuthKeyWithOauthAccessId50ExpiresAtTime,
		RevokedAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(-300 * time.Hour)),
		CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
	})
)

var (
	ValidMobileDeviceAuthKeyWithOauthAccessId50ExpiresAtTime = models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour).UTC())
	ValidMobileDeviceAuthKeyWithOauthAccessId50              = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
		ID:               21,
		UserId:           UserIdForOauthExpirationExtension,
		OauthAccessId:    50,
		DeviceName:       "some android12",
		DeviceModel:      "android 12s",
		DeviceOs:         "Android",
		IsHardwareBacked: true,
		Type:             string(models.DeviceKeyType_Auth),
		ExpiresAt:        ValidMobileDeviceAuthKeyWithOauthAccessId50ExpiresAtTime,
		CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(2 * time.Minute)),
	})
)

var (
	ValidSecondMobileDeviceAuthKeyWithOauthAccessId50ExpiresAtTime = models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour).UTC())
	ValidSecondMobileDeviceAuthKeyWithOauthAccessId50              = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
		ID:               22,
		UserId:           UserIdForOauthExpirationExtension,
		OauthAccessId:    50,
		DeviceName:       "some android12",
		DeviceModel:      "android 12s",
		DeviceOs:         "Android",
		IsHardwareBacked: true,
		Type:             string(models.DeviceKeyType_Auth),
		ExpiresAt:        ValidSecondMobileDeviceAuthKeyWithOauthAccessId50ExpiresAtTime,
		CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(2 * time.Minute).UTC()),
	})
)

// intentionally not added to MobileDeviceReferences
var MobileDeviceAuthKeyNotInStore = createMobileDeviceKeyTestReference(&models.MobileDeviceKey{
	ID:               101010,
	UserId:           1010,
	OauthAccessId:    10101010,
	DeviceName:       "some iphone101010",
	DeviceModel:      "iphone 10101s",
	DeviceOs:         "iOS",
	IsHardwareBacked: true,
	Type:             string(models.DeviceKeyType_Auth),
	ExpiresAt:        models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	CreatedAt:        models.NullMysqlDateTimeFromTime(time.Now()),
})
