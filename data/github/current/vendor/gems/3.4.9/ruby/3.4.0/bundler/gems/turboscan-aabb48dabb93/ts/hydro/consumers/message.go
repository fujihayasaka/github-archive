package consumers

import (
	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"google.golang.org/protobuf/proto"
)

// CloneAnalysisMessage will create a copy of an analysis.
func CloneAnalysisMessage(a *tshydro.Analysis) *tshydro.Analysis {
	clone, _ := proto.Clone(a).(*tshydro.Analysis)
	return clone
}

// UnwrapEnvelope unboxes a v1 or v2 protobuf message into a Hydro envelope.
func UnwrapEnvelope(data []byte, e *envelope.Envelope) error {
	return proto.Unmarshal(data, e)
}

// UnwrapAnalysisMessage unboxes a v1 or v2 Hydro envelope into an Analysis.
func UnwrapAnalysisMessage(data []byte, msg *tshydro.Analysis) error {
	return proto.Unmarshal(data, msg)
}
