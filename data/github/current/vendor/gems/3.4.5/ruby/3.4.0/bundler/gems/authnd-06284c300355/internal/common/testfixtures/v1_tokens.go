package testfixtures

import (
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	apimodels "github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/tokens/fgpat"
)

var ProgrammaticAccessTokens = []*models.ProgrammaticAccessToken{
	// legacy v1 tokens
	MonalisaLegacyProgrammaticAccessToken,
	MonalisaLegacyProgrammaticAccessTokenExtraAttributes,
	ExpiredLegacyProgrammaticAccessToken,
	RevokedLegacyProgrammaticAccessToken,
	FutureExpiredLegacyProgrammaticAccessToken,
	MissingActorIDLegacyProgrammaticAccessToken,
	MissingActorTypeLegacyProgrammaticAccessToken,
	MissingAccessIDLegacyProgrammaticAccessToken,
	MismatchActorIDLegacyProgrammaticAccessToken,
	MismatchActorTypeLegacyProgrammaticAccessToken,
	MismatchAccessIDLegacyProgrammaticAccessToken,

	FindCredentialsLegacyAccess1NoCat,
	FindCredentialsLegacyAccess1WithCat,
	FindCredentialsLegacyAccess2NoCat,
	FindCredentialsLegacyAccess2WithCat,
	FindCredentialsLegacyAccess2Expired,
	FindCredentialsLegacyAccess2Revoked,

	// v1 tokens
	MonalisaProgrammaticAccessToken,
	MonalisaProgrammaticAccessTokenExtraAttributes,
	ExpiredProgrammaticAccessToken,
	RevokedProgrammaticAccessToken,
	FutureExpiredProgrammaticAccessToken,
	MissingActorIDProgrammaticAccessToken,
	MissingActorTypeProgrammaticAccessToken,
	MissingAccessIDProgrammaticAccessToken,
	MismatchActorIDProgrammaticAccessToken,
	MismatchActorTypeProgrammaticAccessToken,
	MismatchAccessIDProgrammaticAccessToken,
	ExpiringInTwentyThreeHoursProgrammaticAccessToken,
	ExpiringIn6DaysProgrammaticAccessToken,

	FindCredentialsAccess1NoCat,
	FindCredentialsAccess1WithCat,
	FindCredentialsAccess2NoCat,
	FindCredentialsAccess2WithCat,

	NilUserProgrammaticAccessToken,
	SuspendedUserProgrammaticAccessToken,
}

var (
	MonalisaV0TokenPlainText = mustParseToken("gh0_f8qT8wbEFXUwkqc8cgCmjYwakA45oc2Qz7T3") // fully deprecated

	FutureExpirationTime = time.Now().Add(2 * time.Hour).UTC()
)

const (
	BoolTrueAttributeId  = "foo.bool.true"
	BoolFalseAttributeId = "foo.bool.false"
	DoubleAttributeId    = "foo.double"
)

var MonalisaProgrammaticAccessToken, MonalisaToken1 = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:    3,
	ActorID:     MonalisaUser.ID,
	MintTokenID: 1201,
	IssuedAt:    OneHundredHoursAgo,
	ExpiresAt:   SixDaysFromNow,
})

var MonalisaProgrammaticAccessTokenExtraAttributes, MonalisaTokenExtraAttributes = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:    3,
	ActorID:     MonalisaUser.ID,
	MintTokenID: 1202,
	IssuedAt:    time.Now().UTC(),
	ExtraCommonAttrs: []*pb.Attribute{
		pb.NewBoolAttribute(BoolTrueAttributeId, true),
		pb.NewBoolAttribute(BoolFalseAttributeId, false),
		pb.NewDoubleAttribute(DoubleAttributeId, 1.1),
	},
})

var ExpiredProgrammaticAccessToken, ExpiredToken = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:    3,
	ActorID:     MonalisaUser.ID,
	MintTokenID: 1203,
	IssuedAt:    Y2K,
	ExpiresAt:   Y2KPlus,
	LastEventAt: Y2K,
})

var RevokedProgrammaticAccessToken, RevokedToken = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:    3,
	ActorID:     MonalisaUser.ID,
	MintTokenID: 1204,
	IssuedAt:    Y2K,
	RevokedAt:   Y2KPlus,
	LastEventAt: Y2K,
})

