package testfixtures

import (
	"github.com/github/authnd/internal/common/models"
	"gopkg.in/guregu/null.v4"
)

var Businesses = []*models.Business{
	DefaultBusiness,
	SpammyBusiness,
}

var DefaultBusiness = &models.Business{
	ID:        12345,
	Slug:      "test-tenant",
	Shortcode: "abcdef",
	Spammy:    null.IntFrom(0),
}

var SpammyBusiness = &models.Business{
	ID:        12346,
	Slug:      "spammy-tenant",
	Shortcode: "ghijkl",
	Spammy:    null.IntFrom(1),
}
