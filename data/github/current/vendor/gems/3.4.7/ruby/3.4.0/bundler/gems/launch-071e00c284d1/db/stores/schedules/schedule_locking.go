// Schedule Locking Scheme
//
// This is a pessimistic locking scheme implemented using the `locked_by` and `locked_at` columns.
// To avoid database contention, we use `SELECT ... FOR UPDATE SKIP LOCKED` then `UPDATE` to lock the schedules in a transaction:
//
// 1. Use `SELECT ... FOR UPDATE SKIP LOCKED` to find rows are that are due to run and are not locked.
// 2. Sort them by weighted priority and determine the ones to lock.
// 3. Lock only the ones we are going to run by using `UPDATE` to set `locked_by` and `locked_at`.
//
// Then we `SELECT` the rows that were locked to retrieve what we need to queue the schedules.
//
// After a schedule is queued, we update the `next_run_at` column to the next time the schedule should run and unlock the row.
//
// We couldn't do this via a optimistic scheme: build queueing is not idempotent, so we need to ensure
// only a single worker attempts each scheduled invocation.
//
// There is a separate periodic job that unlocks stale rows - i.e rows that have remained locked for a long time.
package schedules

import (
	"context"
	"database/sql"
	"fmt"
	"sort"
	"strconv"
	"time"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability/kvperrors"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/deploy/scheduled/model"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
)

// Scale factor for scattering of scheduled workflows below tier 1
const tierScatterScaleFactor = 2

// Batch size for unlocking stale schedules
const unlockStaleBatchSize = 100

// These are type `time.Duration` to avoid casting when we use the values
// `time.Duration` represents elapsed time as nanoseconds, but that's irrelevant here as the values are used as multipliers
var tierWeightMultipliers = map[types.RepositoryTier]time.Duration{
	types.RepositoryTier1: 12,
	types.RepositoryTier2: 4,
	types.RepositoryTier3: 1,
}

type ScheduleRun struct {
	ID                 uint64
	RepositoryNodeID   types.GlobalID
	OwnerID            int64
	Schedule           string
	ActorNodeID        types.GlobalID
	ActorLogin         string
	CommitSHA          types.CommitSha
	WorkflowIdentifier string
	WorkflowFilePath   string
	NextRunAt          *time.Time
	Tier               types.RepositoryTier
	TierUpdatedAt      *time.Time
	GitHubTenantID     *int64
}

func weightedAge(now time.Time, nextRunAt *time.Time, tier types.RepositoryTier) time.Duration {
	if nextRunAt == nil {
		return 0 // Should not happen, but were it to, a schedule with no next run has no "age"
	}

	multiplier, ok := tierWeightMultipliers[tier]
	if ok {
		return now.Sub(*nextRunAt) * multiplier
	}

	return now.Sub(*nextRunAt)
}

type scheduleCandidate struct {
	ID          uint64
	NextRunAt   *time.Time
	Tier        types.RepositoryTier
	WeightedAge time.Duration
}

