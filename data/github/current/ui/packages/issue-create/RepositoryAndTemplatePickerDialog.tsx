import {RepositoryPicker} from '@github-ui/item-picker/RepositoryPicker'
import type {RepositoryPickerRepository$data as Repository} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import type {RepositoryPickerTopRepositoriesQuery} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'

import {Suspense, useId} from 'react'
import type {PreloadedQuery} from 'react-relay'
import {TemplateListPaneFromRepo} from './TemplateListPane'
import {TemplateListLoading} from './TemplateListLoading'
import {useIssueCreateConfigContext} from './contexts/IssueCreateConfigContext'
import type {IssueCreationKind} from './utils/model'
import {TEST_IDS} from './constants/test-ids'

export type RepositoryAndTemplatePickerDialogProps = {
  repository: Repository | undefined
  setRepository: (repository: Repository | undefined) => void
  topReposQueryRef: PreloadedQuery<RepositoryPickerTopRepositoriesQuery>
  organization?: string
  onTemplateSelected: (filename: string, kind: IssueCreationKind) => void
}

export function RepositoryAndTemplatePickerDialog({
  repository,
  setRepository,
  topReposQueryRef,
  organization,
  onTemplateSelected,
}: RepositoryAndTemplatePickerDialogProps) {
  const {optionConfig} = useIssueCreateConfigContext()
  const descriptionId = useId()
  const repoLeftMargin = optionConfig.insidePortal ? `ml-3` : `ml-0`

  return (
    <div className={optionConfig.insidePortal ? 'pt-2' : ''} data-testid={TEST_IDS.repositoryAndTemplateDialog}>
      <Field className={repoLeftMargin} name="Repository" />
      <div className={`${optionConfig.insidePortal ? `mb-2` : `mb-3`} ${repoLeftMargin}`}>
        <RepositoryPicker
          aria-describedby={descriptionId}
          initialRepository={repository}
          onSelect={setRepository}
          organization={organization}
          topReposQueryRef={topReposQueryRef}
          focusRepositoryPicker
          enforceAtleastOneSelected
          options={{hasIssuesEnabled: true}}
        />
      </div>
      <Suspense fallback={<TemplateListLoading />}>
        {repository && (
          <TemplateListPaneFromRepo
            repositoryId={repository.id}
            onTemplateSelected={onTemplateSelected}
            descriptionId={descriptionId}
          />
        )}
      </Suspense>
    </div>
  )
}

function Field({name, className}: {name: string; className?: string}) {
  return (
    <div className={`pt-1 pb-1 ${className}`}>
      <span className={'text-bold'}>{name}</span>
      <span className={'ml-1 mb-1 fgColor-danger'}>*</span>
    </div>
  )
}
