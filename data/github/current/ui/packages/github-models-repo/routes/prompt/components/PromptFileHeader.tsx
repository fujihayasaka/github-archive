import {useCurrentRepository, type Repository} from '@github-ui/current-repository'
import {repoModelsPath, repositoryTreePath} from '@github-ui/paths'
import {KebabHorizontalIcon, PencilIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Breadcrumbs, Button, IconButton, PageHeader} from '@primer/react'
import type {PromptConfig} from '../prompts'
import {EditBreadcrumb} from './EditBreadcrumb'
import {useRef} from 'react'
import {useLocation} from 'react-router-dom'

const separator = '/'

export function PromptFileHeader({
  prompt,
  setCommitOpen,
  canCommit,
}: {
  prompt: PromptConfig
  setCommitOpen: (open: boolean) => void
  canCommit: boolean
}) {
  const repository = useCurrentRepository()

  const path = prompt.path || ''
  const segments = path.split(separator)
  const filename = segments.pop()

  const nameInputRef = useRef<HTMLInputElement>(null)

  const location = useLocation()
  const isNewPrompt = location.pathname.includes('models/prompt/new') ? true : false

  return (
    <PageHeader className="mb-2">
      <PageHeader.TitleArea className="flex-items-center">
        {!isNewPrompt ? <span className="color-fg-muted f5 text-normal">{separator}</span> : null}
        <PageHeader.Title as="h1" className="f5">
          {isNewPrompt ? '.prompt.md' : filename}
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
          <EditBreadcrumb repository={repository} folderPath="/" fileName="" nameInputRef={nameInputRef} />
        ) : (
          <ExistingPromptBreadCrumbs repository={repository} segments={segments} />
        )}
      </PageHeader.Breadcrumbs>

      <PageHeader.Actions>
        <ActionMenu>
          <ActionMenu.Anchor>
            <IconButton icon={KebabHorizontalIcon} aria-label="More actions" />
          </ActionMenu.Anchor>
          <ActionMenu.Overlay>
            <ActionList>
              <ActionList.LinkItem onClick={() => {}} href={''}>
                <ActionList.LeadingVisual>
                  <PencilIcon />
                </ActionList.LeadingVisual>
                Rename
              </ActionList.LinkItem>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>

        <Button variant="default" onClick={() => setCommitOpen(true)} disabled={!canCommit}>
          Commit changes
        </Button>
      </PageHeader.Actions>
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
            path: segments.slice(0, index + 1).join(separator),
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
