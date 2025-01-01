package common

import "time"

const (
	// DevelopmentEncryptionKey is the default encryption key that is set in development
	DevelopmentEncryptionKey = "BEEFCAFEBEEFCAFEBEEFCAFEBEEFCAFE"

	// GitHub Mobile auth key
	// this is the original lifetime when the key is created. This value is also used to extend the lifetime of the key every time the corresponding oauth access record is accessed (e.g. mobile app usage)
	DeviceAuthKeyLifetime = time.Hour * 720 // 30 days
	// GitHub Mobile recovery key
	DeviceRecoveryKeyLifetime = time.Hour * 8760 // 1 year

	// MobileRequestType* enum values for different mobile auth request types
	MobileRequestTypeTwoFactorLogin         int = 0
	MobileRequestTypeDeviceVerification     int = 1
	MobileRequestTypeTwoFactorPasswordReset int = 2
	MobileRequestTypeTwoFactorSudoChallenge int = 3

	// MobileRequestType*Name are string values for the different mobile auth request enum values
	MobileRequestTypeTwoFactorLoginName         string = "2fa_login"
	MobileRequestTypeDeviceVerificationName     string = "device_verification"
	MobileRequestTypeTwoFactorPasswordResetName string = "2fa_password_reset"
	MobileRequestTypeTwoFactorSudoChallengeName string = "2fa_sudo_challenge"
)
