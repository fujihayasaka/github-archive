package wfparser

import (
	"context"
	"fmt"

	"github.com/github/actions-expressions/go/data"
	parser "github.com/github/actions-workflow-parser/go"
	template "github.com/github/actions-workflow-parser/go/template"

	"github.com/github/launch/observability"
)

const (
	// Setting default to 50 similar to other places in parser. However, NewWorkflowTemplateEvaluator doesn't appear to currently utilize
	// the parentTemplate's depth value.  Generally we need the depth limits so customer workflows can't cause a stack overflow.
	maxDepth = 50

	// 10 KB
	maxResultSize = 10 * 1024
)

func EvaluateWorkflowConcurrency(ctx context.Context, obs *observability.Observability, wf *parser.WorkflowTemplate, workflowFilePath string, expCtx *data.Dictionary) *parser.ConcurrencySetting {
	defer func() {
		if r := recover(); r != nil {
			e, ok := r.(error)
			if !ok {
				e = fmt.Errorf("%v", r)
			}

			err := fmt.Errorf("panic evaluating concurrency with actions-workflow-parser: %w", e)
			obs.Report(ctx, err)
		}
	}()
	if len(wf.Errors) == 0 {
		parentMemory := template.NewTemplateMemory(maxDepth, maxResultSize, nil)
		wte := parser.NewWorkflowTemplateEvaluator([]string{workflowFilePath}, parentMemory)
		// TODO: https://github.com/github/c2c-actions-experience/issues/7206
		// We are currently only evaluating at the workflow level, so Job ID is "".
		c, err := wte.EvaluateConcurrency("", wf.Concurrency, expCtx, nil)
		if err != nil {
			wf.Errors = append(wf.Errors, err)
		}
		return c
	}
	return nil
}