var NotFoundToken = generateToken(MonalisaUser.ID)

var FutureExpiredProgrammaticAccessToken, FutureExpiredToken = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:    3,
	ActorID:     MonalisaUser.ID,
	MintTokenID: 1205,
	IssuedAt:    time.Now().UTC(),
	ExpiresAt:   FutureExpirationTime,
})

var MissingActorIDProgrammaticAccessToken, MissingActorIDToken = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:            3,
	ActorID:             MonalisaUser.ID,
	MintTokenID:         1206,
	IssuedAt:            time.Now().UTC(),
	OverrideCommonAtrrs: true,
	ExtraCommonAttrs: []*pb.Attribute{
		pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
		pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
	},
})

var MissingActorTypeProgrammaticAccessToken, MissingActorTypeToken = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:            3,
	ActorID:             MonalisaUser.ID,
	MintTokenID:         1207,
	IssuedAt:            time.Now().UTC(),
	OverrideCommonAtrrs: true,
	ExtraCommonAttrs: []*pb.Attribute{
		pb.NewInt64Attribute(client.ActorIDAttribute, MonalisaUser.ID),
		pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
	},
})

var MissingAccessIDProgrammaticAccessToken, MissingAccessIDToken = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:            3,
	ActorID:             MonalisaUser.ID,
	MintTokenID:         1208,
	IssuedAt:            time.Now().UTC(),
	OverrideCommonAtrrs: true,
	ExtraCommonAttrs: []*pb.Attribute{
		pb.NewInt64Attribute(client.ActorIDAttribute, MonalisaUser.ID),
		pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
	},
})

var MismatchActorIDProgrammaticAccessToken, MismatchActorIDToken = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:            3,
	ActorID:             MonalisaUser.ID,
	MintTokenID:         1209,
	IssuedAt:            time.Now().UTC(),
	OverrideCommonAtrrs: true,
	ExtraCommonAttrs: []*pb.Attribute{
		pb.NewInt64Attribute(client.ActorIDAttribute, 1337),
		pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
		pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
	},
})

var MismatchActorTypeProgrammaticAccessToken, MismatchActorTypeToken = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:            3,
	ActorID:             MonalisaUser.ID,
	MintTokenID:         1210,
	IssuedAt:            time.Now().UTC(),
	OverrideCommonAtrrs: true,
	ExtraCommonAttrs: []*pb.Attribute{
		pb.NewInt64Attribute(client.ActorIDAttribute, MonalisaUser.ID),
		pb.NewStringAttribute(client.ActorTypeAttribute, "LizardPerson"),
		pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
	},
})

var MismatchAccessIDProgrammaticAccessToken, MismatchAccessIDToken = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:            3,
	ActorID:             MonalisaUser.ID,
	MintTokenID:         1211,
	IssuedAt:            time.Now().UTC(),
	OverrideCommonAtrrs: true,
	ExtraCommonAttrs: []*pb.Attribute{
		pb.NewInt64Attribute(client.ActorIDAttribute, MonalisaUser.ID),
		pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
		pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 1337),
	},
})

var ExpiringInTwentyThreeHoursProgrammaticAccessToken, _ = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:    3,
	ActorID:     MonalisaUser.ID,
	MintTokenID: 1210,
	IssuedAt:    OneHundredHoursAgo,
	LastEventAt: OneHundredHoursAgo,
	ExpiresAt:   TwentyThreeHoursFromNow,
})

var ExpiringIn6DaysProgrammaticAccessToken, _ = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:    3,
	ActorID:     MonalisaUser.ID,
	MintTokenID: 1211,
	IssuedAt:    OneHundredHoursAgo,
	LastEventAt: OneHundredHoursAgo,
	ExpiresAt:   SixDaysFromNow,
})

var FindCredentialsAccess1NoCat, _ = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:    1,
	ActorID:     FindCredentialsUser.ID,
	MintTokenID: 1300,
	IssuedAt:    time.Now().UTC(),
})

