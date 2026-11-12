package twirp

import "github.com/github/go-spdx/v2/spdxexp"

func (s *Server) spdxLicenseValidationOptions() spdxexp.ValidateLicensesOptions {
	return spdxexp.ValidateLicensesOptions{FailComplexExpressions: true}
}
