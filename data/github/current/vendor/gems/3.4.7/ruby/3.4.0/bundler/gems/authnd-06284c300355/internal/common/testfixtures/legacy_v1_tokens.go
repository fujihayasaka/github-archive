package testfixtures

import (
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/models"
)

var (
	ExpiredLegacyProgrammaticAccessTokenPlainText                 = mustParseToken("gh1_1AAAAAAI0im3k9mu7LaCJ_qeLdjBWT3PTGX29CcwfMnkX4gWxQAgYSbKobe9cU5PEQH7VI7AX202ZtlwS")
	RevokedLegacyProgrammaticAccessTokenPlainText                 = mustParseToken("gh1_1AAAAAAI0mlm2fiTsa4sF_6NAy6fYVGN48nUu5nQYNLLYlPT29nHuqp8Y1PhgOYq52ZNL4NXKuMq380gJ")
	NotFoundLegacyProgramaticAccessTokenPlainText                 = mustParseToken("gh1_1AAAAAAI0SPZ75SYT52YY_bMcTFy0SfPm2P1AbjF2OAiiaL3uP3gi0OXNGAYoRaHHN7R6MOK4YEVVGy4j")
	MonalisaLegacyProgrammaticAccessTokenPlainText                = mustParseToken("gh1_1AAAAAAI01sHihE23bnDa_USbRk05vTHgobVgWGM8Cmo8xyyd6uGd7PlJ5o5WSAmJJDPBQMVOBxTvGS66")
	FutureExpiredLegacyProgrammaticAccessTokenPlainText           = mustParseToken("gh1_1AAAAAAI0vwMltd7SBH0S_IoZt6rfyHi169nD9Lc3fUFGQkEGofReab0vViOw74CGODQZAIGMbTJ1Qxt5")
	MonalisaLegacyProgrammaticAccessTokenExtraAttributesPlainText = mustParseToken("gh1_1AAAAAAI00oygw3TNWn93_daNpR4odClX6oyuETggIFSz37nx8mOuXDfksAJlKw14E27ZIKCQ8Lj3Wjof")
	MissingActorIDLegacyProgrammaticAccessTokenPlainText          = mustParseToken("gh1_1AAAAAAQ0kGOaYfjK4HPO_HuGNqYDJEsTHHrTmRy3YXEjoWAu3q7MKeDrr9esPoksAFWJMEO6Ot1bdLxJ")
	MissingActorTypeLegacyProgrammaticAccessTokenPlainText        = mustParseToken("gh1_1AAAAAAQ0ODYYCREc5Du2_wj9ltmUvq394v4PdrwORgKhk4FG3sfaIPDFuW3dUS9R2VTUHK2D4Wg7Bi72")
	MissingAccessIDLegacyProgrammaticAccessTokenPlainText         = mustParseToken("gh1_1AAAAAAQ0BtXYFPT95wqE_RnxQvwF9aBoENkBLD1aQlUoUvgSKl0zKuknuY9AcFsdI4HSFEPNPLsi0fpv")
	MismatchActorIDLegacyProgrammaticAccessTokenPlainText         = mustParseToken("gh1_1AAAAAAQ0GYuGxTdl6vfm_EOO4a0GR3esahJENPMWeazcEQpcsvPs2ogC95ul7ymt5FXAKP6Im7mXtVXT")
	MismatchActorTypeLegacyProgrammaticAccessTokenPlainText       = mustParseToken("gh1_1AAAAAAQ0W63jNWvnANUg_bjmcPJ3E0KoQkt7413dkKmRh7fHmnZKN3iGoHUWfC8VSYWRQSHX8AOPZArI")
	MismatchAccessIDLegacyProgrammaticAccessTokenPlainText        = mustParseToken("gh1_1AAAAAAQ0qzWXAz1cy1Dx_h18qbrzlSLW2ViW2xGGNOCJ9Ho73ploGWg6rcYkSUohBTJHJOV25vDAdhkk")

	// Tokens used for FindCredentials tests, the values don't actually matter and are just random :)
	FindCredentialsLegacyAccess1NoCatPlainText   = mustParseToken("gh1_1AAAAAAQ0948abadef73d_8069bc199236329a7a65b3cf7efcbb3f363ff378ab482a1b43b6a37982e")
	FindCredentialsLegacyAccess1WithCatPlainText = mustParseToken("gh1_1AAAAAAQ0b18a3fd35243_3fa2a5d31d7abf8538223bd8e0c6fca202ef4dd93471a46cb6f9d40c2a2")
	FindCredentialsLegacyAccess2NoCatPlainText   = mustParseToken("gh1_1AAAAAAQ0f147e2ee3f6f_0003f90dd0f085e7530e4cdfbabaa00a67d66722a23ff88ab9f46746b9d")
	FindCredentialsLegacyAccess2WithCatPlainText = mustParseToken("gh1_1AAAAAAQ05645a3efe14f_8110ef074b2585abcc672fbb43cb4b92f3b5587415cb6570eb5dded9d44")
	FindCredentialsLegacyAccess2ExpiredPlainText = mustParseToken("gh1_1AAAAAAQ017a9b17dc3f2_fc5b12fb8807c43a002a03368555ce327c24e74cdb7f175e0fc54cdf167")
	FindCredentialsLegacyAccess2RevokedPlainText = mustParseToken("gh1_1AAAAAAQ019bbdd48bbbe_abc94ad52459e68d28d94ebbf76dbf00881763eae5c5c21af910ac792cc")
)

