package testfixtures

import (
	"context"
	"database/sql"
	"encoding/base64"
	"sync"
	"testing"
	"time"

	apimodels "github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/mobiledeviceauth"
	"github.com/github/authnd/internal/common/models"
	"gopkg.in/guregu/null.v4"
)

// AuthStore is an authenticator/store implementation containing test fixture data.
// nil values represent when a store's methods are not supported
var AuthStore = &authStore{
	users:                              Users,
	userSessions:                       UserSessions,
	publicKeys:                         PublicKeys,
	oauthAccesses:                      GetOAuthAccesses(),
	publicKeyOrganizationSSOs:          PublicKeyOrganizationSSOs,
	oauthOrganizationSSOs:              OAuthOrganizationSSOs,
	programmaticAccessTokens:           ProgrammaticAccessTokens,
	mobileDeviceKeys:                   GetMobileDeviceKeys(),
	mobileAuthRequests:                 []*models.MobileAuthRequest{},
	integrations:                       Integrations,
	integrationInstallations:           IntegrationInstallations,
	scopedIntegrationInstallations:     ScopedIntegrationInstallations,
	siteScopedIntegrationInstallations: SiteScopedIntegrationInstallations,
	authenticationTokens:               AuthenticationTokens,
}

type authStore struct {
	users                              map[string]*models.User
	userSessions                       map[int64]*models.UserSession
	publicKeys                         []*models.PublicKey
	oauthAccesses                      []*models.OAuthAccessWithTokenContext
	publicKeyOrganizationSSOs          map[int64][]models.OrganizationCredentialAuthorization
	oauthOrganizationSSOs              map[int64][]models.OrganizationCredentialAuthorization
	programmaticAccessTokens           []*models.ProgrammaticAccessToken
	mobileDeviceKeys                   []*models.MobileDeviceKey
	mobileAuthRequests                 []*models.MobileAuthRequest
	mobileDeviceKeysLock               sync.RWMutex
	businesses                         []*models.Business
	integrations                       []*models.Integration
	integrationInstallations           []*models.IntegrationInstallation
	scopedIntegrationInstallations     []*models.ScopedIntegrationInstallation
	siteScopedIntegrationInstallations []*models.SiteScopedIntegrationInstallation
	authenticationTokens               []*models.AuthenticationToken
}

func (a *authStore) FindUserByLogin(ctx context.Context, login string) (*models.User, error) {
	if a.users == nil {
		return nil, common.StoreErrUnsupported
	}
	u, found := a.users[login]
	if !found {
		return nil, sql.ErrNoRows
	}
	return u, nil
}

func (a *authStore) FindPublicKeyBySHA256Fingerprint(ctx context.Context, fingerprint string) (*models.PublicKey, error) {
	if a.publicKeys == nil {
		return nil, common.StoreErrUnsupported
	}

	publicKeys := []*models.PublicKey{}
	for _, pk := range a.publicKeys {
		// fingerprints are base64 encoded when queried from SQL, so we need to encode the
		// seed values to correctly compare them
		encodedFingerprint := base64.RawStdEncoding.EncodeToString(pk.FingerprintSHA256)
		if encodedFingerprint == fingerprint {
			publicKeys = append(publicKeys, pk)
		}
	}
	if len(publicKeys) == 0 {
		return nil, sql.ErrNoRows
	} else if len(publicKeys) > 1 {
		return nil, common.StoreErrUnexpectedMultipleResults
	}

	return publicKeys[0], nil
}

func (a *authStore) FindUserByID(ctx context.Context, userID int64) (*models.User, error) {
	if a.users == nil {
		return nil, common.StoreErrUnsupported
	}
	for _, u := range a.users {
		if u.ID == userID {
			return u, nil
		}
	}
	return nil, sql.ErrNoRows
}

func (a *authStore) FindUserSessionByID(ctx context.Context, userSessionID int64) (*models.UserSession, error) {
	if a.userSessions == nil {
		return nil, common.StoreErrUnsupported
	}
	for _, u := range a.userSessions {
		if u.ID == userSessionID {
			return u, nil
		}
	}
	return nil, sql.ErrNoRows
}

