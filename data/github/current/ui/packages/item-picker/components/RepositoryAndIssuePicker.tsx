import {Box, IconButton, type TokenProps} from '@primer/react'
import type React from 'react'
import {useCallback, useEffect, useState} from 'react'
import {IssuePicker, type IssuePickerItem} from './IssuePicker'

import {RepositoryFragment, RepositoryPicker, TopRepositories, prefetchCurrentRepository} from './RepositoryPicker'
import {readInlineData, useQueryLoader, useRelayEnvironment} from 'react-relay'
import type {RepositoryPickerTopRepositoriesQuery} from './__generated__/RepositoryPickerTopRepositoriesQuery.graphql'
import type {
  RepositoryPickerRepository$data as Repository,
  RepositoryPickerRepository$data,
  RepositoryPickerRepository$key,
} from './__generated__/RepositoryPickerRepository.graphql'
import {ArrowLeftIcon} from '@primer/octicons-react'
import type {RepositoryPickerCurrentRepoQuery$data} from './__generated__/RepositoryPickerCurrentRepoQuery.graphql'
import {useItemPickersContext} from '../contexts/ItemPickersContext'

export interface RepositoryAndIssuePickerProps extends Omit<TokenProps, 'leadingVisual' | 'text' | 'ref'> {
  anchorElement: (props: React.HTMLAttributes<HTMLElement>) => JSX.Element
  onIssueSelection: (issues: IssuePickerItem[]) => void
  organization: string
  defaultRepositoryNameWithOwner: string
  selectedIssueIds?: string[]
  hiddenIssueIds?: string[]
  // pickerType allows this to be treated as a controlled component
  pickerType?: PickerType
  onPickerTypeChange?: (pickerType: PickerType) => void
}

export type PickerType = 'Repository' | 'Issue' | null

const REPOSITORY_PICKER_ID = 'repository-picker'
const ISSUE_PICKER_ID = 'issue-picker'

type RepositoryAndIssuePickerInteralProps = {
  pickerType: Exclude<PickerType, null>
  setPickerType: React.Dispatch<React.SetStateAction<PickerType>>
} & Omit<RepositoryAndIssuePickerProps, 'pickerType'>

