import type {FC} from 'react'
import {useCallback, useEffect, useMemo, useState} from 'react'
import {ReposSelector} from '@github-ui/repos-selector'
import {MultiSelectReposPicker} from '@github-ui/repos-picker'
import type {PickerRepository} from '@github-ui/repos-picker'
import type {SimpleRepository, RepositoryIdConditionMetadata, RepositoryIdParameters} from '../../../types/rules-types'
import {getRepoSuggestionsForOrg} from '../../../services/api'
import {useRelativeNavigation} from '../../../hooks/use-relative-navigation'
import {TargetsTable, type IncludeExcludeType} from '../TargetsTable'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useParams} from 'react-router-dom'

interface RepositoryIdTargetProps {
  readOnly: boolean
  parameters: RepositoryIdParameters
  metadata?: RepositoryIdConditionMetadata
  updateParameters: (parameters: RepositoryIdParameters) => void
  headerRowText?: string
  excludePublicRepos?: boolean
  blankslate: {
    heading: string
    description?: React.ReactNode
  }
}

export const RepositoryIdTarget: FC<RepositoryIdTargetProps> = ({
  readOnly,
  parameters,
  metadata,
  updateParameters,
  headerRowText,
  excludePublicRepos = false,
  blankslate,
}) => {
  const [fetchedMetadata, setFetchedMetadata] = useState<SimpleRepository[]>([])
  const isReposPicker = useFeatureFlag('repos_picker_in_ruleset')

  const selectedRepos = useMemo(() => {
    const reposById = (metadata?.repositories || []).concat(fetchedMetadata).reduce(
      (acc, repo) => {
        acc[repo.nodeId] = repo
        return acc
      },
      {} as Record<string, SimpleRepository>,
    )

    return parameters.repository_ids.reduce((acc, id) => {
      if (reposById[id]) {
        acc.push(reposById[id])
      }
      return acc
    }, [] as SimpleRepository[])
  }, [metadata, parameters, fetchedMetadata])

  const {resolvePath} = useRelativeNavigation()

  const queryForRepos = async (query: string) => {
    return await getRepoSuggestionsForOrg(resolvePath('repo_suggestions'), {
      query,
      excludePublicRepos,
    })
  }

  const changeRepositories = useCallback(
    async (newRepos: SimpleRepository[]) => {
      if (readOnly) {
        return
      }

      updateParameters({
        repository_ids: newRepos.map(r => r.nodeId),
      })
      setFetchedMetadata(newRepos)
    },
    [readOnly, updateParameters],
  )

  const removeRepository = (repoNodeId: string) => {
    if (readOnly) {
      return
    }
    const newRepoIds = parameters.repository_ids.filter(r => r !== repoNodeId)

    updateParameters({
      repository_ids: newRepoIds,
    })
  }

  // If the server does not return the full set of repos that are currently configured, this most likely
  // means that a repo has been deleted or moved outside of the Organization. In this case, remove it from the
  // condition so we do not fail ruleset save
  useEffect(() => {
    if (selectedRepos.length !== parameters.repository_ids.length) {
      changeRepositories(selectedRepos)
    }
  }, [selectedRepos, parameters, changeRepositories])

  const targets = useMemo(
    () =>
      selectedRepos.map(repo => ({
        type: 'include' as IncludeExcludeType,
        prefix: 'repo',
        value: repo.nodeId,
        display: repo.name,
      })),
    [selectedRepos],
  )

  const orgLogin = useParams()['repo'] // Oddly, the org name comes in the 'repo' param, because of how routes are defined
  return (
    <TargetsTable
      renderTitle={() => <h3 className="Box-title">Repositories</h3>}
      renderAction={() =>
        isReposPicker ? (
          <MultiSelectReposPicker
            orgLogin={orgLogin}
            selected={selectedRepos.map(toPickerRepository)}
            onSubmit={newSelection => changeRepositories(newSelection.map(toSimpleRepository))}
          />
        ) : (
          <ReposSelector
            currentSelection={selectedRepos}
            repositoryLoader={queryForRepos}
            selectionVariant="multiple"
            selectAllOption={false}
            onSelect={newSelection => changeRepositories(newSelection as SimpleRepository[])}
          />
        )
      }
      headerRowText={headerRowText}
      blankslate={blankslate}
      targets={targets}
      onRemove={(_, v) => removeRepository(v)}
      readOnly={readOnly}
    />
  )
}

function toSimpleRepository(repo: PickerRepository): SimpleRepository {
  return {
    ...repo,
    public: repo.visibility === 'public',
    private: repo.visibility === 'private',
    isOrgOwned: true, // Rulesets can only be used in orgs
  }
}

function toPickerRepository(repo: SimpleRepository): PickerRepository {
  return {
    ...repo,
    visibility: repo.public ? 'public' : 'private',
  }
}