func (a *authStore) FindOAuthAccessByHash(ctx context.Context, token string) (*models.OAuthAccessWithTokenContext, error) {
	if a.oauthAccesses == nil {
		return nil, common.StoreErrUnsupported
	}
	for _, access := range a.oauthAccesses {
		// hashed_tokens are base64 encoded when queried from SQL, so we need to encode the
		// seed values to correctly compare them
		encodedToken := base64.StdEncoding.EncodeToString(access.HashedToken)
		if encodedToken == token {
			return access, nil
		}
	}
	return nil, sql.ErrNoRows
}

func (a *authStore) RevokeProgrammaticAccessTokenByHash(ctx context.Context, hashedToken string) (apimodels.RevokeResult, error) {
	if a.programmaticAccessTokens == nil {
		return apimodels.RevokeResult_Error, common.StoreErrUnsupported
	}

	for _, existingToken := range a.programmaticAccessTokens {
		encodedToken := string(existingToken.HashedToken)
		if encodedToken == hashedToken {
			if existingToken.IsRevoked() {
				return apimodels.RevokeResult_AlreadyRevoked, nil
			} else {
				// NOTE we don't actually revoke the token here. Otherwise this state will persist between tests
				// We have tests for this in the integration tests
				return apimodels.RevokeResult_Success, nil
			}
		}
	}
	return apimodels.RevokeResult_NotFound, sql.ErrNoRows
}

func (a *authStore) RevokeProgrammaticAccessTokenByID(ctx context.Context, id uint64) (apimodels.RevokeResult, error) {
	if a.programmaticAccessTokens == nil {
		return apimodels.RevokeResult_Error, common.StoreErrUnsupported
	}

	for _, existingToken := range a.programmaticAccessTokens {
		if existingToken.ID == id {
			if existingToken.IsRevoked() {
				return apimodels.RevokeResult_AlreadyRevoked, nil
			} else {
				// NOTE we don't actually revoke the token here. Otherwise this state will persist between tests
				// We have tests for this in the integration tests
				return apimodels.RevokeResult_Success, nil
			}
		}
	}
	return apimodels.RevokeResult_NotFound, sql.ErrNoRows
}

func (a *authStore) FindOrganizationSSOByPublicKeyID(ctx context.Context, credentialID int64) ([]models.OrganizationCredentialAuthorization, error) {
	if a.publicKeyOrganizationSSOs == nil {
		return nil, common.StoreErrUnsupported
	}
	sso, found := a.publicKeyOrganizationSSOs[credentialID]
	if !found {
		return []models.OrganizationCredentialAuthorization{}, sql.ErrNoRows
	}

	return sso, nil
}

func (a *authStore) FindOrganizationSSOByOAuthAccessID(ctx context.Context, credentialID int64) ([]models.OrganizationCredentialAuthorization, error) {
	if a.oauthOrganizationSSOs == nil {
		return nil, common.StoreErrUnsupported
	}
	sso, found := a.oauthOrganizationSSOs[credentialID]
	if !found {
		return []models.OrganizationCredentialAuthorization{}, sql.ErrNoRows
	}

	return sso, nil
}

func (a *authStore) FindProgrammaticAccessTokenByHash(ctx context.Context, hashedToken string) (*models.ProgrammaticAccessToken, error) {
	if a.programmaticAccessTokens == nil {
		return nil, common.StoreErrUnsupported
	}
	for _, token := range a.programmaticAccessTokens {
		encodedToken := string(token.HashedToken)
		if encodedToken == hashedToken {
			return token, nil
		}
	}
	return nil, sql.ErrNoRows
}

func (a *authStore) FindProgrammaticAccessTokenByID(ctx context.Context, id uint64) (*models.ProgrammaticAccessToken, error) {
	if a.programmaticAccessTokens == nil {
		return nil, common.StoreErrUnsupported
	}
	for _, token := range a.programmaticAccessTokens {
		if token.ID == id {
			return token, nil
		}
	}
	return nil, sql.ErrNoRows
}

func (a *authStore) FindProgrammaticAccessTokens(ctx context.Context, actorId int64, actorType string, accessId int64) ([]*models.ProgrammaticAccessToken, error) {
	if a.programmaticAccessTokens == nil {
		return nil, common.StoreErrUnsupported
	}

	var prats []*models.ProgrammaticAccessToken
	for _, prat := range a.programmaticAccessTokens {
		if prat.IsExpired(time.Now().UTC()) || prat.IsRevoked() {
			continue
		}
		if int64(prat.ActorID) == actorId && prat.ActorType == actorType && (accessId == 0 || int64(prat.AccessID) == accessId) {
			prats = append(prats, prat)
		}
	}

	return prats, nil
}