var FindCredentialsAccess1WithCat, _ = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:    1,
	ActorID:     FindCredentialsUser.ID,
	MintTokenID: 1301,
	IssuedAt:    time.Now().UTC(),
	ExpiresAt:   time.Date(2999, 1, 11, 10, 1, 2, 0, time.UTC),
	ExtraCommonAttrs: []*pb.Attribute{
		pb.NewStringAttribute("cat", "tabby"),
	},
})

var FindCredentialsAccess2NoCat, _ = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:    2,
	ActorID:     FindCredentialsUser.ID,
	MintTokenID: 1301,
	IssuedAt:    time.Now().UTC(),
})

var FindCredentialsAccess2WithCat, _ = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:    2,
	ActorID:     FindCredentialsUser.ID,
	MintTokenID: 1301,
	IssuedAt:    time.Now().UTC(),
	ExtraCommonAttrs: []*pb.Attribute{
		pb.NewStringAttribute("cat", "tabby"),
	},
})

var NilUserProgrammaticAccessToken, NilUserToken = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:    2,
	ActorID:     9876,
	MintTokenID: 1400,
	IssuedAt:    time.Now().UTC(),
})

var SuspendedUserProgrammaticAccessToken, SuspendedUserToken = generateProgrammaticAccessToken(&tokenSettableValues{
	AccessID:    2,
	ActorID:     SuspendedUser.ID,
	MintTokenID: 1402,
	IssuedAt:    time.Now().UTC(),
})

type tokenSettableValues struct {
	AccessID            int64
	ActorID             int64
	MintTokenID         int64
	IssuedAt            time.Time
	ExpiresAt           time.Time
	RevokedAt           time.Time
	LastEventAt         time.Time
	OverrideCommonAtrrs bool
	ExtraCommonAttrs    []*pb.Attribute
}

func generateProgrammaticAccessToken(attrs *tokenSettableValues) (*models.ProgrammaticAccessToken, *fgpat.Token) {
	token := generateToken(attrs.ActorID)
	var commonAttrs []*pb.Attribute
	if !attrs.OverrideCommonAtrrs {
		commonAttrs = GetPRATRequiredAttributes(attrs.ActorID, attrs.AccessID)
	}
	if attrs.ExtraCommonAttrs != nil {
		commonAttrs = append(commonAttrs, attrs.ExtraCommonAttrs...)
	}
	prat := &models.ProgrammaticAccessToken{
		HashedToken: []byte(token.Hash()),
		TokenSuffix: []byte(token.GetSuffix()),
		AccessID:    uint64(attrs.AccessID),
		MintTokenCommon: &models.MintTokenCommon{
			ID:         uint64(attrs.MintTokenID),
			ActorID:    uint64(attrs.ActorID),
			ActorType:  "User",
			IssuedAt:   attrs.IssuedAt,
			Attributes: serializeAttributes(commonAttrs),
		},
	}
	if !attrs.LastEventAt.IsZero() {
		prat.LastEventAt = models.NullMysqlDateTimeFromTime(attrs.LastEventAt)
	}
	if !attrs.ExpiresAt.IsZero() {
		prat.ExpiresAt = models.NullMysqlDateTimeFromTime(attrs.ExpiresAt)
	}
	if !attrs.RevokedAt.IsZero() {
		prat.RevokedAt = models.NullMysqlDateTimeFromTime(attrs.RevokedAt)
	}

	return prat, token
}

func GetPRATRequiredAttributes(actorID, accessID int64) []*pb.Attribute {
	return []*pb.Attribute{
		pb.NewInt64Attribute(client.ActorIDAttribute, actorID),
		pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
		pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, accessID),
	}
}

func generateToken(actorID int64) *fgpat.Token {
	header := fgpat.NewV1Header(fgpat.ProgrammaticAccessTokenType, uint32(actorID))
	tok, _ := fgpat.GenerateToken(fgpat.V1Prefix, header)

	return tok
}

func serializeAttributes(attributes []*pb.Attribute) []byte {
	bytes, _ := apimodels.SerializeAttributes(attributes)
	return bytes
}

func mustParseToken(token string) *fgpat.Token {
	t, err := fgpat.ParseToken(token)
	if err != nil {
		panic(err)
	}
	return t
}
