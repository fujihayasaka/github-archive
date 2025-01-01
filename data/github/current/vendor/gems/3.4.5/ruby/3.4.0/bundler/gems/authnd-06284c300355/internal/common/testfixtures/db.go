package testfixtures

import (
	"encoding/base64"
	"fmt"
	"testing"
	"time"

	"github.com/github/authnd/internal/common/db/schemas"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store"
	commonTesting "github.com/github/authnd/internal/common/testing"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/require"
)

func CreateTestDatabaseStore(t *testing.T, seed bool) store.Store {
	t.Helper()

	dbGetter := commonTesting.NewTestDatabaseGetter(t)

	var dbStore store.Store
	var err error
	if commonTesting.IsProximaMode() {
		dbStore, err = store.NewProximaStore(dbGetter)
		require.NoError(t, err)
	} else {
		dbStore, err = store.NewStore(dbGetter, false)
		require.NoError(t, err)
	}

	authndDB, err := dbGetter.GetDB(schemas.AuthndRW)
	require.NoError(t, err)
	mysql1DB, err := dbGetter.GetDB(schemas.Mysql1RO)
	require.NoError(t, err)
	collabDB, err := dbGetter.GetDB(schemas.CollabRW)
	require.NoError(t, err)
	lodgeDB, err := dbGetter.GetDB(schemas.LodgeRW)
	require.NoError(t, err)

	if seed {
		SeedTables(t, authndDB, mysql1DB, collabDB, lodgeDB)
	} else {
		TruncateTables(t, authndDB, mysql1DB, collabDB, lodgeDB)
	}

	return dbStore
}

func TruncateTables(t *testing.T, authndDB, mysql1DB, collabDB, lodgeDB *sqlx.DB) {
	mysql1Tables := []string{
		"users",
		"businesses",
		"user_sessions",
		"public_keys",
		"oauth_accesses",
		"oauth_applications",
		"organization_credential_authorizations",
		"integrations",
		"integration_installations",
	}

	authndTables := []string{
		"programmatic_access_tokens",
	}

	collabTables := []string{
		"scoped_integration_installations",
		"site_scoped_integration_installations",
	}

	lodgeTables := []string{
		"authentication_tokens",
	}

	if !commonTesting.IsProximaMode() {
		authndTables = append(authndTables,
			"mobile_device_keys",
			"mobile_auth_requests",
		)
	}

	for db, tables := range map[*sqlx.DB][]string{
		mysql1DB: mysql1Tables,
		authndDB: authndTables,
		collabDB: collabTables,
		lodgeDB:  lodgeTables,
	} {
		for _, table := range tables {
			_, err := db.Exec(fmt.Sprintf("TRUNCATE TABLE %s", table))
			require.NoError(t, err)
		}
	}
}