func (a *authStore) InsertProgrammaticAccessToken(ctx context.Context, token *models.ProgrammaticAccessToken) error {
	if a.programmaticAccessTokens == nil {
		return common.StoreErrUnsupported
	}
	token.ID = uint64(len(a.programmaticAccessTokens) + 1)
	a.programmaticAccessTokens = append(a.programmaticAccessTokens, token)
	return nil
}

func (a *authStore) FindProgrammaticAccessTokensForRevokedNotification(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
	return nil, common.StoreErrUnsupported
}

func (a *authStore) FindProgrammaticAccessTokensForIssuedNotification(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
	return nil, common.StoreErrUnsupported
}

func (a *authStore) FindProgrammaticAccessTokensForExpiredNotification(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
	return nil, common.StoreErrUnsupported
}

func (a *authStore) FindProgrammaticAccessTokensForExpirationWarningNotification(ctx context.Context, expiresInDays int64, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error) {
	return nil, common.StoreErrUnsupported
}

func (a *authStore) MarkEventForProgrammaticAccessTokens(ctx context.Context, ids []uint64) error {
	return common.StoreErrUnsupported
}

func (a *authStore) InsertMobileDeviceKey(ctx context.Context, deviceKey *models.MobileDeviceKey, now time.Time) (int64, error) {
	a.mobileDeviceKeysLock.Lock()
	defer a.mobileDeviceKeysLock.Unlock()

	if a.mobileDeviceKeys == nil {
		return 0, common.StoreErrUnsupported
	}
	deviceKey.ID = uint64(len(a.mobileDeviceKeys) + 1)
	a.mobileDeviceKeys = append(a.mobileDeviceKeys, deviceKey)
	return int64(deviceKey.ID), nil
}

func (a *authStore) RevokeMobileDeviceKeysByOauthAccessId(ctx context.Context, deviceKeyType models.DeviceKeyType, oauthAccessId uint64, now time.Time) (int64, error) {
	a.mobileDeviceKeysLock.RLock()
	defer a.mobileDeviceKeysLock.RUnlock()

	if a.mobileDeviceKeys == nil {
		return 0, common.StoreErrUnsupported
	}

	for _, deviceKey := range a.mobileDeviceKeys {
		if deviceKey.Type == string(deviceKeyType) && deviceKey.OauthAccessId == oauthAccessId {
			// NOTE we don't actually revoke the token here. Otherwise this state will persist between tests
			// We have tests for this in the integration tests
			return 1, nil
		}
	}

	return 0, nil
}

func (a *authStore) FindMobileDeviceKeyByUserIdAndOauthAccessId(ctx context.Context, deviceKeyType models.DeviceKeyType, userId uint64, oauthAccessId uint64, now time.Time) (*models.MobileDeviceKey, error) {
	a.mobileDeviceKeysLock.RLock()
	defer a.mobileDeviceKeysLock.RUnlock()

	if a.mobileDeviceKeys == nil {
		return nil, common.StoreErrUnsupported
	}

	deviceKeys := []*models.MobileDeviceKey{}
	for _, deviceKey := range a.mobileDeviceKeys {
		if string(deviceKeyType) == deviceKey.Type && userId == deviceKey.UserId && oauthAccessId == deviceKey.OauthAccessId {
			if deviceKey.IsValid(now) {
				deviceKeys = append(deviceKeys, deviceKey)
			}
		}
	}

	if len(deviceKeys) == 0 {
		return nil, sql.ErrNoRows
	} else if len(deviceKeys) > 1 {
		return nil, common.StoreErrUnexpectedMultipleResults
	}
	return deviceKeys[0], nil
}

func (a *authStore) FindMobileDeviceKeysByUserId(ctx context.Context, deviceKeyType models.DeviceKeyType, userId uint64, now time.Time) ([]*models.MobileDeviceKey, error) {
	a.mobileDeviceKeysLock.RLock()
	defer a.mobileDeviceKeysLock.RUnlock()

	var results []*models.MobileDeviceKey
	if a.mobileDeviceKeys == nil {
		return results, common.StoreErrUnsupported
	}

	for _, deviceKey := range a.mobileDeviceKeys {
		if uint64(userId) == deviceKey.UserId {
			if deviceKey.IsAuthKey() && deviceKey.IsValid(now) {
				results = append(results, deviceKey)
			}
		}
	}
	if len(results) == 0 {
		return nil, sql.ErrNoRows
	}

	return results, nil
}

