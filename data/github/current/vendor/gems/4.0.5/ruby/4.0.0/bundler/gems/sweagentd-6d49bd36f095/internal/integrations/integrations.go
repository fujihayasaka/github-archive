// Package integrations provides details about first-party integrations.
// This package should only contain constants and static details needed to
// enable first-party integrations in a generic, reusable way.
package integrations

import (
	"slices"

	"github.com/github/sweagentd/internal/integrations/cianalysis"
	"github.com/github/sweagentd/internal/integrations/codereview"
	"github.com/github/sweagentd/internal/integrations/codescanning"
	"github.com/github/sweagentd/internal/integrations/verificationplatform"
)

// progressNamespaces contains the progress namespaces for all first-party integrations.
var progressNamespaces = []string{
	cianalysis.ProgressNamespace,
	codereview.ProgressNamespace,
	codescanning.ProgressNamespace,
	verificationplatform.ProgressNamespace,
}

// IsProgressNamespace reports whether the given namespace is a registered
// first-party integration progress namespace.
func IsProgressNamespace(ns string) bool {
	return slices.Contains(progressNamespaces, ns)
}
