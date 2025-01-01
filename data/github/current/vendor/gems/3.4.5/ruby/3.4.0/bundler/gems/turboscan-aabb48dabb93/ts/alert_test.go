package ts

import (
	"testing"

	"github.com/github/turboscan/ts/proto"
)

func TestAnalysisStatusSortOrderDefined(t *testing.T) {
	var as proto.AnalysisStatus
	ev := as.Descriptor().Values()
	for i := 0; i < ev.Len(); i++ {
		evd := ev.Get(i)
		_, ok := statusSortOrder[proto.AnalysisStatus(evd.Number())]
		if !ok {
			t.Errorf("No sort order defined for proto.AnalysisStatus_%s", evd.Name())
		}
	}
}

func TestSecuritySeverityWeightDefined(t *testing.T) {
	var as proto.SecuritySeverity
	ev := as.Descriptor().Values()
	for i := 0; i < ev.Len(); i++ {
		evd := ev.Get(i)
		_, ok := securitySeverityWeight[proto.SecuritySeverity(evd.Number())]
		if !ok {
			t.Errorf("No weight defined for proto.SecuritySeverity_%s", evd.Name())
		}
	}
}