func (a *authStore) TouchMobileDeviceKey(ctx context.Context, id uint64, now time.Time) error {
	a.mobileDeviceKeysLock.RLock()
	defer a.mobileDeviceKeysLock.RUnlock()

	if a.mobileDeviceKeys == nil {
		return common.StoreErrUnsupported
	}

	for _, deviceKey := range a.mobileDeviceKeys {
		if id == deviceKey.ID {
			// don't actually touch the key since that will affect other tests
			return nil
		}
	}
	return nil
}

func (a *authStore) RevokeMobileDeviceKeyById(ctx context.Context, id uint64, now time.Time) error {
	a.mobileDeviceKeysLock.RLock()
	defer a.mobileDeviceKeysLock.RUnlock()

	if a.mobileDeviceKeys == nil {
		return common.StoreErrUnsupported
	}

	for _, deviceKey := range a.mobileDeviceKeys {
		if id == deviceKey.ID {
			// don't actually touch the key since that will affect other tests
			return nil
		}
	}
	return nil
}

func (a *authStore) RevokeMobileDeviceKeysByIds(ctx context.Context, ids []int64, now time.Time) (int64, error) {
	a.mobileDeviceKeysLock.RLock()
	defer a.mobileDeviceKeysLock.RUnlock()

	if a.mobileDeviceKeys == nil {
		return 0, common.StoreErrUnsupported
	}

	rowsAffected := 0
	for _, deviceKey := range a.mobileDeviceKeys {
		if deviceKey.IsExpired(now) || deviceKey.IsRevoked(now) {
			continue
		}
		for _, id := range ids {
			if uint64(id) == deviceKey.ID {
				// don't actually touch the key since that will affect other tests
				rowsAffected++
			}
		}
	}

	return int64(rowsAffected), nil
}

func (a *authStore) RevokeMobileDeviceKeysByUserId(ctx context.Context, deviceKeyType models.DeviceKeyType, userId uint64, now time.Time) ([]int64, error) {
	a.mobileDeviceKeysLock.RLock()
	defer a.mobileDeviceKeysLock.RUnlock()

	var results []int64
	if a.mobileDeviceKeys == nil {
		return results, common.StoreErrUnsupported
	}

	for _, deviceKey := range a.mobileDeviceKeys {
		if deviceKey.IsExpired(now) || deviceKey.IsRevoked(now) {
			continue
		}
		if deviceKey.Type == string(deviceKeyType) && deviceKey.UserId == userId {
			// NOTE we don't actually revoke the token here. Otherwise this state will persist between tests
			// We have tests for this in the integration tests
			results = append(results, int64(deviceKey.OauthAccessId))
		}
	}

	return results, nil
}

func (a *authStore) RevokeMobileDeviceKeysByOauthAccessIds(ctx context.Context, oauthAccessIds []int64, now time.Time) (int64, error) {
	a.mobileDeviceKeysLock.RLock()
	defer a.mobileDeviceKeysLock.RUnlock()

	if a.mobileDeviceKeys == nil {
		return 0, common.StoreErrUnsupported
	}

	rowsAffected := 0
	for _, deviceKey := range a.mobileDeviceKeys {
		if deviceKey.IsExpired(now) || deviceKey.IsRevoked(now) {
			continue
		}
		for _, oauthAccessId := range oauthAccessIds {
			if deviceKey.OauthAccessId == uint64(oauthAccessId) {
				// NOTE we don't actually revoke the token here. Otherwise this state will persist between tests
				// We have tests for this in the integration tests
				rowsAffected++
			}
		}
	}

	return int64(rowsAffected), nil
}

