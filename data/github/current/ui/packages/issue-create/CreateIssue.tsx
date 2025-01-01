import type {RepositoryPickerRepository$data as Repository} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import type {RepositoryPickerTopRepositoriesQuery} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'

import {Box} from '@primer/react'
import {type RefObject, useCallback, useEffect} from 'react'
import {fetchQuery, graphql, type PreloadedQuery, useFragment, useRelayEnvironment} from 'react-relay'

import {CreateIssueForm, type CreateIssueCallbackProps} from './CreateIssueForm'
import {TemplatePickerButton} from './TemplatePickerButton'
import {RepositoryAndTemplatePickerDialog} from './RepositoryAndTemplatePickerDialog'

import {IssueCreationKind, getBlankIssue} from './utils/model'
import {TemplateListInternal} from './TemplateListPane'
import {DisplayMode} from './utils/display-mode'
import type {IssueCreateValueTypes} from './utils/template-args'
import {useIssueCreateConfigContext} from './contexts/IssueCreateConfigContext'
import {useIssueCreateDataContext} from './contexts/IssueCreateDataContext'
import type {IssueFormRef} from '@github-ui/issue-form/Types'
import type {CreateIssue$key} from './__generated__/CreateIssue.graphql'
import {getSelectedTemplate, useHandleTemplateChange} from './use-handle-template-change'
import type {CreateIssueQuery} from './__generated__/CreateIssueQuery.graphql'
import {ERRORS} from './constants/errors'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import type {TemplateListSharedProps} from './TemplateList'
import {useOnCreateSuccess} from './hooks/use-on-create-success'

const templateQuery = graphql`
  query CreateIssueQuery($repoId: ID!, $filename: String!) {
    node(id: $repoId) {
      ... on Repository {
        ...useHandleTemplateChange @dangerously_unaliased_fixme @arguments(filename: $filename)
      }
    }
  }
`

export type CreateIssueProps = {
  currentRepository: CreateIssue$key | undefined | null
  topReposQueryRef?: PreloadedQuery<RepositoryPickerTopRepositoriesQuery>
  navigate: (url: string) => void
  issueFormRef: RefObject<IssueFormRef>
  onSafeClose?: () => void
} & CreateIssueCallbackProps &
  TemplateListSharedProps

