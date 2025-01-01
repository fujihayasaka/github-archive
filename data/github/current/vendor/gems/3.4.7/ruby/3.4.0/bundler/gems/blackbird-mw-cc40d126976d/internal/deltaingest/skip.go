package deltaingest

import (
	"context"
	"errors"

	"github.com/github/blackbird/crates/core/pkg/epoch"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

// Set of repos not suitable for indexing. Keyed by repository ID.
//
// NOTE: IDs are only valid for dotcom.
var repoDenyList = map[routing.Stamp]map[types.RepoID]bool{
	routing.Dotcom: {
		1409811:   true, // The cdnjs/cdnjs network
		273106075: true, // feedarchive/libera-newsbot-live
		106601653: true, // Katee/git-bomb
		487308156: true, // jakwings/.github (contains a git bomb)
	},
}

// Set of owners not suitable for indexing. Keyed by owner ID.
//
// NOTE: IDs are only valid for dotcom.
var ownerDenyList = map[routing.Stamp]map[uint32]bool{
	routing.Dotcom: {
		56326858: true, // dandisets
		99900493: true, // dandizaars
		4600091:  true, // tpb-archive (torrent data archive)
	},
}

// Set of repository networks not suitable for indexing. Keyed by network ID.
//
// NOTE: IDs are only valid for dotcom.
var networkDenyList = map[routing.Stamp]map[types.NetworkID]bool{
	routing.Dotcom: {
		1409811:   true, // The cdnjs/cdnjs network
		158612282: true, // network of Katee/git-bomb
		454712548: true, // network of jakwings/.github (contains a git bomb)
		2365549:   true, // The CocoaPods/Specs (package management) network
		451803487: true, // mZpB7W6wPuAwTqUf7Apy9X22/batch-7-gdmsr3 (private repo)
		206741917: true, // rikanakai0823/bangumi-data (private repo)
	},
}

func isRepoIDDenied(repoID types.RepoID, stamp routing.Stamp) bool {
	return repoDenyList[stamp][repoID]
}

func isOwnerIDDenied(ownerID uint32, stamp routing.Stamp) bool {
	return ownerDenyList[stamp][ownerID]
}

func isNetworkIDDenied(networkID types.NetworkID, stamp routing.Stamp) bool {
	return networkDenyList[stamp][networkID]
}

func isTooLarge(diskSizeBytes uint64) bool {
	// TODO: Handle cases of toggling in and out of the limit by having two
	// different thresholds.
	//
	// NOTE: DiskUsage calculations are delayed and cached so it's possible for
	// this field to be wrong. For this reason, we ignore DiskUsage of zero.
	//
	// Max repo size on disk that will be processed is 100 GiB
	const maxRepoSizeInBytes = 100 * 1024 * 1024 * 1024
	return diskSizeBytes > maxRepoSizeInBytes
}

// Returns a skipError if the task should be skipped. This can be evaluated
// BEFORE fetching the repository information.
func shouldSkipTask(task *Task) *db.SkipReason {
	if task.event.BlackbirdTargetCorpus != "" {
		target, err := routing.CorpusFromString(task.event.BlackbirdTargetCorpus)
		if err != nil {
			return &db.SkipInvalidTargetCorpus
		}

		if target != task.corpus.Corpus {
			return &db.SkipNotTargetCorpus
		}
	}

	if isRepoIDDenied(task.repoID(), task.stamp) {
		return &db.SkipRepoDenyList
	}

	return nil
}

// Returns a shouldSkipRepository if the repository should be skipped (due to ban lists,
// etc.).
//
// NOTE: These skips must happen after fetching the github.Repository because we
// don't know the true values until then.
func shouldSkipRepository(repo *github.Repository, state db.RepoInfoState, topic string, stamp routing.Stamp, epochMode epoch.EpochMode) *db.SkipReason {
	if isTooLarge(repo.DiskUsageBytes()) {
		return &db.SkipMaxDiskSize
	}

	if isNetworkIDDenied(repo.NetworkID, stamp) {
		return &db.SkipNetworkDenyList
	}

	if epoch.EpochFeaturesOnlyEmbeddings.SupportedBy(epochMode) {
		_, codeEmbeddings := repo.Experiments[experiments.EnableCodeEmbedding]
		_, docsEmbeddings := repo.Experiments[experiments.EnableDocsEmbedding]

		if !(codeEmbeddings || docsEmbeddings) {
			return &db.SkipEmbeddingsDisabled
		}
	}

	if isOwnerIDDenied(repo.OwnerID, stamp) {
		return &db.SkipOwnerDenyList
	}

	// Only index existing repositories UNLESS this is an onboarding or backfill
	// message (we index all of these) or a new repo for a paying customer.
	if state == db.RepoInfoStateExisting {
		return nil
	}

	if topic == routing.OnboardSourceTopic || routing.IsBackfillTopic(topic) {
		return nil
	}

	if repo.PayingCustomer {
		return nil
	}

	return &db.SkipUnknownRepo
}

func status(skip *db.SkipReason, err error) string {
	if err != nil {
		switch {
		case errors.Is(err, context.Canceled):
			return "cancelled"
		default:
			return "error"
		}
	}

	if skip != nil {
		return "skipped"
	}

	return "success"
}

// maxBlobLocationsOverrideRepos stores repo IDs that we manually want to allow
// to have a larger blob/location limit. This should only be done for important
// repositories that are excluded by our normal limits.
var maxBlobLocationsOverrideRepos = map[types.RepoID]bool{
	6223686:   true, // Canva/canva
	542158940: true, // mono-uberint/go-code
	90689572:  true, // aiming/mq see https://github.com/github/blackbird/issues/4268
	27447564:  true, // glg/SqlServers, see https://github.com/github/blackbird/issues/5108
	671549390: true, // as1299/salesforce-archive-04082023, see: https://github.com/github/blackbird/issues/5677
	771365464: true, // ncratleos-it-cio/edw-pipeline, see: https://github.com/github/blackbird/issues/6423
	770132230: true, // gree-platform/land, see: https://github.com/github/blackbird/issues/7378
	616702163: true, // dropbox-internal/server, see: https://github.com/github/blackbird/issues/9047
	926756717: true, // cisco-csg/polaris, see: https://github.com/github/blackbird/issues/9108
}

// maxBlobLocations returns the number of path/blob locations allowed for a
// repository based on its importance.
func maxBlobLocations(repoID types.RepoID, numStars int32, payingCustomer bool) int {
	const (
		// maxBlobLocationsOverride is the max upper bound blob/path location limit
		// for repositories opted into the override.
		maxBlobLocationsOverride = 1_250_000

		// maxBlobLocationsImportant is the maximum number of blob/path locations
		// allowed in an "important" repository before that repo is skipped for ingest.
		//
		// As of epoch 204, this value is approximately 99.999th percentile of
		// repository size.
		//
		// See: https://github.com/github/blackbird-mw/issues/1493#issuecomment-1318440625
		maxBlobLocationsImportant = 600_000

		// maxBlobLocationsStandard is a lower limit for less important repos,
		// near the 99.9th percentile for repository size.
		//
		// See: https://github.com/github/blackbird-mw/issues/1493#issuecomment-1318440625
		maxBlobLocationsStandard = 75_000

		// minImportantStars is a SWAG for what makes a public repo "important".
		// Fewer than 1.5% of all public repos have 5 or more stars as of late
		// 2022.
		//
		// See: https://data.githubapp.com/sql/f189fdfa-2334-4146-8e03-b0eb94532a56
		minImportantStars = 5
	)

	if maxBlobLocationsOverrideRepos[repoID] {
		return maxBlobLocationsOverride
	}

	if payingCustomer || numStars >= minImportantStars {
		return maxBlobLocationsImportant
	}

	return maxBlobLocationsStandard
}