func (r *dbStore) FindAndLock(ctx context.Context, workerID string, tasksPerTick int) ([]ScheduleRun, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	now := time.Now()
	schedulesToRunIDs := make([]any, 0, tasksPerTick)
	tiersCount := [3]int{0, 0, 0}

	err := mysqldb.WithTransaction(ctx, r.DB.Conn(), r.obs.Statter, "FindAndLock", func(tx *sql.Tx) error {
		var candidates []scheduleCandidate
		var err error
		candidates, tiersCount, err = r.findPrioritizedCandidates(ctx, tx, tasksPerTick, now)

		if err != nil {
			return err
		}

		if len(candidates) == 0 {
			return nil
		}

		// Lock the schedules in the database
		schedulesToRunIDs, err = r.lockSchedules(ctx, tx, workerID, candidates)
		if err != nil {
			return errors.Wrap(err, "failed to lock schedules")
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	if len(schedulesToRunIDs) == 0 {
		return nil, nil
	}

	// Fetch the schedules we just locked
	schedules, err := r.retrieveSchedules(ctx, schedulesToRunIDs)
	if err != nil {
		// These rows won't be unlocked until the unlock stale job runs
		return nil, err
	}

	r.obs.Logger.Debug(ctx, "schedules loaded",
		kvp.Int("gh.launch.schedule.tier1.count", tiersCount[0]),
		kvp.Int("gh.launch.schedule.tier2.count", tiersCount[1]),
		kvp.Int("gh.launch.schedule.tier3.count", tiersCount[2]),
		kvp.Int("gh.launch.schedule.running.count", len(schedules)),
	)

	return schedules, nil
}

// lockSchedules locks the `candidates` by setting `locked_by` and `locked_at` for the rows in the database
func (r *dbStore) lockSchedules(ctx context.Context, tx *sql.Tx, workerID string, candidates []scheduleCandidate) ([]any, error) {
	schedulesToLockLen := len(candidates)
	schedulesToRunIDs := make([]any, 0, schedulesToLockLen)

	if schedulesToLockLen == 0 {
		return schedulesToRunIDs, nil
	}

	for _, s := range candidates {
		schedulesToRunIDs = append(schedulesToRunIDs, s.ID)
	}

	updateSQL := `
		UPDATE workflow_schedules
		SET locked_by = ?,
			locked_at = UTC_TIMESTAMP
		WHERE id IN (` + mysqldb.Placeholders(schedulesToLockLen) + `)
	`

	updateParams := make([]any, 0, schedulesToLockLen+1)
	updateParams = append(updateParams, workerID)
	updateParams = append(updateParams, schedulesToRunIDs...)

	_, err := r.DB.ExecTx(ctx, tx, updateSQL, asql.WithName("LockSchedules"), updateParams...)
	if err != nil {
		return nil, err
	}

	return schedulesToRunIDs, nil
}

// findPrioritizedCandidates finds the schedules that should run next
// Returns the schedules, the number of schedules for each tier, and any error
func (r *dbStore) findPrioritizedCandidates(
	ctx context.Context,
	tx *sql.Tx,
	tasksPerTick int,
	now time.Time,
) ([]scheduleCandidate, [3]int, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	candidates := make([]scheduleCandidate, 0, tasksPerTick*2)
	var minWeightedAge time.Duration // default 0
	var tiersCount [3]int

	// Fetch up to `tasksPerTick` candidates for each tier and sort by weighted age to find the top `tasksPerTick` candidates overall
	// If we already have `tasksPerTick` candidates, for the next tier we only find schedules that are
	// weighted higher than the lowest weighted candidate by keeping track of the `minWeightedAge`.
	// Otherwise we find `tasksPerTick` candidates that are due to run
	for _, tier := range []types.RepositoryTier{types.RepositoryTier1, types.RepositoryTier2, types.RepositoryTier3} {
		minNextRunAt := now

		// If we do not have `tasksPerTick` candidates yet, candidates from this tier do not necessarily need to be weighted higher than the `minWeightedAge`
		if len(candidates) >= tasksPerTick {
			tierMultiplier, ok := tierWeightMultipliers[tier]
			if !ok {
				tierMultiplier = 1
			}

			// minNextRunAt from a minWeightedAge is calculated as:
			//
			//	weightedAge > minWeightedAge
			//	(now - minNextRunAt) * tierMultiplier > minWeightedAge
			//	now - minNextRunAt > minWeightedAge / tierMultiplier
			//	minNextRunAt < now - (minWeightedAge / tierMultiplier)
			minNextRunAt = now.Add(-minWeightedAge / tierMultiplier)
		}

		name := fmt.Sprintf("FindForTierWeighted_Tier%v", tier)
		candidatesForTier, err := r.findForTier(ctx, tx, tier, tasksPerTick, now, minNextRunAt, name)
		if err != nil {
			return nil, tiersCount, err
		}

		if len(candidatesForTier) == 0 {
			tiersCount[tier-1] = 0
			continue
		}

		candidates = append(candidates, candidatesForTier...)

		// Take only the top weighted `tasksPerTick` schedules, update minWeightedAge
		// We do not need to update minWeightedAge when len(candidates) < tasksPerTick because it will not be used for the next tier
		if len(candidates) == tasksPerTick {
			// Since the schedule with the previous minWeightedAge is still a candidate,
			//  and all schedules in `candidatesForTier` are included in the top `tasksPerTick` candidates,
			//  we can skip sorting and only need to update `minWeightedAge` if the lowest of this tier is lower
			minWeightedAgeForTier := candidatesForTier[len(candidatesForTier)-1].WeightedAge
			// always update minWeightedAge if it is the default value 0
			if minWeightedAge == 0 || minWeightedAgeForTier < minWeightedAge {
				minWeightedAge = minWeightedAgeForTier
			}
		} else if len(candidates) > tasksPerTick {
			// The new `minWeightedAge` schedule may not necessarily be the previous `minWeightedAge` schedule
			//  or the `minWeightedAgeSchedule` in the top `tasksPerTick` candidates, so we need to sort to find the new `minWeightedAge`

			// Sort `candidates` by weighted age, only take the top tasksPerTick schedules
			sort.Slice(candidates, func(i, j int) bool {
				return candidates[i].WeightedAge > candidates[j].WeightedAge
			})
			candidates = candidates[:tasksPerTick]

			minWeightedAge = candidates[len(candidates)-1].WeightedAge
		}
		tiersCount[tier-1] = len(candidatesForTier)
	}

	return candidates, tiersCount, nil
}

// findForTier finds up to `tasksPerTick` schedules that are due to run before `minNextRunAt`
func (r *dbStore) findForTier(
	ctx context.Context,
	tx *sql.Tx,
	tier types.RepositoryTier,
	tasksPerTick int,
	now time.Time,
	minNextRunAt time.Time,
	name string,
) ([]scheduleCandidate, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const selectForUpdateSQL = `
		SELECT id, next_run_at
		FROM workflow_schedules
		WHERE locked_by IS NULL
			AND environment = ?
			AND tier = ?
			AND next_run_at <= ?
		ORDER BY next_run_at ASC
		LIMIT ?
		FOR UPDATE SKIP LOCKED
	`

	params := []any{r.Cfg.Environment, tier, minNextRunAt, tasksPerTick}
	rows, err := r.DB.QueryTx(ctx, tx, selectForUpdateSQL, asql.WithName(name), params...)
	if err != nil {
		return nil, errors.Wrap(err, "failed to find schedule rows")
	}

	defer rows.Close()

	candidates := make([]scheduleCandidate, 0, tasksPerTick)

	for rows.Next() {
		candidate := scheduleCandidate{
			Tier: tier,
		}
		err := rows.Scan(&candidate.ID, &candidate.NextRunAt)
		if err != nil {
			return nil, errors.Wrap(err, "failed to load schedule candidate row")
		}

		// Precompute weighted age for later sorting
		candidate.WeightedAge = weightedAge(now, candidate.NextRunAt, candidate.Tier)
		candidates = append(candidates, candidate)
	}

	if rows.Err() != nil {
		return nil, errors.Wrap(rows.Err(), "failed to find schedule rows")
	}

	return candidates, nil
}

func (r *dbStore) retrieveSchedules(ctx context.Context, ids []any) ([]ScheduleRun, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	selectSQL := `
		SELECT
			id,
			schedule,
			commit_sha,
			actor_node_id,
			actor_login,
			repository_node_id,
			owner_id,
			workflow_identifier,
			workflow_file_path,
			next_run_at,
			tier,
			tier_updated_at
		FROM workflow_schedules
		WHERE id IN (` + mysqldb.Placeholders(len(ids)) + `)
	`

	rows, err := r.DB.QueryContextWith(ctx, selectSQL, asql.WithName("SelectLockedSchedules"), ids...)
	if err != nil {
		return nil, errors.Wrap(err, "failed to retrieve rows for IDs")
	}
	defer rows.Close()

	schedules := make([]ScheduleRun, 0, len(ids))

	var ownerID sql.NullInt64

	for rows.Next() {
		schedule := ScheduleRun{}
		err = rows.Scan(
			&schedule.ID,
			&schedule.Schedule,
			&schedule.CommitSHA,
			&schedule.ActorNodeID,
			&schedule.ActorLogin,
			&schedule.RepositoryNodeID,
			&ownerID,
			&schedule.WorkflowIdentifier,
			&schedule.WorkflowFilePath,
			&schedule.NextRunAt,
			&schedule.Tier,
			&schedule.TierUpdatedAt,
		)

		if ownerID.Valid && ownerID.Int64 > 0 {
			schedule.OwnerID = ownerID.Int64
		} else {
			schedule.OwnerID = 0
		}

		if err != nil {
			return nil, errors.Wrap(err, "failed to load schedule row")
		}
		schedules = append(schedules, schedule)
	}

	if rows.Err() != nil {
		return nil, errors.Wrap(rows.Err(), "failed to retrieve rows for IDs")
	}

	return schedules, nil
}

func (r *dbStore) UnlockStale(ctx context.Context) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	for {
		rowsAffected, err := r.unlockStale(ctx)
		if err != nil {
			return err
		}
		if rowsAffected < unlockStaleBatchSize {
			break
		}
	}
	return nil
}

func (r *dbStore) unlockStale(ctx context.Context) (int64, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var rowsAffected int64
	err := mysqldb.WithTransaction(ctx, r.DB.Conn(), r.obs.Statter, "SelectAndUnlockStale", func(tx *sql.Tx) error {
		const selectName = "SelectStale"
		selectSQL := `
			SELECT id
			FROM workflow_schedules
			WHERE locked_at < ?
				AND environment = ?
			LIMIT ?
			FOR UPDATE SKIP LOCKED
		`

		params := []any{time.Now().UTC().Add(-r.Cfg.ReassignWorkAfterDuration), r.Cfg.Environment, unlockStaleBatchSize}

		rows, err := r.DB.QueryTx(ctx, tx, selectSQL, asql.WithName(selectName), params...)

		if err != nil {
			return kvperrors.WrapWith(
				errors.Wrap(err, "failed to select stale"),
				kvp.String("code.function", selectName),
			)
		}

		defer rows.Close()

		ids := make([]any, 0)
		for rows.Next() {
			var id int64
			err = rows.Scan(&id)
			if err != nil {
				return err
			}
			ids = append(ids, id)
		}

		if rows.Err() != nil {
			return rows.Err()
		}

		if len(ids) == 0 {
			r.obs.Logger.Debug(ctx, "unlocked stale schedules", kvp.Int("count", 0))
			return nil
		}

		updateSQL := `
			UPDATE workflow_schedules
			SET locked_by = NULL,
				locked_at = NULL
			WHERE id IN (` + mysqldb.Placeholders(len(ids)) + `)
		`
		const updateName = "UnlockStale"

		res, err := r.DB.ExecTx(ctx, tx, updateSQL, asql.WithName(updateName), ids...)

		if err != nil {
			return kvperrors.WrapWith(
				errors.Wrap(err, "failed to update stale"),
				kvp.String("code.function", updateName),
			)
		}

		if c, err := res.RowsAffected(); err == nil {
			rowsAffected = c
			r.obs.Statter.Counter(ctx, "scheduled.unlockedStale", nil, c)
			r.obs.Logger.Debug(ctx, "unlocked stale schedules", kvp.Int("count", int(c)))
		}

		return nil
	})

	if err != nil {
		return 0, errors.Wrap(err, "failed to complete transaction")
	}

	return rowsAffected, nil
}

func (r *dbStore) ScheduleNextRun(ctx context.Context, run ScheduleRun) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	// Note: this doesn't validate count of rows affected. Schedule changes can cause
	// our row to get deleted in between lock and this, which is fine.
	const updateSQL = `
		UPDATE workflow_schedules
		SET locked_by = NULL,
			locked_at = NULL,
			next_run_at = DATE_ADD(?, INTERVAL (scatter_offset * ?) SECOND),
			tier = ?,
			tier_updated_at = ?
		WHERE id = ?
	`

	schedule, err := r.ScheduleParser.ParseExpression(run.Schedule)
	if err != nil {
		return kvperrors.WrapWith(
			errors.Wrap(err, "failed to parse expression"),
			kvp.String("code.function", "scheduler_parse"),
		)
	}

	now := r.clock.Now().UTC()
	var tierUpdatedAt time.Time
	if run.TierUpdatedAt != nil {
		tierUpdatedAt = *run.TierUpdatedAt
	}
	const name = "ScheduleNextRun"
	_, err = mysqldb.WithDeadlockRetry(ctx, name, r.obs.Statter, func() (sql.Result, error) {
		nextRun := schedule.Next(now)
		return r.DB.ExecContextWith(
			ctx,
			updateSQL,
			asql.WithName(name),
			nextRun,
			scaleScatterOffsetByTier(run.Tier, r.Cfg.ScatterOffsetDuration.Seconds()),
			run.Tier,
			tierUpdatedAt,
			run.ID,
		)
	})
	if err != nil {
		return kvperrors.WrapWith(
			errors.Wrap(err, "failed to schedule next run"),
			kvp.String("code.function", name),
		)
	}

	if run.NextRunAt != nil {
		skippedRuns := computeSkippedRuns(schedule, *run.NextRunAt, now)
		r.obs.Statter.Counter(ctx, "scheduled.skippedRuns", statter.Tags{"tier": strconv.Itoa(int(run.Tier))}, skippedRuns)
	}

	return nil
}

func computeSkippedRuns(schedule model.Schedule, from time.Time, actualRun time.Time) int64 {
	skippedRuns := 0
	nextRun := schedule.Next(from)

	for nextRun.Before(actualRun) {
		skippedRuns++
		nextRun = schedule.Next(nextRun)
	}

	return int64(skippedRuns)
}

func scaleScatterOffsetByTier(tier types.RepositoryTier, offsetDuration float64) float64 {
	scaledOffsetDuration := offsetDuration
	if tier != types.RepositoryTier1 {
		scaledOffsetDuration *= tierScatterScaleFactor
	}
	return scaledOffsetDuration
}