func (a *authStore) InsertMobileAuthRequest(ctx context.Context, request *models.MobileAuthRequest, skipChallenge bool, now time.Time) (apimodels.RequestDeviceAuthResult, null.Int, error) {
	a.mobileDeviceKeysLock.RLock()
	defer a.mobileDeviceKeysLock.RUnlock()

	if a.mobileDeviceKeys == nil || a.mobileAuthRequests == nil {
		return apimodels.RequestDeviceAuthResult_Error, null.Int{}, common.StoreErrUnsupported
	}

	var activeRequestCount int
	for _, mobileRequest := range a.mobileAuthRequests {
		if request.UserId == mobileRequest.UserId && mobileRequest.IsActive(request.CreatedAt.Time) {
			activeRequestCount++
		}
	}

	if activeRequestCount > 0 {
		skipChallenge = false
	}

	request.ID = uint64(len(a.mobileAuthRequests) + 1)
	a.mobileAuthRequests = append(a.mobileAuthRequests, request)

	if !skipChallenge {
		challengeNumber, err := mobiledeviceauth.GenerateChallengeNumber()
		if err != nil {
			return apimodels.RequestDeviceAuthResult_Error, null.Int{}, err
		}
		request.ChallengeNumber = null.IntFrom(int64(challengeNumber))
	}
	return apimodels.RequestDeviceAuthResult_Success, request.ChallengeNumber, nil
}

func (a *authStore) ExpireMobileAuthRequestByID(ctx context.Context, id uint64, now time.Time) error {
	if a.mobileAuthRequests == nil {
		return common.StoreErrUnsupported
	}

	for _, r := range a.mobileAuthRequests {
		if r.ID == id {
			// NOTE we don't actually update the device here. Otherwise this state will persist between tests
			// We have tests for this in the integration tests
			return nil
		}
	}

	return sql.ErrNoRows
}

func (a *authStore) FindMobileAuthRequestByIdAndUserId(ctx context.Context, id uint64, userId uint64) (*models.MobileAuthRequest, error) {
	if a.mobileAuthRequests == nil {
		return nil, common.StoreErrUnsupported
	}

	for _, r := range a.mobileAuthRequests {
		if r.ID == id && r.UserId == userId {
			return r, nil
		}
	}

	return nil, sql.ErrNoRows
}

func (a *authStore) FindActiveMobileAuthRequestByUserID(ctx context.Context, userID uint64, now time.Time) (*models.MobileAuthRequest, error) {
	if a.mobileAuthRequests == nil {
		return nil, common.StoreErrUnsupported
	}

	mobileAuthRequestResults := []*models.MobileAuthRequest{}
	for _, r := range a.mobileAuthRequests {
		if r.UserId == userID && r.IsActive(now) {
			mobileAuthRequestResults = append(mobileAuthRequestResults, r)
		}
	}
	if len(mobileAuthRequestResults) == 0 {
		return nil, sql.ErrNoRows
	} else if len(mobileAuthRequestResults) > 1 {
		return nil, common.StoreErrUnexpectedMultipleResults
	}

	return mobileAuthRequestResults[0], nil
}

func (a *authStore) CompleteMobileAuthRequest(ctx context.Context, id uint64, completionType apimodels.CompleteDeviceAuthType, now time.Time) (apimodels.CompleteDeviceAuthResult, error) {
	a.mobileDeviceKeysLock.RLock()
	defer a.mobileDeviceKeysLock.RUnlock()

	if a.mobileDeviceKeys == nil {
		return apimodels.CompleteDeviceAuthResult_Error, common.StoreErrUnsupported
	}

	for _, r := range a.mobileAuthRequests {
		if r.ID == id {
			if r.IsActive(now) {
				return apimodels.CompleteDeviceAuthResult_Success, nil
			}
			return apimodels.CompleteDeviceAuthResult_NotActive, nil
		}
	}

	return apimodels.CompleteDeviceAuthResult_NotFound, nil
}

func (a *authStore) HasExpiredMobileAuthRequestByUserID(ctx context.Context, userID uint64, now time.Time) (bool, error) {
	if a.mobileAuthRequests == nil {
		return false, common.StoreErrUnsupported
	}

	for _, r := range a.mobileAuthRequests {
		if r.UserId == userID && r.IsExpired(now) && !r.IsApproved(now) && !r.IsRejected(now) {
			return true, nil
		}
	}

	return false, nil
}

// TODO techdebt: this method needs some love. Very fragile, makes several assumptions about seed data
func (a *authStore) SeedMobileAuthRequests(t *testing.T, mobileAuthRequests []*models.MobileAuthRequest) {
	// ensure we reset the auth stores mobile auth request state between each test
	t.Cleanup(func() {
		a.ResetMobileAuthRequest()
	})

	for index, mobileAuthRequest := range mobileAuthRequests {
		mobileAuthRequest.ID = uint64(len(a.mobileAuthRequests) + index + 1)
		a.mobileAuthRequests = append(a.mobileAuthRequests, mobileAuthRequest)
	}
}

