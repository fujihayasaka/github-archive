package utils

type RuntimeHelper struct {
	isEnterprise      bool
	enterpriseVersion string
}

func NewRuntimeHelper(isEnterprise bool, enterpriseVersion string) *RuntimeHelper {
	return &RuntimeHelper{
		isEnterprise:      isEnterprise,
		enterpriseVersion: enterpriseVersion,
	}
}

func (r *RuntimeHelper) IsEnterprise() bool {
	return r.isEnterprise
}

func (r *RuntimeHelper) GetDocsURL(path string) string {
	if r.IsEnterprise() {
		return GetGHESDocsURL(path, r.enterpriseVersion)
	}

	return GetDotcomDocsURL(path)
}
