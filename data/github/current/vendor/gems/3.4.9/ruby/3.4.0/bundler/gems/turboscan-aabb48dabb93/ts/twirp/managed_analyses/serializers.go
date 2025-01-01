package managed_analyses

import (
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/proto"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"
)

var errUnspecifiedValue = errors.New("unspecified value")
var errUnknownValue = errors.New("unknown value")

func serializeOnboardingStatus(s ts.OnboardingStatus) proto.OnboardingStatusV2 {
	switch s {
	case ts.OnboardingStatus_DISABLED:
		return proto.OnboardingStatusV2_DISABLED
	case ts.OnboardingStatus_WAITING:
		return proto.OnboardingStatusV2_WAITING
	case ts.OnboardingStatus_ONBOARDING:
		return proto.OnboardingStatusV2_ONBOARDING
	case ts.OnboardingStatus_STABLE:
		return proto.OnboardingStatusV2_STABLE
	case ts.OnboardingStatus_UPDATING:
		return proto.OnboardingStatusV2_UPDATING
	default:
		return proto.OnboardingStatusV2_DISABLED
	}
}

func serializeCodeQLConfig(config *ts.CodeqlConfig) *proto.CodeQLConfig {
	runnerLabel := config.RunnerLabel

	resp := &proto.CodeQLConfig{
		Languages:        config.Languages,
		InitialLanguages: config.InitialLanguages,
		UpdatedAt:        timestamppb.New(config.UpdatedAt.Time),
		QuerySuite:       serializeQuerySuite(config.QuerySuiteType.Root()),
		ThreatModel:      serializeThreatModel(config.ThreatModel),
		Trigger:          serializeNewConfigTrigger(config),
		RunnerLabel:      runnerLabel,
	}

	return resp
}

func serializeQuerySuite(q ts.QuerySuite) proto.QuerySuite {
	switch q {
	case ts.QuerySuite_DEFAULT:
		return proto.QuerySuite_QUERY_SUITE_DEFAULT
	case ts.QuerySuite_EXTENDED:
		return proto.QuerySuite_QUERY_SUITE_SECURITY_EXTENDED
	default:
		return proto.QuerySuite_QUERY_SUITE_DEFAULT
	}
}

func deserializeQuerySuite(p proto.QuerySuite) (*ts.QuerySuite, error) {
	var q ts.QuerySuite
	var err error = nil
	switch p {
	case proto.QuerySuite_QUERY_SUITE_DEFAULT:
		q = ts.QuerySuite_DEFAULT
	case proto.QuerySuite_QUERY_SUITE_SECURITY_EXTENDED:
		q = ts.QuerySuite_EXTENDED
	case proto.QuerySuite_QUERY_SUITE_UNSPECIFIED:
		err = errors.Wrap(errUnspecifiedValue, "query suite")
	default:
		err = errors.Wrap(errUnknownValue, "query suite")
	}
	return &q, err
}

func serializeThreatModel(t ts.ThreatModel) proto.ThreatModel {
	switch t {
	case ts.ThreatModel_REMOTE:
		return proto.ThreatModel_THREAT_MODEL_REMOTE
	case ts.ThreatModel_REMOTE_LOCAL:
		return proto.ThreatModel_THREAT_MODEL_REMOTE_LOCAL
	default:
		return proto.ThreatModel_THREAT_MODEL_REMOTE
	}
}

func deserializeThreatModel(p proto.ThreatModel) (*ts.ThreatModel, error) {
	var t ts.ThreatModel
	var err error = nil
	switch p {
	case proto.ThreatModel_THREAT_MODEL_REMOTE:
		t = ts.ThreatModel_REMOTE
	case proto.ThreatModel_THREAT_MODEL_REMOTE_LOCAL:
		t = ts.ThreatModel_REMOTE_LOCAL
	case proto.ThreatModel_THREAT_MODEL_UNSPECIFIED:
		err = errors.Wrap(errUnspecifiedValue, "threat model")
	default:
		err = errors.Wrap(errUnknownValue, "threat model")
	}
	return &t, err
}

func deserializeLanguageList(ll *proto.LanguageList) *ts.Languages {
	if ll == nil {
		return nil
	}

	languageList := ts.Languages(ll.Languages)
	return &languageList
}

func serializeNewConfigTrigger(c *ts.CodeqlConfig) proto.NewConfigTrigger {
	if c.ValidationRun.LanguageUpdateValidation() {
		return proto.NewConfigTrigger_LANGUAGES_CHANGE
	}
	if c.ValidationRun.JITValidation() {
		return proto.NewConfigTrigger_TEMPLATE_UPGRADE
	}
	return proto.NewConfigTrigger_MANUAL
}
