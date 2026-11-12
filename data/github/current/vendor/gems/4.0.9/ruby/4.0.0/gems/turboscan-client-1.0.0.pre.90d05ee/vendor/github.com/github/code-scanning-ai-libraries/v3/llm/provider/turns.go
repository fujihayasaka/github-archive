package provider

import (
	"context"
	"fmt"

	"github.com/github/code-scanning-ai-libraries/v3/errors"
	"github.com/github/code-scanning-ai-libraries/v3/llm/models"
)

type maxTurnsContextKey struct{}

type turnsState struct {
	Used int
}

func incrementTurns(ctx context.Context) (context.Context, int) {
	parentState, _ := ctx.Value(maxTurnsContextKey{}).(*turnsState)
	state := &turnsState{}
	if parentState != nil {
		*state = *parentState
	}
	state.Used++
	ctx = context.WithValue(ctx, maxTurnsContextKey{}, state)
	ctx = models.WithTurnNumber(ctx, state.Used)
	return ctx, state.Used
}

func enforceMaxTurns(ctx context.Context, options *models.CompletionOptions) (context.Context, int, errors.LLMError) {
	ctx, used := incrementTurns(ctx)
	if options == nil || options.MaxTurns == nil {
		return ctx, used, nil
	}
	if *options.MaxTurns <= 0 {
		return ctx, used, errors.NewError("max_turns must be > 0", errors.ErrorTypeLogic)
	}
	if used > *options.MaxTurns {
		return ctx, used, errors.NewError(
			fmt.Sprintf("max turns exceeded (max=%d)", *options.MaxTurns),
			errors.ErrorTypeLogic,
		)
	}
	return ctx, used, nil
}