var MonalisaLegacyProgrammaticAccessToken = &models.ProgrammaticAccessToken{
	HashedToken: []byte(MonalisaLegacyProgrammaticAccessTokenPlainText.Hash()),
	TokenSuffix: []byte(MonalisaLegacyProgrammaticAccessTokenPlainText.GetSuffix()),
	AccessID:    uint64(3),
	MintTokenCommon: &models.MintTokenCommon{
		ID:         201,
		ActorID:    uint64(MonalisaUser.ID),
		ActorType:  "User",
		IssuedAt:   time.Now().UTC(),
		Attributes: serializeAttributes(GetPRATRequiredAttributes(MonalisaUser.ID, 3)),
	},
}

var MonalisaLegacyProgrammaticAccessTokenExtraAttributes = &models.ProgrammaticAccessToken{
	HashedToken: []byte(MonalisaLegacyProgrammaticAccessTokenExtraAttributesPlainText.Hash()),
	TokenSuffix: []byte(MonalisaLegacyProgrammaticAccessTokenExtraAttributesPlainText.GetSuffix()),
	AccessID:    uint64(3),
	MintTokenCommon: &models.MintTokenCommon{
		ID:        202,
		ActorID:   uint64(MonalisaUser.ID),
		ActorType: "User",
		IssuedAt:  time.Now().UTC(),
		Attributes: serializeAttributes([]*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, MonalisaUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
			pb.NewBoolAttribute(BoolTrueAttributeId, true),
			pb.NewBoolAttribute(BoolFalseAttributeId, false),
			pb.NewDoubleAttribute(DoubleAttributeId, 1.1),
		}),
	},
}

var ExpiredLegacyProgrammaticAccessToken = &models.ProgrammaticAccessToken{
	HashedToken: []byte(ExpiredLegacyProgrammaticAccessTokenPlainText.Hash()),
	TokenSuffix: []byte(ExpiredLegacyProgrammaticAccessTokenPlainText.GetSuffix()),
	AccessID:    uint64(3),
	MintTokenCommon: &models.MintTokenCommon{
		ID:         203,
		ActorID:    uint64(MonalisaUser.ID),
		ActorType:  "User",
		IssuedAt:   time.Now().UTC(),
		ExpiresAt:  models.NullMysqlDateTimeFromTime(time.Date(2000, 1, 11, 10, 1, 2, 0, time.UTC)),
		Attributes: serializeAttributes(GetPRATRequiredAttributes(MonalisaUser.ID, 3)),
	},
}

var RevokedLegacyProgrammaticAccessToken = &models.ProgrammaticAccessToken{
	HashedToken: []byte(RevokedLegacyProgrammaticAccessTokenPlainText.Hash()),
	TokenSuffix: []byte(RevokedLegacyProgrammaticAccessTokenPlainText.GetSuffix()),
	AccessID:    uint64(3),
	MintTokenCommon: &models.MintTokenCommon{
		ID:         204,
		ActorID:    uint64(MonalisaUser.ID),
		ActorType:  "User",
		IssuedAt:   time.Now().UTC(),
		RevokedAt:  models.NullMysqlDateTimeFromTime(time.Date(2000, 1, 11, 10, 1, 2, 0, time.UTC)),
		Attributes: serializeAttributes(GetPRATRequiredAttributes(MonalisaUser.ID, 3)),
	},
}