func SeedTables(t *testing.T, authndDB, mysql1DB, collabDB, lodgeDB *sqlx.DB) {
	insert := func(db *sqlx.DB, query string, values ...interface{}) int64 {
		t.Helper()
		result, err := db.Exec(query, values...)
		require.NoError(t, err, "executing '%s' with values '%v", query, values)
		id, err := result.LastInsertId()
		require.NoError(t, err)
		return id
	}

	// Truncate tables at the start, just in case a previous test run left content in them.
	TruncateTables(t, authndDB, mysql1DB, collabDB, lodgeDB)

	insertUser := func(user *models.User) {
		insert(mysql1DB, `INSERT INTO users (id, login, type, bcrypt_auth_token, business_id, token_secret, disabled, suspended_at, spammy) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			user.ID,
			user.Login,
			user.Type,
			user.BcryptAuthToken,
			DefaultBusiness.ID,
			user.TokenSecret,
			user.Disabled,
			user.SuspendedAt,
			user.Spammy,
		)
	}

	for _, user := range Users {
		insertUser(user)
	}

	insertPublicKey := func(key *models.PublicKey) {
		fingerprint := base64.RawStdEncoding.EncodeToString(key.FingerprintSHA256)
		if commonTesting.IsProximaMode() {
			fingerprint += "_" + DefaultBusiness.Shortcode
		}

		insert(mysql1DB,
			"INSERT INTO public_keys (id, `key`, fingerprint_sha256, title, read_only, user_id, repository_id, verified_at, username)"+
				"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
			key.ID,
			key.Key,
			fingerprint,
			"test-key",
			0,
			key.UserID,
			key.RepositoryID,
			key.VerifiedAt,
			"test-name",
		)
	}

	for _, key := range PublicKeys {
		insertPublicKey(key)
	}

	for _, access := range GetOAuthAccesses() {
		insert(mysql1DB, "INSERT INTO oauth_accesses (id, user_id, application_id, raw_data, application_type, hashed_token, token_last_eight, expires_at_timestamp, authorization_id, created_at, last_issued_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
			access.ID,
			access.UserID,
			access.ApplicationID,
			access.RawData,
			access.ApplicationType,
			base64.StdEncoding.EncodeToString(access.HashedToken),
			access.TokenLastEight,
			access.ExpiresAt,
			access.AuthorizationID,
			access.CreatedAt,
			access.LastIssuedAt,
		)
	}

	insertOauthApp := func(app *models.OAuthApplication) {
		insert(mysql1DB, "INSERT INTO oauth_applications (id, name, `key`, user_id, created_at, state) VALUES (?, ?, ?, ?, ?, ?)",
			app.ID,
			app.Name,
			app.Key,
			app.UserID,
			app.CreatedAt,
			app.State,
		)
	}

	for _, app := range OAuthApplications {
		insertOauthApp(app)
	}

	for _, integration := range Integrations {
		insert(mysql1DB, "INSERT INTO integrations (id, owner_id, owner_type, bot_id, name, `key`, created_at, state, user_hidden) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
			integration.ID,
			integration.OwnerID,
			integration.AbstractOwnerType,
			integration.BotID,
			integration.Name,
			integration.Key,
			integration.CreatedAt,
			integration.State,
			integration.UserHidden,
		)
	}

	for _, ii := range IntegrationInstallations {
		insert(mysql1DB, "INSERT INTO integration_installations (id, integration_id, target_id, target_type, user_suspended_by_id, integrator_suspended) VALUES (?, ?, ?, ?, ?, ?)",
			ii.ID,
			ii.IntegrationID,
			ii.TargetID,
			ii.AbstractTargetType,
			ii.UserSuspendedByID,
			ii.IntegratorSuspended,
		)
	}

	for _, organizationSSOSet := range OAuthOrganizationSSOs {
		for _, organizationSSO := range organizationSSOSet {
			insert(mysql1DB, "INSERT INTO organization_credential_authorizations (id, organization_id, credential_id, credential_type, revoked_at, created_at, actor_id, actor_type, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
				organizationSSO.ID,
				organizationSSO.OrganizationID,
				organizationSSO.CredentialID,
				organizationSSO.CredentialType,
				organizationSSO.RevokedAt,
				// fields required by the dotcom schema but unused by authnd
				time.Now(),
				1,
				"User",
				time.Now(),
			)
		}
	}

	for _, userSession := range UserSessions {
		insert(mysql1DB,
			"INSERT INTO user_sessions(`id`, `user_id`, `ip`, `time_zone_name`, `user_agent`, `accessed_at`, `created_at`, `impersonator_id`, `revoked_at`, `expires_at`, `impersonator_session_id`, `sudo_enabled_at`, `hashed_key`, `csrf_token`,"+
				"`revoked_reason`, `secret`, `hashed_private_mode_key`, `hashed_gist_key`, `updated_at`) "+
				"VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
			userSession.ID,
			userSession.UserID,
			userSession.IP,
			userSession.TimeZoneName,
			userSession.UserAgent,
			userSession.AccessedAt,
			time.Now(), // userSession.CreatedAt unused
			userSession.ImpersonatorId,
			userSession.RevokedAt,
			userSession.ExpiresAt,
			userSession.ImpersonatorSessionId,
			userSession.SudoEnabledAt,
			[]byte(fmt.Sprintf("hashedKey-%d", userSession.ID)),
			[]byte(fmt.Sprintf("csrf-token-%d", userSession.ID)),
			userSession.RevokedReason,
			userSession.Secret,
			userSession.HashedPrivateModeKey,
			userSession.HashedGistKey,
			time.Now(), // userSession.UpdatedAt unused
		)
	}

	InsertProgrammaticAccessToken := func(token *models.ProgrammaticAccessToken) {
		id := insert(authndDB,
			"INSERT INTO programmatic_access_tokens (hashed_token, token_suffix, actor_id, actor_type, access_id, issued_at_utc, expires_at_utc, revoked_at_utc, last_event_at_utc, attributes)"+
				"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
			token.HashedToken,
			token.TokenSuffix,
			token.ActorID,
			token.ActorType,
			token.AccessID,
			token.IssuedAt,
			token.ExpiresAt,
			token.RevokedAt,
			token.LastEventAt,
			token.Attributes,
		)

		token.ID = uint64(id)
	}

	for _, token := range ProgrammaticAccessTokens {
		InsertProgrammaticAccessToken(token)
	}

	InsertMobileDeviceKeyFunc := func(deviceKey *models.MobileDeviceKey) {
		id := insert(authndDB, `
			INSERT INTO mobile_device_keys (
				id,
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
				updated_at_utc,
				last_used_at_utc,
				expires_at_utc,
				revoked_at_utc
			)
			VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			deviceKey.ID,
			deviceKey.UserId,
			deviceKey.OauthAccessId,
			deviceKey.DeviceName,
			deviceKey.DeviceModel,
			deviceKey.DeviceOs,
			deviceKey.IsHardwareBacked,
			deviceKey.Type,
			deviceKey.PublicKey,
			deviceKey.PublicKeyFingerprint,
			deviceKey.CreatedAt,
			deviceKey.UpdatedAt,
			deviceKey.LastUsedAt,
			deviceKey.ExpiresAt,
			deviceKey.RevokedAt,
		)

		deviceKey.ID = uint64(id)
	}

	if !commonTesting.IsProximaMode() {
		for _, deviceKey := range GetMobileDeviceKeys() {
			InsertMobileDeviceKeyFunc(deviceKey)
		}
	}

	InsertBusiness := func(business *models.Business) {
		insert(mysql1DB, `INSERT INTO businesses (id, shortcode, slug, spammy) VALUES(?, ?, ?, ?)`,
			business.ID, business.Shortcode, business.Slug, business.Spammy,
		)
	}
	for _, business := range Businesses {
		InsertBusiness(business)
	}

	for _, sii := range ScopedIntegrationInstallations {
		insert(collabDB, `
			INSERT INTO scoped_integration_installations (
				id,
				integration_installation_id,
				created_at,
				updated_at,
				expires_at
			)
			VALUES(?, ?, ?, ?, ?)`,
			sii.ID,
			sii.IntegrationInstallationID,
			sii.CreatedAt,
			sii.UpdatedAt,
			sii.ExpiresAt,
		)
	}

	for _, ssii := range SiteScopedIntegrationInstallations {
		insert(collabDB, `
			INSERT INTO site_scoped_integration_installations (
				id,
				integration_id,
				target_id,
				target_type,
				created_at,
				updated_at,
				expires_at
			)
			VALUES(?, ?, ?, ?, ?, ?, ?)`,
			ssii.ID,
			ssii.IntegrationID,
			ssii.TargetID,
			ssii.AbstractTargetType,
			ssii.CreatedAt,
			ssii.UpdatedAt,
			ssii.ExpiresAt,
		)
	}

	for _, at := range AuthenticationTokens {
		insert(lodgeDB, `
			INSERT INTO authentication_tokens (
				id,
				authenticatable_id,
				authenticatable_type,
				hashed_value,
				created_at,
				updated_at,
				expires_at_timestamp
			)
			VALUES(?, ?, ?, ?, ?, ?, ?)`,
			at.ID,
			at.AuthenticatableID,
			at.AuthenticatableType,
			at.HashedValue,
			at.CreatedAt,
			at.UpdatedAt,
			at.ExpiresAt,
		)
	}

	t.Cleanup(func() {
		TruncateTables(t, authndDB, mysql1DB, collabDB, lodgeDB)
	})
}
