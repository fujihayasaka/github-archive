import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {PlusIcon, SidebarCollapseIcon} from '@primer/octicons-react'
import {Button, PageHeader, Link, IconButton} from '@primer/react'
import {ModelsRepoLayout} from '../../components/ModelsRepoLayout'
import type {ModelRepoPromptsAppPayload, ModelRepoPromptsRoutePayload} from '../../types'
import {PromptList} from '../../components/PromptList'
import {useState} from 'react'

export function PromptsRoute({comparisons = false}: {comparisons?: boolean}) {
  const {repository, canEdit, totalPrompts} = useAppPayload<ModelRepoPromptsAppPayload>()
  const {prompts, page, totalPages} = useRoutePayload<ModelRepoPromptsRoutePayload>()
  const [fileTreeExpanded, setFileTreeExpanded] = useState(true)

  return (
    <ModelsRepoLayout fileTreeExpanded={fileTreeExpanded} setFileTreeExpanded={setFileTreeExpanded}>
      <div className={fileTreeExpanded ? 'pt-3 pr-5' : 'pt-3 px-5'}>
        <PageHeader aria-label="Prompts" className="mb-4">
          <PageHeader.TitleArea>
            <div className="d-flex">
              {!fileTreeExpanded && (
                <IconButton
                  onClick={() => setFileTreeExpanded(true)}
                  aria-label="Expand menu"
                  icon={SidebarCollapseIcon}
                  variant="invisible"
                  // eslint-disable-next-line @github-ui/github-monorepo/no-sx
                  sx={{marginRight: '8px'}}
                />
              )}
              <PageHeader.Title>{comparisons ? 'Comparisons' : 'Prompts'}</PageHeader.Title>
            </div>
          </PageHeader.TitleArea>
          {canEdit && (
            <PageHeader.Actions>
              <Button as="a" href="prompt/new" variant="primary" leadingVisual={PlusIcon}>
                New prompt
              </Button>
            </PageHeader.Actions>
          )}
          <PageHeader.Description className="pt-0">
            <p className="color-fg-muted">
              {comparisons ? 'Compare and evaluate' : 'Manage'} prompts stored in your repo using{' '}
              <Link
                href="https://docs.github.com/github-models/use-github-models/storing-prompts-in-github-repositories"
                inline
              >
                .prompt.yml file
              </Link>{' '}
              format.
            </p>
          </PageHeader.Description>
        </PageHeader>
        <PromptList
          canEdit={canEdit}
          totalPrompts={totalPrompts}
          prompts={prompts}
          page={page}
          totalPages={totalPages}
          repository={repository}
          promptAction={comparisons ? 'compare' : 'edit'}
        />
      </div>
    </ModelsRepoLayout>
  )
}
