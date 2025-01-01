package cocofix

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"

	"github.com/pkg/errors"
)

func (c *CocofixRunner) buildSarifInput(ctx context.Context, tool *ToolInfo, pa *ts.PhysicalAlert, opts SarifBuilderOpts) (string, []string, error) {
	defer c.emitDistribution(ctx, "BuildSarifInput")()

	// build filePaths from codeFlows

	filePaths, err := pa.ExtractFilePaths()
	if err != nil {
		return "", nil, err
	}
	if len(filePaths) == 0 {
		return "", nil, errors.New("No file paths found in the alert")
	}

	builder, err := NewSarifBuilder(opts)
	if err != nil {
		return "", nil, err
	}
	r := builder.AppendRun(tool)
	var rules []string
	r.AppendResult(&Result{
		Number:            int(pa.LogicalAlert.Number),
		SarifIdentifier:   pa.LogicalAlert.SarifIdentifier,
		Message:           pa.Message,
		MessageMarkdown:   pa.MessageMarkdown,
		FilePath:          pa.LogicalAlert.FilePath,
		Region:            pa.Region,
		CodeFlowsDocument: pa.CodeFlowsDocument,
		RelatedLocations:  pa.RelatedLocations,
		Rule:              pa.Rule,
	})
	rules = append(rules, pa.LogicalAlert.SarifIdentifier)
	b, err := builder.BuildIndented()
	if err != nil {
		return "", nil, err
	}
	appctx.Logger(ctx).Info("CoCoFix input sarif rules",
		kvp.Strings("rules", rules),
		pa.RepositoryID.AsKVP(),
	)

	return string(b), filePaths, nil
}