var FutureExpiredLegacyProgrammaticAccessToken = &models.ProgrammaticAccessToken{
	HashedToken: []byte(FutureExpiredLegacyProgrammaticAccessTokenPlainText.Hash()),
	TokenSuffix: []byte(FutureExpiredLegacyProgrammaticAccessTokenPlainText.GetSuffix()),
	AccessID:    uint64(3),
	MintTokenCommon: &models.MintTokenCommon{
		ID:         205,
		ActorID:    uint64(MonalisaUser.ID),
		ActorType:  "User",
		IssuedAt:   time.Now().UTC(),
		ExpiresAt:  models.NullMysqlDateTimeFromTime(FutureExpirationTime),
		Attributes: serializeAttributes(GetPRATRequiredAttributes(MonalisaUser.ID, 3)),
	},
}

var MissingActorIDLegacyProgrammaticAccessToken = &models.ProgrammaticAccessToken{
	HashedToken: []byte(MissingActorIDLegacyProgrammaticAccessTokenPlainText.Hash()),
	TokenSuffix: []byte(MissingActorIDLegacyProgrammaticAccessTokenPlainText.GetSuffix()),
	AccessID:    uint64(3),
	MintTokenCommon: &models.MintTokenCommon{
		ID:        206,
		ActorID:   uint64(MonalisaUser.ID),
		ActorType: "User",
		IssuedAt:  time.Now().UTC(),
		Attributes: serializeAttributes([]*pb.Attribute{
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 1234),
		}),
	},
}

var MissingActorTypeLegacyProgrammaticAccessToken = &models.ProgrammaticAccessToken{
	HashedToken: []byte(MissingActorTypeLegacyProgrammaticAccessTokenPlainText.Hash()),
	TokenSuffix: []byte(MissingActorTypeLegacyProgrammaticAccessTokenPlainText.GetSuffix()),
	AccessID:    uint64(3),
	MintTokenCommon: &models.MintTokenCommon{
		ID:        207,
		ActorID:   uint64(MonalisaUser.ID),
		ActorType: "User",
		IssuedAt:  time.Now().UTC(),
		Attributes: serializeAttributes([]*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, MonalisaUser.ID),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
		}),
	},
}

var MissingAccessIDLegacyProgrammaticAccessToken = &models.ProgrammaticAccessToken{
	HashedToken: []byte(MissingAccessIDLegacyProgrammaticAccessTokenPlainText.Hash()),
	TokenSuffix: []byte(MissingAccessIDLegacyProgrammaticAccessTokenPlainText.GetSuffix()),
	AccessID:    uint64(3),
	MintTokenCommon: &models.MintTokenCommon{
		ID:        206,
		ActorID:   uint64(MonalisaUser.ID),
		ActorType: "User",
		IssuedAt:  time.Now().UTC(),
		Attributes: serializeAttributes([]*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, MonalisaUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
		}),
	},
}

var MismatchActorIDLegacyProgrammaticAccessToken = &models.ProgrammaticAccessToken{
	HashedToken: []byte(MismatchActorIDLegacyProgrammaticAccessTokenPlainText.Hash()),
	TokenSuffix: []byte(MismatchActorIDLegacyProgrammaticAccessTokenPlainText.GetSuffix()),
	AccessID:    uint64(3),
	MintTokenCommon: &models.MintTokenCommon{
		ID:        208,
		ActorID:   uint64(MonalisaUser.ID),
		ActorType: "User",
		IssuedAt:  time.Now().UTC(),
		Attributes: serializeAttributes([]*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, 1337),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
		}),
	},
}

var MismatchActorTypeLegacyProgrammaticAccessToken = &models.ProgrammaticAccessToken{
	HashedToken: []byte(MismatchActorTypeLegacyProgrammaticAccessTokenPlainText.Hash()),
	TokenSuffix: []byte(MismatchActorTypeLegacyProgrammaticAccessTokenPlainText.GetSuffix()),
	AccessID:    uint64(3),
	MintTokenCommon: &models.MintTokenCommon{
		ID:        209,
		ActorID:   uint64(MonalisaUser.ID),
		ActorType: "User",
		IssuedAt:  time.Now().UTC(),
		Attributes: serializeAttributes([]*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, MonalisaUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "LizardPerson"),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
		}),
	},
}

var MismatchAccessIDLegacyProgrammaticAccessToken = &models.ProgrammaticAccessToken{
	HashedToken: []byte(MismatchAccessIDLegacyProgrammaticAccessTokenPlainText.Hash()),
	TokenSuffix: []byte(MismatchAccessIDLegacyProgrammaticAccessTokenPlainText.GetSuffix()),
	AccessID:    uint64(3),
	MintTokenCommon: &models.MintTokenCommon{
		ID:        208,
		ActorID:   uint64(MonalisaUser.ID),
		ActorType: "User",
		IssuedAt:  time.Now().UTC(),
		Attributes: serializeAttributes([]*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, MonalisaUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 31337),
		}),
	},
}

