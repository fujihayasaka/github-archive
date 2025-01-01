package cocofix

import (
	"encoding/json"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/sarif"
	v210 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
)

type SarifBuilderOpts struct {
	AllowNonDefaultRules bool
}

type SarifBuilder struct {
	sarif     *v210.SARIF210ForGitHubCodeScanning
	ruleStore *defaultRuleStore
	opts      SarifBuilderOpts
}

func NewSarifBuilder(opts SarifBuilderOpts) (*SarifBuilder, error) {
	dr, err := sarif.DefaultRuleMetadataAugmentor()
	if err != nil {
		return nil, err
	}

	return &SarifBuilder{
		sarif:     sarif.NewSarif(),
		ruleStore: &defaultRuleStore{dr},
		opts:      opts,
	}, nil
}

type ToolInfo struct {
	ToolName            string
	ToolVersion         string
	ToolSemanticVersion string
}

func (b *SarifBuilder) AppendRun(args *ToolInfo) *RunBuilder {
	run := &v210.Run{}
	run.Conversion = &v210.Conversion{}
	run.Conversion.Tool = &v210.Tool{}
	run.Conversion.Tool.Driver = &v210.ToolComponent{Name: "GitHub Code Scanning"}

	tool := &v210.Tool{}
	tool.Driver = &v210.ToolComponent{}
	tool.Driver.Name = args.ToolName
	tool.Driver.Version = args.ToolVersion
	if args.ToolSemanticVersion == "" {
		tool.Driver.SemanticVersion = args.ToolVersion
	} else {
		tool.Driver.SemanticVersion = args.ToolSemanticVersion
	}
	tool.Driver.Rules = make([]*v210.ReportingDescriptor, 0)
	run.Tool = tool

	b.sarif.Runs = append(b.sarif.Runs, run)
	return &RunBuilder{
		run: run,
		sb:  b,
	}
}

func (b *SarifBuilder) BuildIndented() ([]byte, error) {
	return json.MarshalIndent(b.sarif, "", " ")
}

type RunBuilder struct {
	run *v210.Run
	sb  *SarifBuilder
}

type Result struct {
	Number            int
	GUID              string
	SarifIdentifier   string
	Message           string
	MessageMarkdown   string
	FilePath          string
	Region            ts.Region
	CodeFlowsDocument *ts.CodeFlowsDocument
	RelatedLocations  []*ts.RelatedLocation
	Rule              *ts.Rule
}

func (b *RunBuilder) AppendResult(alert *Result) bool {
	result := &v210.Result{CorrelationGuid: alert.GUID}
	result.Properties = &v210.ResultPropertyBag{GithubAlertNumber: alert.Number}

	result.Rule = &v210.ReportingDescriptorReference{}
	result.Rule.Id = alert.SarifIdentifier
	result.RuleId = result.Rule.Id
	ruleIndex := b.FindOrAppendRule(alert)
	if ruleIndex == -1 {
		return false
	}
	result.RuleIndex = ruleIndex
	result.Rule.Index = result.RuleIndex

	result.Message = &v210.Message{
		Text:     alert.Message,
		Markdown: alert.MessageMarkdown,
	}
	// Message is mandatory for SARIF parsing, so we set a default if it wasnt specified (old data).
	if result.Message.Text == "" {
		result.Message.Text = "Empty message"
	}

	result.Locations = append(result.Locations, &v210.Location{
		PhysicalLocation: &v210.PhysicalLocation{
			ArtifactLocation: sarif.BuildArtifactLocation(alert.FilePath),
			Region:           sarif.BuildRegion(alert.Region),
		},
	})

	for _, relatedLocation := range alert.RelatedLocations {
		result.RelatedLocations = append(result.RelatedLocations, &v210.Location{
			Id:      int(relatedLocation.ReplacementIndex),
			Message: &v210.Message{Text: relatedLocation.Message},
			PhysicalLocation: &v210.PhysicalLocation{
				ArtifactLocation: sarif.BuildArtifactLocation(relatedLocation.FilePath),
				Region:           sarif.BuildRegion(relatedLocation.Region),
			},
		})
	}
	result.CodeFlows = sarif.BuildCodeFlows(alert.CodeFlowsDocument)

	b.run.Results = append(b.run.Results, result)
	return true
}

func (b *RunBuilder) FindOrAppendRule(alert *Result) int {
	ruleID := alert.SarifIdentifier
	rules := b.run.Tool.Driver.Rules
	for i, r := range rules {
		if r.Id == ruleID {
			return i
		}
	}
	rule := b.sb.ruleStore.FindRule(b.run.Tool.Driver.Name, ruleID)
	if rule == nil {
		if b.sb.opts.AllowNonDefaultRules && alert.Rule != nil {
			rule = &v210.ReportingDescriptor{
				Id:   ruleID,
				Name: alert.Rule.Name,
				ShortDescription: &v210.MultiformatMessageString{
					Text: alert.Rule.ShortDescription,
				},
				FullDescription: &v210.MultiformatMessageString{
					Text: alert.Rule.FullDescription,
				},
			}
			if alert.Rule.Help != "" {
				rule.Help = &v210.MultiformatMessageString{
					Text:     alert.Rule.Help,
					Markdown: alert.Rule.Help,
				}
			}
		} else {
			rule = &v210.ReportingDescriptor{
				Id:   ruleID,
				Name: ruleID,
			}
		}
	}
	b.run.Tool.Driver.Rules = append(b.run.Tool.Driver.Rules, rule)
	return len(b.run.Tool.Driver.Rules) - 1
}

// default rule store
type defaultRuleStore struct {
	r sarif.RuleMetadataAugmentor
}

func (s *defaultRuleStore) FindRule(tool string, ruleID string) *v210.Rule {
	rm := s.r.DefaultRulesDataByTool(tool)
	return rm[ruleID]
}
