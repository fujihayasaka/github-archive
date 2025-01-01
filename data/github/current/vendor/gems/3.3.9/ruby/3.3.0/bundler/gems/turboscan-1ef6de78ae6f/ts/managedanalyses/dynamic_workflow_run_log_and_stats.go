package managedanalyses

import (
	"context"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
)

// DynamicWorkflowRunLogAndStats logs the launch of a dynamic workflow
// run, including details about the workflow template version, as well
// as sending stats about it
func DynamicWorkflowRunLogAndStats(ctx context.Context, config *ts.CodeqlConfig, run *ts.CodeqlRun) {
	wtv := "unknown"
	if config != nil {
		wtv = config.TemplateVersion
	}
	appctx.Logger(ctx).Info("Dynamic workflow submitted",
		run.WorkflowRunID.AsKVP(),
		kvp.String("gh.turboscan.execution_id", run.ExecutionID),
		kvp.String("gh.turboscan.trigger", run.TriggeringEvent.String()),
		kvp.String("gh.turboscan.workflow_template_version", wtv),
		kvp.Bool("gh.turboscan.steady_run", !run.Validation()))

	tags := stats.Tags{
		"trigger":                   run.TriggeringEvent.String(),
		"workflow_template_version": wtv,
		"steady_run":                strconv.FormatBool(!run.Validation()),
	}
	appctx.Stats(ctx).Counter("default_setup.dynamic_workflow_run", tags, 1)

	if run.EventTimestamp != nil {
		appctx.Stats(ctx).DistributionMs("default_setup.trigger_to_workflow_enqueued", tags, time.Since(run.EventTimestamp.Time))
	}
}
