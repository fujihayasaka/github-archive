package managedanalyses

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/pkg/errors"
)

// UpdateRepoLanguages updates the CodeqlConfig for a repository and returns the workflow id
// of the last relevant validation run.
func (ma *ManagedAnalyses) UpdateRepoLanguages(ctx context.Context, repoID ts.RepositoryEID, supportedLanguages ts.Languages, languagesAdded ts.Languages, languagesRemoved ts.Languages, defaultRef []byte, ownerID ts.OwnerEID, codeqlPacks ts.CodeqlPacks) (ts.WorkflowRunEID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	bot, err := ma.GetBotActor(ctx)
	if err != nil {
		return 0, errors.Wrap(err, "couldn't get bot actor")
	}

	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	if err != nil {
		return 0, err
	}

	currentSelectedLanguages := make(ts.Languages, 0)
	if codeqlRepo.CurrentConfig != nil {
		currentSelectedLanguages = codeqlRepo.CurrentConfig.Languages
	}
	newSelectedLanguages, _ := computeSelectedLanguages(currentSelectedLanguages, languagesAdded, languagesRemoved)

	return ma.updateRepo(
		ctx,
		codeqlRepo,
		ts.CodeqlRunTriggeringEvent_LANGUAGES_CHANGE,
		supportedLanguages,
		&newSelectedLanguages,
		nil,
		nil,
		defaultRef,
		ownerID,
		codeqlPacks,
		bot,
		codeqlRepo.UsingCSRunnerLabel,
		codeqlRepo.RunnerLabel,
	)
}

func computeSelectedLanguages(initial, added, removed ts.Languages) (ts.Languages, bool) {
	noop := true
	languagesMap := map[string]bool{}
	for _, lang := range initial {
		languagesMap[lang] = true
	}
	for _, lang := range added {
		if !languagesMap[lang] {
			languagesMap[lang] = true
			noop = false
		}
	}
	for _, lang := range removed {
		if languagesMap[lang] {
			languagesMap[lang] = false
			noop = false
		}
	}

	languages := []string{}
	for lang, keep := range languagesMap {
		if keep {
			languages = append(languages, lang)
		}
	}

	return languages, noop
}
