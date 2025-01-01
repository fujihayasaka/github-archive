package testfixtures

import (
	"time"

	"github.com/github/authnd/internal/common/models"
	"gopkg.in/guregu/null.v4"
)

var Integrations = []*models.Integration{
	DefaultIntegration,
	SuspendedIntegration,
	SpammyUserIntegration,
	SuspendedBotIntegration,
	SpammyBusinessIntegration,
	IntegrationOwnedByOrg,
}

var DefaultIntegration = &models.Integration{
	ID:                1,
	OwnerID:           uint64(MonalisaUser.ID),
	AbstractOwnerType: "User",
	BotID:             uint64(BotUser.ID),
	Name:              null.StringFrom("default-application"),
	State:             0,
	Key:               null.StringFrom(IntegrationKey),
	CreatedAt:         models.NullMysqlDateTimeFromTime(time.Now()),
}

var SuspendedIntegration = &models.Integration{
	ID:                2,
	OwnerID:           uint64(MonalisaUser.ID),
	AbstractOwnerType: "User",
	BotID:             uint64(BotUser.ID),
	Name:              null.StringFrom("suspended-application"),
	State:             1,
	Key:               null.StringFrom("v1.b90f985d4e6f0a89"),
	CreatedAt:         models.NullMysqlDateTimeFromTime(time.Now()),
}

var SpammyUserIntegration = &models.Integration{
	ID:                3,
	OwnerID:           uint64(SpammyUser.ID),
	AbstractOwnerType: "User",
	BotID:             uint64(BotUser.ID),
	Name:              null.StringFrom("application-with-spammy-user"),
	State:             0,
	Key:               null.StringFrom(SpammyUserIntegrationKey),
	CreatedAt:         models.NullMysqlDateTimeFromTime(time.Now()),
	UserHidden:        true,
}

var SuspendedBotIntegration = &models.Integration{
	ID:                4,
	OwnerID:           uint64(MonalisaUser.ID),
	AbstractOwnerType: "User",
	BotID:             uint64(SuspendedBotUser.ID),
	Name:              null.StringFrom("application-with-suspended-bot"),
	State:             0,
	Key:               null.StringFrom("Iv1.123456a0231f8e69"),
	CreatedAt:         models.NullMysqlDateTimeFromTime(time.Now()),
}

var SpammyBusinessIntegration = &models.Integration{
	ID:                5,
	OwnerID:           uint64(SpammyBusiness.ID),
	AbstractOwnerType: "Business",
	BotID:             uint64(BotUser.ID),
	Name:              null.StringFrom("business-owned-application"),
	State:             0,
	Key:               null.StringFrom(SpammyBusinessIntegrationKey),
	CreatedAt:         models.NullMysqlDateTimeFromTime(time.Now()),
}

var IntegrationOwnedByOrg = &models.Integration{
	ID:                6,
	OwnerID:           uint64(OrgOne.ID),
	AbstractOwnerType: "User", // this is how it's stored in the DB
	BotID:             uint64(BotUser.ID),
	Name:              null.StringFrom("organization-owned-application"),
	State:             0,
	Key:               null.StringFrom(IntegrationOwnedByOrgKey),
	CreatedAt:         models.NullMysqlDateTimeFromTime(time.Now()),
}
