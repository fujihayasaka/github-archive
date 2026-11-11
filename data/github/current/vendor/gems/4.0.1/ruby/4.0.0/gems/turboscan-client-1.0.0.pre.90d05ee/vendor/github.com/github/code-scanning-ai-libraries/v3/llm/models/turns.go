package models

import "context"

type turnNumberContextKey struct{}

// WithTurnNumber returns a context carrying the current turn number.
// A "turn" is one model call within a single Complete lifecycle.
func WithTurnNumber(ctx context.Context, turn int) context.Context {
	return context.WithValue(ctx, turnNumberContextKey{}, turn)
}

// TurnNumber returns the current turn number and whether it was set.
func TurnNumber(ctx context.Context) (int, bool) {
	v := ctx.Value(turnNumberContextKey{})
	turn, ok := v.(int)
	return turn, ok
}