func (a *authStore) ResetMobileAuthRequest() {
	a.mobileAuthRequests = []*models.MobileAuthRequest{}
}

func (a *authStore) FindBusinessBySlug(ctx context.Context, slug string) (*models.Business, error) {
	if a.businesses == nil {
		return nil, common.StoreErrUnsupported
	}

	for _, b := range a.businesses {
		if b.Slug == slug {
			return b, nil
		}
	}
	return nil, sql.ErrNoRows
}

func (a *authStore) BusinessIdForProgrammaticAccessToken(ctx context.Context, tokenId uint64) (uint64, error) {
	if a.businesses == nil {
		return 0, common.StoreErrUnsupported
	}

	// TODO: make more robust if possible, once we start using multiple test tenants.
	// The problem is that business_id isn't stored on the user model, only in the db, so
	// we can't access it in these tests, only rely on the fact that for testing
	// we only have one tenant/business that everything is scoped to in Proxima mode
	return uint64(a.businesses[0].ID), nil
}

func (a *authStore) FindIntegrationByID(ctx context.Context, id uint64) (*models.IntegrationWithPreciseOwner, error) {
	if a.integrations == nil {
		return nil, common.StoreErrUnsupported
	}

	for _, i := range a.integrations {
		preciseType := "User"
		if i.AbstractOwnerType == "User" {
			u, err := a.FindUserByID(ctx, int64(i.OwnerID))
			if err != nil {
				return nil, err
			}
			preciseType = u.Type
		}
		if i.ID == id {
			return &models.IntegrationWithPreciseOwner{Integration: *i, PreciseOwnerType: preciseType}, nil
		}
	}

	return nil, sql.ErrNoRows
}

func (a *authStore) FindIntegrationInstallationByID(ctx context.Context, id uint64) (*models.IntegrationInstallationWithPreciseTargetType, error) {
	if a.integrationInstallations == nil {
		return nil, common.StoreErrUnsupported
	}

	for _, i := range a.integrationInstallations {
		if i.ID == id {
			preciseType := "User"
			if i.AbstractTargetType == "User" {
				u, err := a.FindUserByID(ctx, int64(i.TargetID))
				if err != nil {
					return nil, err
				}
				preciseType = u.Type
			}

			return &models.IntegrationInstallationWithPreciseTargetType{IntegrationInstallation: *i, PreciseTargetType: preciseType}, nil
		}
	}

	return nil, sql.ErrNoRows
}

func (a *authStore) FindScopedIntegrationInstallationByID(ctx context.Context, id uint64) (*models.ScopedIntegrationInstallation, error) {
	if a.scopedIntegrationInstallations == nil {
		return nil, common.StoreErrUnsupported
	}

	for _, i := range a.scopedIntegrationInstallations {
		if i.ID == id {
			return i, nil
		}
	}

	return nil, sql.ErrNoRows
}

func (a *authStore) FindSiteScopedIntegrationInstallationByID(ctx context.Context, id uint64) (*models.SiteScopedIntegrationInstallationWithPreciseTargetType, error) {
	if a.siteScopedIntegrationInstallations == nil {
		return nil, common.StoreErrUnsupported
	}

	for _, i := range a.siteScopedIntegrationInstallations {
		preciseType := "User"
		if i.AbstractTargetType == "User" {
			u, err := a.FindUserByID(ctx, int64(i.TargetID))
			if err != nil {
				return nil, err
			}
			preciseType = u.Type
		}
		if i.ID == id {
			return &models.SiteScopedIntegrationInstallationWithPreciseTargetType{SiteScopedIntegrationInstallation: *i, PreciseTargetType: preciseType}, nil
		}
	}

	return nil, sql.ErrNoRows
}

func (a *authStore) FindAuthenticationTokenByHash(ctx context.Context, hash string) (*models.AuthenticationToken, error) {
	if a.authenticationTokens == nil {
		return nil, common.StoreErrUnsupported
	}

	for _, t := range a.authenticationTokens {
		if t.HashedValue == hash {
			return t, nil
		}
	}

	return nil, sql.ErrNoRows
}
