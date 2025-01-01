package ghtwirp

import (
	types "github.com/github/launch/types"
)

type EventReference struct {
	Type      string
	BaseRef   types.GitRef
	BeforeOid types.CommitSha
	AfterOid  types.CommitSha
}