export function RepositoryAndIssuePicker({
  pickerType: propsPickerType = null,
  anchorElement,
  onPickerTypeChange,
  selectedIssueIds,
  hiddenIssueIds,
  ...rest
}: RepositoryAndIssuePickerProps) {
  const [pickerType, setPickerType] = useState<PickerType>(propsPickerType)

  useEffect(() => {
    setPickerType(propsPickerType)
  }, [propsPickerType])

  useEffect(() => {
    // don't trigger if the internal pickertype is the same as the external
    if (propsPickerType === pickerType) return

    onPickerTypeChange?.(pickerType)
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [onPickerTypeChange, pickerType])

  if (pickerType === null) {
    return anchorElement({onClick: () => setPickerType('Issue')})
  }

  return (
    <RepositoryAndIssuePickerInternal
      anchorElement={anchorElement}
      selectedIssueIds={selectedIssueIds}
      hiddenIssueIds={hiddenIssueIds}
      {...rest}
      setPickerType={setPickerType}
      pickerType={pickerType}
    />
  )
}

function RepositoryAndIssuePickerInternal({
  anchorElement,
  onIssueSelection,
  organization,
  defaultRepositoryNameWithOwner,
  pickerType,
  setPickerType,
  selectedIssueIds,
  hiddenIssueIds,
}: RepositoryAndIssuePickerInteralProps) {
  const [currentRepositoryNameWithOwner, setCurrentRepositoryNameWithOwner] =
    useState<string>(defaultRepositoryNameWithOwner)
  const [initialRepository, setInitialRepository] = useState<RepositoryPickerRepository$data | undefined>(undefined)
  const {updateOpenState} = useItemPickersContext()
  const environment = useRelayEnvironment()

  const onBackClick = useCallback(() => {
    setPickerType('Repository')
  }, [setPickerType])

  const onRepoClose = useCallback(() => {
    // If the picker type is Issue, then we know this component has moved forward to the issue picking stage, so we
    // shouldn't update the picker type to overwrite that
    setPickerType(t => (t === 'Issue' ? 'Issue' : null))
    updateOpenState(REPOSITORY_PICKER_ID, false)
  }, [setPickerType, updateOpenState])

  const onIssueClose = useCallback(() => {
    // If the picker type is Repository, then we know this has changed due to switching back to the repository
    // picker, so we shouldn't update the picker type to overwrite that
    setPickerType(t => (t === 'Repository' ? 'Repository' : null))
    updateOpenState(ISSUE_PICKER_ID, false)
  }, [setPickerType, updateOpenState])

  const setRepository = useCallback(
    (repository: Repository | undefined) => {
      if (repository?.nameWithOwner) {
        setCurrentRepositoryNameWithOwner(repository?.nameWithOwner)
      }
      // if there was no newly selected repository/NWO, that means that the already selected repository was "de-selected",
      // but with this dual-picker setup, "deselecting" still means "continue to the next picker with the selected repository"
      if (currentRepositoryNameWithOwner || repository?.nameWithOwner) {
        setPickerType('Issue')
      }
    },
    [setPickerType, currentRepositoryNameWithOwner],
  )

  const [topRepos, loadTopRepos, disposeTopRepos] =
    useQueryLoader<RepositoryPickerTopRepositoriesQuery>(TopRepositories)

  const localOnIssueSelection = (issues: IssuePickerItem[]) => {
    onIssueSelection(issues)
    setPickerType(null)
  }

  useEffect(() => {
    // preload topRepos when the component is initialized
    loadTopRepos({topRepositoriesFirst: 5, hasIssuesEnabled: true}, {fetchPolicy: 'store-or-network'})

    return () => {
      disposeTopRepos()
    }
  }, [disposeTopRepos, loadTopRepos])

  useEffect(() => {
    const [organizationLogin, repositoryName] = currentRepositoryNameWithOwner.split('/')
    prefetchCurrentRepository(environment, organizationLogin, repositoryName).subscribe({
      next: (data: RepositoryPickerCurrentRepoQuery$data) => {
        if (data.repository != null) {
          // eslint-disable-next-line no-restricted-syntax
          const current = readInlineData<RepositoryPickerRepository$key>(RepositoryFragment, data.repository)
          setInitialRepository(current)
        }
      },
    })
  }, [currentRepositoryNameWithOwner, environment])

  switch (pickerType) {
    case 'Repository':
      if (!topRepos) return null

      return (
        <RepositoryPicker
          initialRepository={initialRepository}
          preventDefault
          onSelect={setRepository}
          organization={organization}
          topReposQueryRef={topRepos}
          anchorElement={anchorElement}
          onClose={onRepoClose}
          triggerOpen
          title="Select a repository"
          pickerId={REPOSITORY_PICKER_ID}
        />
      )
    case 'Issue':
      return (
        <IssuePicker
          selectedIssueIds={selectedIssueIds}
          hiddenIssueIds={hiddenIssueIds}
          onIssueSelection={localOnIssueSelection}
          anchorElement={anchorElement}
          repositoryNameWithOwner={currentRepositoryNameWithOwner}
          onClose={onIssueClose}
          title={
            <Box sx={{display: 'flex', alignItems: 'center', gap: 1}}>
              {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
              <IconButton
                unsafeDisableTooltip
                sx={{color: 'fg.default'}}
                icon={ArrowLeftIcon}
                variant="invisible"
                aria-label="Back to repository selection"
                title="Back to repository selection"
                onClick={onBackClick}
              />
              <span>{currentRepositoryNameWithOwner}</span>
            </Box>
          }
          triggerOpen
          pickerId={ISSUE_PICKER_ID}
        />
      )
  }
}