var FindCredentialsLegacyAccess1NoCat = &models.ProgrammaticAccessToken{
	HashedToken: []byte(FindCredentialsLegacyAccess1NoCatPlainText.Hash()),
	TokenSuffix: []byte(FindCredentialsLegacyAccess1NoCatPlainText.GetSuffix()),
	AccessID:    uint64(1),
	MintTokenCommon: &models.MintTokenCommon{
		ID:        300,
		ActorID:   uint64(FindCredentialsUser.ID),
		ActorType: "User",
		IssuedAt:  time.Now().UTC(),
		Attributes: serializeAttributes([]*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, FindCredentialsUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 1),
		}),
	},
}

var FindCredentialsLegacyAccess1WithCat = &models.ProgrammaticAccessToken{
	HashedToken: []byte(FindCredentialsLegacyAccess1WithCatPlainText.Hash()),
	TokenSuffix: []byte(FindCredentialsLegacyAccess1WithCatPlainText.GetSuffix()),
	AccessID:    uint64(1),
	MintTokenCommon: &models.MintTokenCommon{
		ID:        301,
		ActorID:   uint64(FindCredentialsUser.ID),
		ActorType: "User",
		IssuedAt:  time.Now().UTC(),
		ExpiresAt: models.NullMysqlDateTimeFromTime(time.Date(2999, 1, 11, 10, 1, 2, 0, time.UTC)),
		Attributes: serializeAttributes([]*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, FindCredentialsUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 1),
			pb.NewStringAttribute("cat", "tabby"),
		}),
	},
}

var FindCredentialsLegacyAccess2NoCat = &models.ProgrammaticAccessToken{
	HashedToken: []byte(FindCredentialsLegacyAccess2NoCatPlainText.Hash()),
	TokenSuffix: []byte(FindCredentialsLegacyAccess2NoCatPlainText.GetSuffix()),
	AccessID:    uint64(2),
	MintTokenCommon: &models.MintTokenCommon{
		ID:        301,
		ActorID:   uint64(FindCredentialsUser.ID),
		ActorType: "User",
		IssuedAt:  time.Now().UTC(),
		Attributes: serializeAttributes([]*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, FindCredentialsUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 2),
		}),
	},
}

var FindCredentialsLegacyAccess2WithCat = &models.ProgrammaticAccessToken{
	HashedToken: []byte(FindCredentialsLegacyAccess2WithCatPlainText.Hash()),
	TokenSuffix: []byte(FindCredentialsLegacyAccess2WithCatPlainText.GetSuffix()),
	AccessID:    uint64(2),
	MintTokenCommon: &models.MintTokenCommon{
		ID:        301,
		ActorID:   uint64(FindCredentialsUser.ID),
		ActorType: "User",
		IssuedAt:  time.Now().UTC(),
		Attributes: serializeAttributes([]*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, FindCredentialsUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 2),
			pb.NewStringAttribute("cat", "tabby"),
		}),
	},
}

var FindCredentialsLegacyAccess2Expired = &models.ProgrammaticAccessToken{
	HashedToken: []byte(FindCredentialsLegacyAccess2ExpiredPlainText.Hash()),
	TokenSuffix: []byte(FindCredentialsLegacyAccess2ExpiredPlainText.GetSuffix()),
	AccessID:    uint64(2),
	MintTokenCommon: &models.MintTokenCommon{
		ID:        301,
		ActorID:   uint64(FindCredentialsUser.ID),
		ActorType: "User",
		IssuedAt:  time.Now().UTC(),
		ExpiresAt: models.NullMysqlDateTimeFromTime(time.Date(2000, 1, 11, 10, 1, 2, 0, time.UTC)),
		Attributes: serializeAttributes([]*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, FindCredentialsUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 2),
		}),
	},
}

var FindCredentialsLegacyAccess2Revoked = &models.ProgrammaticAccessToken{
	HashedToken: []byte(FindCredentialsLegacyAccess2RevokedPlainText.Hash()),
	TokenSuffix: []byte(FindCredentialsLegacyAccess2RevokedPlainText.GetSuffix()),
	AccessID:    uint64(2),
	MintTokenCommon: &models.MintTokenCommon{
		ID:        301,
		ActorID:   uint64(FindCredentialsUser.ID),
		ActorType: "User",
		IssuedAt:  time.Now().UTC(),
		RevokedAt: models.NullMysqlDateTimeFromTime(time.Date(2000, 1, 11, 10, 1, 2, 0, time.UTC)),
		Attributes: serializeAttributes([]*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, FindCredentialsUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 2),
		}),
	},
}
