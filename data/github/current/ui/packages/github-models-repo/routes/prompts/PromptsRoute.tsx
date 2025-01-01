import {CommentDiscussionIcon, PlusIcon, SortDescIcon} from '@primer/octicons-react'
import {Button, Link, PageHeader} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import {ModelsRepoLayout} from '../../components/ModelsRepoLayout'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {ModelRepoPayload} from '../../types'

export type ModelPromptsRepoPayload = ModelRepoPayload & {
  canEdit: boolean
}

export function PromptsRoute() {
  const {canEdit} = useAppPayload<ModelPromptsRepoPayload>()

  return (
    <ModelsRepoLayout>
      <PageHeader aria-label="Prompts">
        <PageHeader.TitleArea>
          <PageHeader.Title>Prompts</PageHeader.Title>
        </PageHeader.TitleArea>
        {canEdit && (
          <PageHeader.Actions>
            <Link inline href="prompt/new">
              <Button variant="primary" leadingVisual={PlusIcon}>
                New prompt
              </Button>
            </Link>
          </PageHeader.Actions>
        )}
      </PageHeader>

      <div className="Box rounded-2 mt-4">
        <div className="Box-header p-2">
          <div className="d-inline-flex flex-justify-between flex-items-center width-full">
            0 prompts
            <div className="flex-justify-between">
              <Button variant="invisible" leadingVisual={SortDescIcon}>
                Sort
              </Button>
            </div>
          </div>
        </div>
        <Blankslate>
          <Blankslate.Visual>
            <CommentDiscussionIcon size="medium" />
          </Blankslate.Visual>
          <Blankslate.Heading>Prompts</Blankslate.Heading>
          <Blankslate.Description>
            Add a prompt anywhere in your repository. Supported are <code>.prompt.md</code> files.
          </Blankslate.Description>
          <Blankslate.SecondaryAction href="#">Learn more about prompts</Blankslate.SecondaryAction>
        </Blankslate>
      </div>
    </ModelsRepoLayout>
  )
}
