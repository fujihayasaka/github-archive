package utils

import (
	v0 "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0"

	"github.com/github/token-scanning-service/ts/constants"
)

func GetSecurityFeatureVisibility(featuresDetails []*v0.SecurityFeatureRepoUpdate_SecurityFeatureDetail) (featureVisible bool, attribPresent bool) {
	for _, v := range featuresDetails {
		if v.SecurityFeature == constants.RepoUpdateFeature {
			attribPresent = true
			featureVisible = v.FeatureVisible
		}
	}
	return
}
