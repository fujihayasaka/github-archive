// Package roundrobin implements a round-robin load balancing strategy for multiple LLM models.
package roundrobin

import (
	"context"
	"fmt"
	"math"
	"math/rand"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/github/code-scanning-ai-libraries/v4/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v4/errors"
	"github.com/github/code-scanning-ai-libraries/v4/llm/models"
)

type modelState struct {
	model             models.Model
	activeRequests    int
	completedRequests int
	durations         []time.Duration
}

// Model implements a load balancing strategy across multiple LLM models.
type Model struct {
	states      []*modelState
	inputModels []models.Model
	mu          sync.Mutex
	lastIndex   int
}

// NewRoundRobinModel creates a new RoundRobinModel with the provided models.
// The models are shuffled to avoid always using the same one first.
func NewRoundRobinModel(ms []models.Model) (*Model, errors.LLMError) {
	if len(ms) == 0 {
		return nil, errors.NewError("no models provided", errors.ErrorTypeLogic)
	}

	// Shuffle the models to avoid always using the same one.
	shuffled := make([]models.Model, len(ms))
	perm := rand.Perm(len(ms))
	for i, v := range perm {
		shuffled[v] = ms[i]
	}

	states := make([]*modelState, len(shuffled))
	for i, m := range shuffled {
		states[i] = &modelState{
			model:     m,
			durations: make([]time.Duration, 0, 10),
		}
	}

	return &Model{
		states:      states,
		inputModels: ms, // keeping the specified input around, to make `GetModelName` and `GetProviderName` deterministic
		lastIndex:   -1,
	}, nil
}

// Complete performs a completion with tools support using one of the underlying models.
// The model is selected based on current load (active request count, weighted by average response time after warmup), with round-robin selection among models with similar load.
func (r *Model) Complete(ctx context.Context, prompt []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.RoundRobinModel.Complete")
	defer span.End()

	if len(r.states) == 0 {
		return "", nil, nil, errors.NewError("no models available", errors.ErrorTypeLogic)
	}

	r.mu.Lock()
	selectedState, selectedIndex := r.selectModel()
	selectedState.activeRequests++
	r.lastIndex = selectedIndex
	r.mu.Unlock()

	start := time.Now()
	resp, msgs, usage, err := selectedState.model.Complete(ctx, prompt, tools, options)
	duration := time.Since(start)

	r.mu.Lock()
	selectedState.activeRequests--
	selectedState.completedRequests++
	selectedState.durations = append(selectedState.durations, duration)
	if len(selectedState.durations) > 10 {
		selectedState.durations = selectedState.durations[1:]
	}
	r.mu.Unlock()

	return resp, msgs, usage, err
}

func (r *Model) selectModel() (*modelState, int) {
	// Determine whether to use timing-based load calculation (weighted by average duration) or simple active request count.
	// Timing bias is only used after warmup (>= 4 completed requests per model).
	useBias := r.shouldUseBiasedTiming()

	candidates := r.findLeastLoadedCandidates(useBias)

	// Round-robin among candidates
	// We want to pick the next candidate after r.lastIndex
	// iterate through the circle starting from r.lastIndex + 1
	// and pick the first one that is in candidates.
	n := len(r.states)
	for i := 1; i <= n; i++ {
		idx := (r.lastIndex + i) % n
		if slices.Contains(candidates, idx) {
			return r.states[idx], idx
		}
	}

	// Should not happen if candidates is not empty
	return r.states[candidates[0]], candidates[0]
}

// findLeastLoadedCandidates returns the indices of models tied for the lowest computed load score.
func (r *Model) findLeastLoadedCandidates(useBias bool) []int {
	bestScore := math.MaxFloat64
	candidates := make([]int, 0, len(r.states))

	for i, state := range r.states {
		var score float64

		var totalDuration time.Duration
		for _, d := range state.durations {
			totalDuration += d
		}
		if useBias { // determine the load based on average duration, but only if we have enough data
			avgDurationSeconds := totalDuration.Seconds() / float64(len(state.durations))
			score = float64(state.activeRequests) * avgDurationSeconds
		} else {
			score = float64(state.activeRequests)
		}

		if score < bestScore {
			bestScore = score
			candidates = candidates[:0]
			candidates = append(candidates, i)
		} else if math.Abs(score-bestScore) < 1e-9 {
			candidates = append(candidates, i)
		}
	}

	return candidates
}

// shouldUseBiasedTiming reports whether every model has enough warmup history to enable duration-weighted load.
func (r *Model) shouldUseBiasedTiming() bool {
	for _, s := range r.states {
		if s.completedRequests < 4 {
			return false
		}
	}
	return true
}

// GetModelName returns a descriptive name that includes all underlying model names.
func (r *Model) GetModelName() string {
	modelsList := r.inputModels
	seen := make(map[string]struct{}, len(modelsList))
	unique := make([]string, 0, len(modelsList))
	for _, m := range modelsList {
		name := m.GetModelName()
		if _, ok := seen[name]; ok {
			continue
		}
		seen[name] = struct{}{}
		unique = append(unique, name)
	}
	return fmt.Sprintf("RoundRobin<%s>", strings.Join(unique, ", "))
}

// GetProviderName returns a descriptive provider name that includes all underlying model provider names.
func (r *Model) GetProviderName() string {
	modelsList := r.inputModels
	seen := make(map[string]struct{}, len(modelsList))
	unique := make([]string, 0, len(modelsList))
	for _, m := range modelsList {
		name := m.GetProviderName()
		if _, ok := seen[name]; ok {
			continue
		}
		seen[name] = struct{}{}
		unique = append(unique, name)
	}
	return fmt.Sprintf("RoundRobin<%s>", strings.Join(unique, ", "))
}
