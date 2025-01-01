package workflowinvoker

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/actions-expressions/go/data"
	parser "github.com/github/actions-workflow-parser/go"
	"github.com/github/actions-workflow-parser/go/reader"
	"github.com/github/actions-workflow-parser/go/token"
	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/expressions"
	"github.com/github/launch/pkg/wfparser"

	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/build"
	"github.com/github/launch/workflowparser"
)

func (i *buildInvoker) updateWorkflowRunName(
	ctx context.Context,
	parsedWorkflow *workflowparser.Workflow,
	b *build.WorkflowBuild,
	checkSuiteState *types.CheckSuiteState,
	secretSource,
	runNameExpression string,
	errCtx *WorkflowStartErrorContext,
	variables map[string]string,
) (startErr *WorkflowStartErr) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	i.obs.Debug(ctx, "evaluating workflow run name", kvp.String("gh.launch.input_run.name", runNameExpression))

	expContext, err := expressions.NewContext(ctx, &i.obs.Observability, parsedWorkflow, b, secretSource, variables)

	if err != nil {
		i.obs.Error(ctx, "unable to create expression context", kvp.Err(err))
		span.RecordError(err)
		return NewPermanentWorkflowStartError(errCtx, err, parserErrorErrType)
	}

	defer func() {
		if r := recover(); r != nil {
			i.obs.Error(ctx, "panic using expression engine", kvp.Err(err))
			err = fmt.Errorf("panic using expression engine: %v", r)
			startErr = NewPermanentWorkflowStartError(errCtx, err, parserErrorErrType)
		}
	}()

	runName, err := evaluateRunName(runNameExpression, expContext, parsedWorkflow)
	if err != nil {
		i.obs.Debug(ctx, "unable to evaluate run-name expression")
		span.RecordError(err)

		return NewPermanentWorkflowStartError(errCtx, err, parserErrorErrType)
	} else if runName == "" {
		i.obs.Debug(ctx, "run-name expression evaluated to empty or whitespace string")
		return nil
	}

	i.obs.Debug(ctx, "evaluated workflow run name", kvp.String("gh.launch.evaluated_run.name", runName))
	err = updateWorkflowRun(ctx, i.ghTwirpClient, checkSuiteState, runName)
	if err != nil {
		i.obs.Error(ctx, "unable to update workflow run name", kvp.Err(err))
		span.RecordError(err)
		return NewWorkflowStartError(errCtx, err, parserErrorErrType)
	}

	return nil
}

// Evaluate the value of the run-name expression using actions-workflow-parser
func evaluateRunName(runNameExpression string, expContext *data.Dictionary, parsedWorkflow *workflowparser.Workflow) (string, error) {
	line := parsedWorkflow.Parsed().RunNameExpression.Line
	col := parsedWorkflow.Parsed().RunNameExpression.Column
	path := parsedWorkflow.Path

	s := token.NewStringToken(runNameExpression)
	s.SetPos(1, line, col)

	tok, err := reader.ParseScalar(s, expContext.Keys())
	if err != nil {
		// Error doesn't contain file/line/col, add it here
		errMsg := fmt.Sprintf("%v (Line: %v, Col: %v): %v", path, line, col, err.Error())
		return "", wfparser.NewWorkflowParseError([]error{errors.New(errMsg)})
	}

	evaluator := parser.NewWorkflowTemplateEvaluator([]string{path}, nil)
	runName, err := evaluator.EvaluateRunName(tok, expContext)
	if err != nil {
		// Errors contain file/line/col
		return "", wfparser.NewWorkflowParseError([]error{err})
	}

	if strings.TrimSpace(runName) == "" {
		return "", nil
	}

	return workflowparser.TrimName(runName), nil
}
