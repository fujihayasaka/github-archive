package testfixtures

import (
	"time"

	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/zson"
	"gopkg.in/guregu/null.v4"
)

func GetOAuthAccesses() []*models.OAuthAccessWithTokenContext {
	oAuthAccesses := []*models.OAuthAccessWithTokenContext{
		MonalisaOAuthAccess,
		MonalisaGistOAuthAccess,
		TrollOAuthAccess,
		UnknownUserOAuthAccess,
		MismatchedEightTokenOAuthAccess,
		ApplicationOauthAccess,
		SuspendedApplicationOauthAccess,
		LegacyApplicationOauthAccess,
		GithubAppOauthAccess,
		UserSuspendedApplicationOAuthAccess,
		ExpiredGithubAppOauthAccess,
		SusUserGithubAppOauthAccess,
		NotExpiredGithubAppOauthAccess,
		ExpiredPersonalAccessTokenOauthAccess,
		EmptyScopesOAuthAccess,
		SusGithubAppOauthAccess,
		SpammyIntegrationUserOwnerOauthAccess,
		SpammyIntegrationBusinessOwnerOauthAccess,
		SpammyOwnerOauthAccess,
	}
	return oAuthAccesses
}

const (
	MonalisaToken              = "ghp_492b79cb96c16e1834b6a2312688ef71b281"
	MonalisaGistToken          = "ghp_1ecc7e327e384e0b8f2004834a2bfe8e00a9"
	MismatchedEightToken       = "ghp_d6ce4c187111ead253992afcf4c6d6a2b627"
	TrollToken                 = "ghp_a9c217401b072dd60dd6f429868bd875356b"
	UnknownUserToken           = "ghp_e94f356138c43f451bd468a0b8a9ed20dea6"
	ExpiredPersonalAccessToken = "ghp_0576f1f97630a57ca953ad3817a6310fc6af"
	EmptyScopesGHPToken        = "ghp_1234f1f97630a57ca953ad3817a6310fc6af"

	OAuthApplicationToken              = "gho_802b79cb96c16e1834b6a2312688ef71b281"
	UserSuspendedOAuthApplicationToken = "gho_572b79cb96c16e1834b6a2312688ef71b281"
	SusOAuthApplicationToken           = "gho_892b79cb96c16e1834b6a2312688ef71b281"
	SpammyGHOToken                     = "gho_893b79cb96c16e1834b6a2312688ef71b281"
	LegacyOauthApplicationToken        = "d3f263735e6193d4bc66c216a86c2f34aad4eb50"

	GitAppOauthToken           = "ghu_992b79cb96c16e1834b6a2312688ef71b281"
	ExpiredGitAppOauthToken    = "ghu_192b79cb96c16e1834b6a2312688ef71b281"
	SusUserGitAppOauthToken    = "ghu_102b79cb96c16e1834b6a2312688ef71b281"
	NotExpiredGitAppOauthToken = "ghu_342b79cb96c16e1834b6a2312688ef71b281"
	SusGitAppOauthToken        = "ghu_f9e08863a0de3b476daafa5f96a0cd30e3d5"
	SpammyUserGHUToken         = "ghu_f9e18863a0de3b476daafa5f96a0cd30e3d5"
	SpammyBusinessGHUToken     = "ghu_f9e28863a0de3b476daafa5f96a0cd30e3d5"

	IntegrationKey               = "v1.f38033c931719580"
	OAuthApplicationKey          = "v1.3dcfcf5927628165"
	SuspendedOAuthApplicationKey = "v1.3dcfcf5927628276"
	SpammyOAuthApplicationKey    = "v1.3dcfcf5927628280"
	SpammyUserIntegrationKey     = "v1.f38033c931719581"
	SpammyBusinessIntegrationKey = "v1.f38033c931719582"
	IntegrationOwnedByOrgKey     = "v1.f38033c931719583"
)

var MonalisaOAuthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:             1,
		UserID:         MonalisaUser.ID,
		HashedToken:    hashToken(MonalisaToken),
		TokenLastEight: lastEight(MonalisaToken),
		CreatedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(-2 * time.Hour).Truncate(time.Second)),
		LastIssuedAt:   models.NullMysqlDateTimeFromTime(time.Now().Add(-time.Hour).Truncate(time.Second)),
		ExpiresAt:      null.IntFrom(time.Now().Add(6 * time.Hour).Unix()),
	},
}

var MonalisaGistOAuthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:             2,
		UserID:         MonalisaUser.ID,
		HashedToken:    hashToken(MonalisaGistToken),
		TokenLastEight: lastEight(MonalisaGistToken),
		RawData:        rawData([]string{"gist"}),
		CreatedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(-time.Hour).Truncate(time.Second)),
	},
}

var MismatchedEightTokenOAuthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:             3,
		UserID:         4, // not a known used -- shouldn't get this far
		HashedToken:    hashToken(MismatchedEightToken),
		TokenLastEight: null.StringFrom("99999999"), // does not match the MismatchedToken[32:]
	},
}

var TrollOAuthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:             4,
		UserID:         TrollUser.ID,
		HashedToken:    hashToken(TrollToken),
		TokenLastEight: lastEight(TrollToken),
	},
}

var UnknownUserOAuthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:             5,
		UserID:         4, // not a known user
		HashedToken:    hashToken(UnknownUserToken),
		TokenLastEight: lastEight(UnknownUserToken),
	},
}

var ApplicationOauthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:              7,
		UserID:          RandomUser.ID,
		HashedToken:     hashToken(OAuthApplicationToken),
		TokenLastEight:  lastEight(OAuthApplicationToken),
		ApplicationID:   DefaultOAuthApplication.ID,
		ApplicationType: null.StringFrom("OauthApplication"),
	},
	ApplicationContext: models.ApplicationContext{
		ApplicationKey:       null.StringFrom(OAuthApplicationKey),
		ApplicationOwnerID:   DefaultOAuthApplication.UserID,
		ApplicationOwnerType: null.StringFrom("User"),
	},
}

var UserSuspendedApplicationOAuthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:              8,
		UserID:          TrollUser.ID,
		HashedToken:     hashToken(UserSuspendedOAuthApplicationToken),
		TokenLastEight:  lastEight(UserSuspendedOAuthApplicationToken),
		ApplicationID:   DefaultOAuthApplication.ID,
		ApplicationType: null.StringFrom("OauthApplication"),
	},
}

var SuspendedApplicationOauthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:              9,
		UserID:          RandomUser.ID,
		HashedToken:     hashToken(SusOAuthApplicationToken),
		TokenLastEight:  lastEight(SusOAuthApplicationToken),
		ApplicationID:   SuspendedOAuthApplication.ID,
		ApplicationType: null.StringFrom("OauthApplication"),
	},
	ApplicationContext: models.ApplicationContext{
		ApplicationSuspended: null.BoolFrom(true),
	},
}

var GithubAppOauthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:              10,
		UserID:          RandomUser.ID,
		HashedToken:     hashToken(GitAppOauthToken),
		TokenLastEight:  lastEight(GitAppOauthToken),
		ApplicationID:   int64(DefaultIntegration.ID),
		ApplicationType: null.StringFrom("Integration"),
	},
	ApplicationContext: models.ApplicationContext{
		ApplicationKey:       null.StringFrom(IntegrationKey),
		ApplicationOwnerID:   null.IntFrom(int64(DefaultIntegration.OwnerID)),
		ApplicationOwnerType: null.StringFrom(DefaultIntegration.AbstractOwnerType),
	},
}

var ExpiredGithubAppOauthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:              11,
		UserID:          RandomUser.ID,
		HashedToken:     hashToken(ExpiredGitAppOauthToken),
		TokenLastEight:  lastEight(ExpiredGitAppOauthToken),
		ApplicationID:   int64(DefaultIntegration.ID),
		ApplicationType: null.StringFrom("Integration"),
		ExpiresAt:       null.IntFrom(time.Now().Unix()),
	},
}

var SusUserGithubAppOauthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:              12,
		UserID:          TrollUser.ID,
		HashedToken:     hashToken(SusUserGitAppOauthToken),
		TokenLastEight:  lastEight(SusUserGitAppOauthToken),
		ApplicationID:   int64(DefaultIntegration.ID),
		ApplicationType: null.StringFrom("Integration"),
	},
}

var NotExpiredGithubAppOauthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:              13,
		UserID:          RandomUser.ID,
		HashedToken:     hashToken(NotExpiredGitAppOauthToken),
		TokenLastEight:  lastEight(NotExpiredGitAppOauthToken),
		ApplicationID:   int64(DefaultIntegration.ID),
		ApplicationType: null.StringFrom("Integration"),
		ExpiresAt:       null.IntFrom(time.Now().Add(100 * time.Hour).Unix()),
	},
	ApplicationContext: models.ApplicationContext{
		ApplicationKey: null.StringFrom(IntegrationKey),
	},
}

var ExpiredPersonalAccessTokenOauthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:             14,
		UserID:         MonalisaUser.ID,
		HashedToken:    hashToken(ExpiredPersonalAccessToken),
		TokenLastEight: lastEight(ExpiredPersonalAccessToken),
		ExpiresAt:      null.IntFrom(time.Now().Unix()),
	},
}

var EmptyScopesOAuthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:             15,
		UserID:         MonalisaUser.ID,
		HashedToken:    hashToken(EmptyScopesGHPToken),
		TokenLastEight: lastEight(EmptyScopesGHPToken),
		RawData:        rawData([]string{}),
	},
}

var SusGithubAppOauthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:              16,
		UserID:          RandomUser.ID,
		HashedToken:     hashToken(SusGitAppOauthToken),
		TokenLastEight:  lastEight(SusGitAppOauthToken),
		ApplicationID:   int64(DefaultIntegration.ID),
		ApplicationType: null.StringFrom("Integration"),
	},
	ApplicationContext: models.ApplicationContext{
		ApplicationSuspended: null.BoolFrom(true),
	},
}

var SpammyIntegrationUserOwnerOauthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:              17,
		UserID:          RandomUser.ID,
		HashedToken:     hashToken(SpammyUserGHUToken),
		TokenLastEight:  lastEight(SpammyUserGHUToken),
		ApplicationID:   int64(SpammyUserIntegration.ID),
		ApplicationType: null.StringFrom("Integration"),
	},
	ApplicationContext: models.ApplicationContext{
		ApplicationKey:         null.StringFrom(SpammyUserIntegrationKey),
		ApplicationOwnerSpammy: null.IntFrom(1),
		ApplicationOwnerID:     null.IntFrom(SpammyUser.ID),
		ApplicationOwnerType:   null.StringFrom("User"),
	},
}

var SpammyIntegrationBusinessOwnerOauthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:              18,
		UserID:          RandomUser.ID,
		HashedToken:     hashToken(SpammyBusinessGHUToken),
		TokenLastEight:  lastEight(SpammyBusinessGHUToken),
		ApplicationID:   int64(SpammyBusinessIntegration.ID),
		ApplicationType: null.StringFrom("Integration"),
	},
	ApplicationContext: models.ApplicationContext{
		ApplicationKey:         null.StringFrom(SpammyBusinessIntegrationKey),
		ApplicationOwnerSpammy: null.IntFrom(1),
		ApplicationOwnerID:     null.IntFrom(SpammyBusiness.ID),
		ApplicationOwnerType:   null.StringFrom("Business"),
	},
}

var LegacyApplicationOauthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:              19,
		UserID:          RandomUser.ID,
		HashedToken:     hashToken(LegacyOauthApplicationToken),
		TokenLastEight:  lastEight(LegacyOauthApplicationToken),
		ApplicationID:   DefaultOAuthApplication.ID,
		ApplicationType: null.StringFrom("OauthApplication"),
	},
	ApplicationContext: models.ApplicationContext{
		ApplicationKey:       null.StringFrom(OAuthApplicationKey),
		ApplicationOwnerID:   null.IntFrom(UserOne.ID),
		ApplicationOwnerType: null.StringFrom("User"),
	},
}

var SpammyOwnerOauthAccess = &models.OAuthAccessWithTokenContext{
	OAuthAccess: models.OAuthAccess{
		ID:              20,
		UserID:          RandomUser.ID,
		HashedToken:     hashToken(SpammyGHOToken),
		TokenLastEight:  lastEight(SpammyGHOToken),
		ApplicationID:   SpammyOAuthApplication.ID,
		ApplicationType: null.StringFrom("OauthApplication"),
	},
	ApplicationContext: models.ApplicationContext{
		ApplicationKey:         null.StringFrom(SpammyOAuthApplicationKey),
		ApplicationOwnerID:     null.IntFrom(SpammyUser.ID),
		ApplicationOwnerSpammy: null.IntFrom(1),
	},
}

func lastEight(token string) null.String {
	return null.StringFrom(token[32:])
}

func rawData(scopes []string) []byte {
	data := models.OAuthAccessData{
		Scopes: scopes,
	}
	bytes, err := zson.Marshal(&data)
	if err != nil {
		panic(err)
	}
	return bytes
}
