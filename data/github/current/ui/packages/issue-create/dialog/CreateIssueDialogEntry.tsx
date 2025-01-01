import type {RepositoryPickerRepository$key} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import type {RepositoryPickerTopRepositoriesQuery} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'
import {RepositoryFragment, TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import {Suspense, useEffect, useMemo, useRef, type RefObject} from 'react'
import {graphql, readInlineData, usePreloadedQuery, useQueryLoader, type PreloadedQuery} from 'react-relay'
import {noop} from '@github-ui/noop'

import {VALUES} from '../constants/values'

import type {IssueCreateOptionConfig, SafeOptionConfig} from '../utils/option-config'
import {getSafeConfig} from '../utils/option-config'
import {issuePath} from '@github-ui/paths'
import type {CreateIssueCallbackProps} from '../CreateIssueForm'
import {CreateIssueDialog} from './CreateIssueDialog'
import {IssueCreateContextProvider} from '../contexts/IssueCreateContext'
import type {OnCreateProps} from '../utils/model'
import {DisplayMode} from '../utils/display-mode'
import {constructIssueCreateParams} from '../utils/template-args'
import type {CreateIssueProps} from '../CreateIssue'
import type {IssueFormRef} from '@github-ui/issue-form/Types'
import type {
  CreateIssueDialogEntryQuery,
  CreateIssueDialogEntryQuery$data,
} from './__generated__/CreateIssueDialogEntryQuery.graphql'
import type {TemplateListSharedProps} from '../TemplateList'

export const CreateIssueDialogEntryGraphQLQuery = graphql`
  query CreateIssueDialogEntryQuery($owner: String!, $name: String!, $includeTemplates: Boolean = false) {
    repository(owner: $owner, name: $name) {
      hasAnyTemplates
      isSecurityPolicyEnabled
      ...RepositoryPickerRepository
      ...CreateIssueDialog @arguments(includeTemplates: $includeTemplates)
    }
  }
`

export const CreateIssueDialogEntry = ({...props}: CreateIssueDialogEntryProps): JSX.Element | null => {
  return (
    <Suspense>
      <CreateIssueDialogEntryInternal {...props} />
    </Suspense>
  )
}

export type CreateIssueDialogEntryProps = {
  navigate: (url: string) => void
  isCreateDialogOpen: boolean
  setIsCreateDialogOpen: (value: boolean) => void
  optionConfig?: IssueCreateOptionConfig
  returnFocusRef?: RefObject<HTMLElement>
} & Partial<CreateIssueCallbackProps> &
  TemplateListSharedProps

export const CreateIssueDialogEntryInternal = ({
  navigate,
  isCreateDialogOpen,
  setIsCreateDialogOpen,
  onCancel,
  onCreateSuccess,
  onCreateError,
  optionConfig,
  isNavigatingToNew,
  setIsNavigatingToNew,
  returnFocusRef,
}: CreateIssueDialogEntryProps): JSX.Element | null => {
  const [topReposQueryRef, loadTopRepos, disposeTopRepos] =
    useQueryLoader<RepositoryPickerTopRepositoriesQuery>(TopRepositories)
  const [currentRepoQueryRef, loadCurrentRepo, disposeCurrentRepo] = useQueryLoader<CreateIssueDialogEntryQuery>(
    CreateIssueDialogEntryGraphQLQuery,
  )

  const config = getSafeConfig(optionConfig)
  const shouldLoadTopRepos = config.showRepositoryPicker

  useEffect(() => {
    if (shouldLoadTopRepos) {
      loadTopRepos(
        {topRepositoriesFirst: VALUES.repositoriesPreloadCount, hasIssuesEnabled: true, owner: null},
        {fetchPolicy: 'store-or-network'},
      )
      return () => {
        disposeTopRepos()
      }
    }
  }, [disposeTopRepos, loadTopRepos, shouldLoadTopRepos])

  /**
   * Repository to prefill the create issue dialog with
   *
   * Note: The repo will only be determined based on the existence of an `owner` and `name` string,
   * without consideration for archived repos or other reasons the repository might not be available.
   */
  const prefillRepository = useMemo(() => {
    if (config.issueCreateArguments?.repository) {
      return {
        owner: config.issueCreateArguments.repository.owner,
        name: config.issueCreateArguments.repository.name,
      }
    }

    return null
  }, [config.issueCreateArguments?.repository])

  useEffect(() => {
    if (prefillRepository)
      loadCurrentRepo({...prefillRepository, includeTemplates: true}, {fetchPolicy: 'store-or-network'})

    return () => disposeCurrentRepo()
  }, [disposeCurrentRepo, prefillRepository, loadCurrentRepo])

  const handleDialogClose = () => {
    onCancel?.()
    setIsCreateDialogOpen(false)
  }

  const handleOnCreate = ({issue, createMore}: OnCreateProps) => {
    // Respect the callback if it exists, else use default behaviour.
    if (onCreateSuccess) {
      onCreateSuccess({issue, createMore})
    } else if (!createMore) {
      handleDialogClose()
      navigate(
        issuePath({
          owner: issue.repository.owner.login,
          repo: issue.repository.name,
          issueNumber: issue.number,
        }),
      )
    }
  }

  const handleOnError = (error: Error) => onCreateError?.(error)

  const createIssueDialogProps: CreateIssuePropsEntry = {
    topReposQueryRef: topReposQueryRef ?? undefined,
    onCreateSuccess: handleOnCreate,
    onCreateError: handleOnError,
    onCancel: handleDialogClose,
    navigate,
    isNavigatingToNew,
    setIsNavigatingToNew,
  }

  if (!isCreateDialogOpen) {
    return null
  }

  // If we are waiting for the top repos to load, or we are waiting for the current repo to load then don't render
  if ((shouldLoadTopRepos && !topReposQueryRef) || (!currentRepoQueryRef && prefillRepository)) {
    return null
  }

  return (
    <CreateIssueEntry
      createIssueProps={createIssueDialogProps}
      config={config}
      currentRepoQueryRef={currentRepoQueryRef ?? null}
      returnFocusRef={returnFocusRef}
    />
  )
}

export type CreateIssuePropsEntry = Omit<CreateIssueProps, 'issueFormRef' | 'currentRepository'>

type CreateIssueEntryBaseProps = {
  createIssueProps: CreateIssuePropsEntry
  config: SafeOptionConfig
  returnFocusRef?: RefObject<HTMLElement>
}

export type CreateIssueEntryProps = CreateIssueEntryBaseProps & {
  currentRepoQueryRef: PreloadedQuery<CreateIssueDialogEntryQuery> | null
}

export type CreateIssueEntryPropsWithRepo = CreateIssueEntryBaseProps & {
  currentRepoQueryRef: PreloadedQuery<CreateIssueDialogEntryQuery>
}

type CreateIssueEntryInternal = CreateIssueEntryBaseProps & {
  currentRepoData: CreateIssueDialogEntryQuery$data | null
}

const CreateIssueEntry = ({currentRepoQueryRef, ...props}: CreateIssueEntryProps) => {
  if (currentRepoQueryRef) {
    return <CreateIssueEntryWithRepo currentRepoQueryRef={currentRepoQueryRef} {...props} />
  } else {
    return <CreateIssueEntryInternal currentRepoData={null} {...props} />
  }
}

export const CreateIssueEntryWithRepo = ({currentRepoQueryRef, ...props}: CreateIssueEntryPropsWithRepo) => {
  const data = usePreloadedQuery<CreateIssueDialogEntryQuery>(CreateIssueDialogEntryGraphQLQuery, currentRepoQueryRef)
  return <CreateIssueEntryInternal currentRepoData={data} {...props} />
}

// Since we have the current repository already loaded, we can now check if theres no templates available
// and if so, directly bypass the template selector.

const CreateIssueEntryInternal = ({
  createIssueProps,
  config,
  currentRepoData,
  returnFocusRef,
}: CreateIssueEntryInternal) => {
  const navigate = createIssueProps.navigate ?? noop
  const repository =
    currentRepoData && currentRepoData.repository !== undefined
      ? // eslint-disable-next-line no-restricted-syntax
        readInlineData<RepositoryPickerRepository$key>(RepositoryFragment, currentRepoData.repository)
      : null
  const issueFormRef = useRef<IssueFormRef>(null)

  const preselectedData = {
    repository: repository ?? undefined,
    template: undefined,
    parentIssue: config.issueCreateArguments?.parentIssue,
  }

  const props = {
    ...createIssueProps,
    issueFormRef,
  }

  const redirect =
    navigate !== noop &&
    repository &&
    !currentRepoData?.repository?.isSecurityPolicyEnabled &&
    !currentRepoData?.repository?.hasAnyTemplates

  useEffect(() => {
    if (redirect) {
      const searchParams = constructIssueCreateParams({
        includeRepository: false,
        repository,
        templateFileName: undefined,
        title: config.issueCreateArguments?.initialValues?.title,
        body: config.issueCreateArguments?.initialValues?.body,
        assignees: config.issueCreateArguments?.initialValues?.assignees,
        labels: config.issueCreateArguments?.initialValues?.labels,
        projects: config.issueCreateArguments?.initialValues?.projects,
        milestone: config.issueCreateArguments?.initialValues?.milestone,
        type: config.issueCreateArguments?.initialValues?.type,
      })
      const url = `/${repository.nameWithOwner}/issues/new${searchParams ? `?${searchParams}` : ''}`
      navigate(url)
    }
  }, [
    config.issueCreateArguments?.initialValues?.assignees,
    config.issueCreateArguments?.initialValues?.body,
    config.issueCreateArguments?.initialValues?.labels,
    config.issueCreateArguments?.initialValues?.milestone,
    config.issueCreateArguments?.initialValues?.projects,
    config.issueCreateArguments?.initialValues?.title,
    config.issueCreateArguments?.initialValues?.type,
    navigate,
    redirect,
    repository,
  ])

  if (redirect) {
    return null
  }

  return (
    <IssueCreateContextProvider
      optionConfig={config}
      overrideFallbackDisplaymode={DisplayMode.TemplatePicker}
      preselectedData={preselectedData}
    >
      <CreateIssueDialog currentRepository={currentRepoData?.repository} {...props} returnFocusRef={returnFocusRef} />
    </IssueCreateContextProvider>
  )
}
