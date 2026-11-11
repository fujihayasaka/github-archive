package jobservice

import (
	"context"
	"errors"
	"slices"
	"strconv"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	jobExperiments "github.com/github/sweagentd/internal/jobs/experiments"
)

var errMissingPullRequestID = goerrors.New("pull request ID is empty")

// SetExperimentAssignmentsForJob is a wrapper for the experimentClient.GetFeatureAssignment call
// that handles setting the randomization unit and traffic filters for the job as well as setting
// the experiment assignment context and variations on the assignment and job for the given feature.
//
// This is designed to take a string of feature names for convenience to minimize the number of patches
// made to the job and assignment when experiments are being applied in the same place.
func (s *Service) SetExperimentAssignmentsForJob(ctx context.Context, featureNames []string, jobAssignment *jobs.Assignment, job *jobs.Job) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.SetExperimentAssignmentsForJob")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("setting experiment assignments for job")

	trafficFilters, err := s.experiments.NewTrafficFiltersDefaults(ctx, s.twirp, &experiments.FilterProps{
		RepoID: job.RepoID,
		OrgID:  job.OwnerID,
		UserID: job.ActorID,
	})
	if err != nil {
		return err
	}

	// Create experiment patch, preserving any existing assignments
	patchExp := &jobExperiments.AssignmentExperiments{
		Variations: make(map[string]any),
	}
	var misses []string
	for _, featureName := range featureNames {
		randomizationUnit, err := randomizationUnitForExperiment(featureName, job)
		if err != nil {
			if errors.Is(err, errMissingPullRequestID) {
				continue
			}
			s.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("skipping experiment due to missing randomization unit",
				kvp.String("feature", featureName))
			misses = append(misses, featureName)
			continue
		}

		expAssignment, found := s.experiments.GetFeatureAssignment(ctx, featureName, randomizationUnit, trafficFilters)
		if !found {
			misses = append(misses, featureName)
			continue
		}
		patchExp.Variations[featureName] = expAssignment.Variation
		patchExp.AssignmentContext = expAssignment.Context
	}

	if len(misses) > 0 {
		s.obsv.LoggerWithTelemetry(ctx).Error("failed to get experiment assignments for features", kvp.Strings("missingExperiments", misses))
	}

	// Preserve existing experiment assignments
	if job.Experiments != nil && job.Experiments.Variations != nil {
		for k, v := range job.Experiments.Variations {
			if !slices.Contains(featureNames, k) {
				patchExp.Variations[k] = v
			}
		}
	}

	jobAssignment.Experiments = patchExp
	job.Experiments = jobAssignment.Experiments

	return nil
}

// randomizationUnitForExperiment returns the appropriate TrafficFilter to use as
// the randomization unit for the given experiment, based on the experiment's
// configured RandomizationUnitType.
func randomizationUnitForExperiment(featureName string, job *jobs.Job) (*experiments.TrafficFilter, error) {
	switch experiments.GetRandomizationUnitType(featureName) {
	case experiments.RandomizeByTrackingID:
		if job.ActorAnalyticsTrackingID == "" {
			return nil, goerrors.New("actor analytics tracking ID is empty")
		}
		return &experiments.TrafficFilter{
			Header: experiments.CopilotTrackingIDHeader,
			Value:  job.ActorAnalyticsTrackingID,
		}, nil
	case experiments.RandomizeByRepoID:
		if job.RepoID == 0 {
			return nil, goerrors.New("repo ID is empty")
		}
		return &experiments.TrafficFilter{
			Header: experiments.CopilotRepositoryHeader,
			Value:  strconv.FormatInt(job.RepoID, 10),
		}, nil
	default:
		if job.PullRequestID == 0 {
			return nil, errMissingPullRequestID
		}
		return &experiments.TrafficFilter{
			Header: experiments.GitHubPullRequestIDHeader,
			Value:  strconv.FormatInt(job.PullRequestID, 10),
		}, nil
	}
}
