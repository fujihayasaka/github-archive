import {useCurrentRepository, type Repository} from '@github-ui/current-repository'
import {repoModelsPath, repositoryTreePath} from '@github-ui/paths'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {WebCommitDialogState} from '@github-ui/web-commit-dialog'
import {Breadcrumbs, PageHeader} from '@primer/react'
import {useRef} from 'react'
import {useLocation} from 'react-router-dom'
import type {PromptConfig} from '../prompts'
import type {PromptAppPayload} from '../types'
import {EditBreadcrumb} from './EditBreadcrumb'
import {isPromptComparePage, promptPathSeparator, promptPathSegments} from '../prompts'
import {CommitButton} from './CommitButton'

export function PromptFileHeader({
  isDirty,
  prompt,
  setDialogState,
}: {
  isDirty: boolean | undefined
  prompt: PromptConfig
  setDialogState?: (state: WebCommitDialogState) => void
}) {
  const repository = useCurrentRepository()
  const {
    payload: {canEdit, promptPath},
  } = useAppPayload<PromptAppPayload>()

  const segments = promptPathSegments(prompt)
  const filename = segments.pop()

  const nameInputRef = useRef<HTMLInputElement>(null)

  const location = useLocation()
  const isNewPrompt = promptPath.length < 1 || location.pathname.includes('models/prompt/new')
  const isCompareView = isPromptComparePage(location.pathname)

  return (
    <PageHeader>
      <PageHeader.TitleArea className="flex-items-center">
        {!isNewPrompt ? <span className="color-fg-muted f5 text-normal">{promptPathSeparator}</span> : null}
        <PageHeader.Title as="h1" className="f5">
          {isNewPrompt ? '.prompt.yml' : filename}
        </PageHeader.Title>
      </PageHeader.TitleArea>

      <PageHeader.ContextArea>
        <PageHeader.ParentLink
          href={repoModelsPath({
            repo: repository,
            action: 'prompts',
          })}
        >
          Prompts
        </PageHeader.ParentLink>
      </PageHeader.ContextArea>
      <PageHeader.Breadcrumbs>
        {isNewPrompt ? (
          <EditBreadcrumb repository={repository} folderPath="" fileName="" nameInputRef={nameInputRef} />
        ) : (
          <ExistingPromptBreadCrumbs repository={repository} segments={segments} />
        )}
      </PageHeader.Breadcrumbs>

      {!isCompareView && canEdit && (
        <PageHeader.Actions>
          <CommitButton size="medium" canEdit isDirty={isDirty} promptConfig={prompt} setDialogState={setDialogState} />
        </PageHeader.Actions>
      )}
    </PageHeader>
  )
}

function ExistingPromptBreadCrumbs({repository, segments}: {repository: Repository; segments: string[]}) {
  return (
    <Breadcrumbs>
      <Breadcrumbs.Item
        className="text-bold"
        href={repoModelsPath({
          repo: repository,
          action: 'prompts',
        })}
      >
        Prompts
      </Breadcrumbs.Item>
      {segments.map((segment, index) => (
        <Breadcrumbs.Item
          href={repositoryTreePath({
            repo: repository,
            commitish: repository.defaultBranch, // TODO: CS: Pass ref from route
            path: segments.slice(0, index + 1).join(promptPathSeparator),
            action: 'tree',
          })}
          // using index in addition to segment to ensure unique keys
          // eslint-disable-next-line @eslint-react/no-array-index-key
          key={`${segment}-${index}`}
        >
          {segment}
        </Breadcrumbs.Item>
      ))}
    </Breadcrumbs>
  )
}
