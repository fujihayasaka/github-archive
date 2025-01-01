package v210turboscan

import (
	"encoding/json"

	"github.com/mailru/easyjson"

	"github.com/github/turboscan/ts/transforms"
)

func (s *SARIF210ForGitHubCodeScanning) Normalise() {
	s.Runs = transforms.Map(s.Runs, func(run *Run) *Run { run.normalise(); return run })
}

//easyjson:json
type SARIF = SARIF210ForGitHubCodeScanning
type Rule = ReportingDescriptor

//easyjson:json
type InvocationNonRec Invocation

//easyjson:json
type ResultNonRec Result

//easyjson:json
type ReportingDescriptorReferenceNonRec ReportingDescriptorReference

//easyjson:json
type TCRNonRec ToolComponentReference

func (r *Result) UnmarshalJSON(b []byte) error {
	// TODO: This should be handled by the generated code
	r.RuleIndex = -1
	tmp := (*ResultNonRec)(r)
	return easyjson.Unmarshal(b, tmp)
}

func (r *Result) MarshalJSON() ([]byte, error) {
	type ResultNonRec Result
	type IndexedResult struct {
		ResultNonRec
		// override omit empty
		RuleIndex int `json:"ruleIndex"`
	}

	tmp := (*ResultNonRec)(r)

	if r.RuleIndex >= 0 {
		indexed := new(IndexedResult)
		indexed.ResultNonRec = *tmp
		indexed.RuleIndex = tmp.RuleIndex
		return json.Marshal(indexed)
	} else {
		// omit negative index
		clone := new(ResultNonRec)
		*clone = *tmp
		clone.RuleIndex = 0
		return json.Marshal(clone)
	}
}

func (r *ReportingDescriptorReference) UnmarshalJSON(b []byte) error {
	// TODO: This should be handled by the generated code
	r.Index = -1
	tmp := (*ReportingDescriptorReferenceNonRec)(r)
	return easyjson.Unmarshal(b, tmp)
}

func (r *ReportingDescriptorReference) MarshalJSON() ([]byte, error) {
	type ReportingDescriptorReferenceNonRec ReportingDescriptorReference
	type IndexedReportingDescriptorReference struct {
		ReportingDescriptorReferenceNonRec
		// override omit empty
		Index int `json:"index"`
	}

	tmp := (*ReportingDescriptorReferenceNonRec)(r)

	if r.Index >= 0 {
		indexed := new(IndexedReportingDescriptorReference)
		indexed.ReportingDescriptorReferenceNonRec = *tmp
		indexed.Index = tmp.Index
		return json.Marshal(indexed)
	} else {
		// omit negative index
		clone := new(ReportingDescriptorReferenceNonRec)
		*clone = *tmp
		clone.Index = 0
		return json.Marshal(clone)
	}
}

func (tcr *ToolComponentReference) UnmarshalJSON(b []byte) error {
	// TODO: This should be handled by the generated code
	tcr.Index = -1
	tmp := (*TCRNonRec)(tcr)
	return easyjson.Unmarshal(b, tmp)
}

func (tcr *ToolComponentReference) MarshalJSON() ([]byte, error) {
	type TCRNonRec ToolComponentReference
	type IndexedToolComponentReference struct {
		TCRNonRec
		// override omit empty
		Index int `json:"index"`
	}

	tmp := (*TCRNonRec)(tcr)

	if tcr.Index >= 0 {
		indexed := new(IndexedToolComponentReference)
		indexed.TCRNonRec = *tmp
		indexed.Index = tmp.Index
		return json.Marshal(indexed)
	} else {
		// omit negative index
		clone := new(TCRNonRec)
		*clone = *tmp
		clone.Index = 0
		return json.Marshal(clone)
	}
}

func (i *Invocation) UnmarshalJSON(b []byte) error {
	// As we allow invalid SARIF, we need to handle the case where ExecutionSuccessful is not set and assume success
	i.ExecutionSuccessful = true
	// No need for a sentinel value for ExitCode to indicate that the exit code field was not set
	// if the value was zero then the process would have succeeded anyway so this is an ok proxy for no value.
	tmp := (*InvocationNonRec)(i)
	return easyjson.Unmarshal(b, tmp)
}