export const CreateIssue = ({
  topReposQueryRef,
  navigate,
  currentRepository,
  onCreateSuccess,
  issueFormRef,
  ...props
}: CreateIssueProps) => {
  const data = useFragment(
    graphql`
      fragment CreateIssue on Repository
      @argumentDefinitions(includeTemplates: {type: "Boolean", defaultValue: false}) {
        ...TemplatePickerButton @dangerously_unaliased_fixme @include(if: $includeTemplates)
        ...TemplateListPane @dangerously_unaliased_fixme @include(if: $includeTemplates)
      }
    `,
    currentRepository,
  )
  const {addToast} = useToastContext()

  const environment = useRelayEnvironment()
  const {title, body, setBody, repository, setRepository, template, setNewTitle, clearMetadata, clearSessionData} =
    useIssueCreateDataContext()
  const {optionConfig, displayMode, initialDefaultDisplayMode, setDisplayMode, setCreateMoreCreatedPath} =
    useIssueCreateConfigContext()

  const onRepositorySelected = useCallback(
    (selectedRepository: Repository | undefined) => {
      if (selectedRepository) {
        if (repository?.id !== selectedRepository.id) {
          // We are only clearing metadata because we want to persist title & body across repo changes incase we are selecting blank issues
          clearMetadata()
        }

        setRepository(selectedRepository)
        setCreateMoreCreatedPath({
          owner: selectedRepository.owner.login,
          repo: selectedRepository.name,
          number: undefined,
        })
      }
    },
    [clearMetadata, repository?.id, setCreateMoreCreatedPath, setRepository],
  )

  const handleTemplateChange = useHandleTemplateChange({
    optionConfig,
    repository,
    navigate,
    setDisplayMode,
  })

  const onTemplateSelected = useCallback(
    (filename: string, kind: IssueCreationKind) => {
      if (!repository) {
        return
      }

      if (repository?.viewerInteractionLimitReasonHTML && repository.viewerInteractionLimitReasonHTML.length > 0) {
        const redirectUrl = `/${repository.owner.login}/${repository.name}/issues/new`
        navigate(redirectUrl)
        return
      }

      // Contact links will redirect to a new page, so we don't want to set the template
      if (kind === IssueCreationKind.ContactLink) {
        return
      }
      let extraArgs: IssueCreateValueTypes | undefined = undefined
      if (optionConfig.issueCreateArguments?.initialValues?.appendTitleToTemplate) {
        extraArgs = {
          appendTitleToTemplate: optionConfig.issueCreateArguments.initialValues.appendTitleToTemplate,
        }
      }
      if (kind === IssueCreationKind.BlankIssue) {
        const selectedTemplate = getBlankIssue()
        handleTemplateChange(selectedTemplate, extraArgs, true)
        return
      }

      fetchQuery<CreateIssueQuery>(environment, templateQuery, {repoId: repository.id, filename}).subscribe({
        next: response => {
          if (!response.node) {
            return
          }

          const fetchedTemplate = getSelectedTemplate(response.node)

          if (fetchedTemplate) {
            handleTemplateChange(fetchedTemplate, extraArgs, true)
          }
        },
        error: () => {
          reportError(new Error(ERRORS.unableToLoadSelectedTemplate))

          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: ERRORS.unableToLoadSelectedTemplate,
          })
        },
      })
    },
    [
      repository,
      environment,
      optionConfig.issueCreateArguments?.initialValues?.appendTitleToTemplate,
      handleTemplateChange,
      addToast,
      navigate,
    ],
  )

  const onCreateSuccessInternal = useOnCreateSuccess({
    issueFormRef,
    handleTemplateChange,
    template,
    callback: onCreateSuccess,
  })

  useEffect(() => {
    if (repository)
      setCreateMoreCreatedPath({
        owner: repository.owner?.login || '',
        repo: repository.name || '',
        number: undefined,
      })
  }, [repository, setCreateMoreCreatedPath])

  if (!data && !repository) {
    return (
      <CreateIssueWithoutRepo
        repository={repository}
        onRepositorySelected={onRepositorySelected}
        topReposQueryRef={topReposQueryRef}
        organization={optionConfig.scopedOrganization}
        onTemplateSelected={onTemplateSelected}
      />
    )
  }

  // If we are immediately bypassing the template selection, then we should allow the user to go back to choose another template or repository.
  // We don't allow users to choose another template or repository for issue duplication at the moment
  const shouldShowTemplateButton = initialDefaultDisplayMode === DisplayMode.IssueCreation
  return (
    <Box sx={{display: 'flex', flexDirection: 'column', alignItems: 'stretch', gap: 2}} tabIndex={-1}>
      {(displayMode === DisplayMode.IssueCreation || displayMode === DisplayMode.IssueDuplication) && (
        <>
          {shouldShowTemplateButton && data && <TemplatePickerButton repository={data} template={template} />}
          {repository && (
            <CreateIssueForm
              {...props}
              issueFormRef={issueFormRef}
              onCreateSuccess={onCreateSuccessInternal}
              selectedTemplate={template}
              repository={repository}
              title={title}
              setTitle={setNewTitle}
              body={body}
              setBody={setBody}
              clearOnCreate={clearSessionData}
              focusTitleInput={!shouldShowTemplateButton}
              footer={undefined}
            />
          )}
        </>
      )}
      {optionConfig.showRepositoryPicker && displayMode === DisplayMode.TemplatePicker && topReposQueryRef && (
        <RepositoryAndTemplatePickerDialog
          repository={repository}
          setRepository={onRepositorySelected}
          topReposQueryRef={topReposQueryRef}
          organization={optionConfig.scopedOrganization}
          onTemplateSelected={onTemplateSelected}
        />
      )}
      {!optionConfig.showRepositoryPicker && displayMode === DisplayMode.TemplatePicker && data && (
        <div data-hpc>
          <TemplateListInternal repository={data} onTemplateSelected={onTemplateSelected} {...props} />
        </div>
      )}
    </Box>
  )
}
type CreateIssueWithoutRepoProps = {
  repository: Repository | undefined
  onRepositorySelected: (selectedRepository: Repository | undefined) => void
  topReposQueryRef?: PreloadedQuery<RepositoryPickerTopRepositoriesQuery>
  organization?: string
  onTemplateSelected: (filename: string, kind: IssueCreationKind) => void
}
function CreateIssueWithoutRepo({
  repository,
  onRepositorySelected,
  topReposQueryRef,
  organization,
  onTemplateSelected,
}: CreateIssueWithoutRepoProps) {
  if (!topReposQueryRef) {
    // TODO log error
    // cant create issue without repo
    return null
  }
  return (
    <Box sx={{display: 'flex', flexDirection: 'column', alignItems: 'stretch', gap: 2}} tabIndex={-1}>
      <RepositoryAndTemplatePickerDialog
        repository={repository}
        setRepository={onRepositorySelected}
        topReposQueryRef={topReposQueryRef}
        organization={organization}
        onTemplateSelected={onTemplateSelected}
      />
    </Box>
  )
}
