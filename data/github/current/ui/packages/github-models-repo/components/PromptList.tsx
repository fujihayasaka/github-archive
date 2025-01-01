import type {Repository} from '@github-ui/current-repository'
import {blobPath, repoModelsPromptPath} from '@github-ui/paths'
import {AiModelIcon, KebabHorizontalIcon, LinkExternalIcon, NoteIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, Heading, IconButton, Link, Stack, Truncate} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {type PropsWithChildren, useCallback, useState} from 'react'
import type {ParsedPrompt, PromptAction} from '../types'
import {PromptLabel} from './PromptLabel'
import {PromptListPagination} from './PromptListPagination'
import styles from './PromptList.module.css'

export function PromptList({
  canEdit,
  headerText,
  promptAction = 'edit',
  totalPrompts,
  prompts: initialPrompts,
  page: initialPage = 1,
  totalPages = 1,
  repository,
  showViewAll,
}: {
  canEdit: boolean
  headerText?: string
  promptAction?: PromptAction
  totalPrompts: number
  prompts: ParsedPrompt[]
  page?: number
  totalPages?: number
  repository: Repository
  showViewAll?: boolean
}) {
  const [prompts, setPrompts] = useState(initialPrompts)
  const [page, setPage] = useState(initialPage)
  const linkPrefix = `/${repository.ownerLogin}/${repository.name}/`
  const defaultHeaderText = `${totalPrompts} prompt${totalPrompts !== 1 ? 's' : ''} found`
  const handleLoadPromptsPage = useCallback(
    (promptsInPage: ParsedPrompt[], newCurrentPage: number) => {
      setPrompts(promptsInPage)
      setPage(newCurrentPage)
    },
    [setPage, setPrompts],
  )

  return (
    <div className="Box rounded-2">
      <div className="Box-header p-2">
        <div className="d-inline-flex flex-justify-between flex-items-center width-full px-2 py-1">
          <Heading as="h3" className="text-semibold" variant="small">
            {headerText || defaultHeaderText}
          </Heading>
          {showViewAll && (
            <Link href={`${linkPrefix}models/prompts`} className="f6">
              View all
            </Link>
          )}
        </div>
      </div>

      {!canEdit ? (
        <PromptListReadOnly />
      ) : (
        <>
          {prompts.length === 0 && (
            <Blankslate>
              <Blankslate.Visual>
                <NoteIcon size="medium" />
              </Blankslate.Visual>
              <Blankslate.Heading>Create a prompt</Blankslate.Heading>
              <Blankslate.Description>
                Build with natural language or using{' '}
                <Link
                  inline
                  href="https://docs.github.com/github-models/use-github-models/storing-prompts-in-github-repositories"
                >
                  prompt.yml files
                </Link>
              </Blankslate.Description>
              <BlanklateActionAsDefaultButton href={`${linkPrefix}models/prompt/new?sample`}>
                Test sample prompt
              </BlanklateActionAsDefaultButton>
            </Blankslate>
          )}
          <Stack direction="vertical" gap="none">
            {prompts.length > 0 &&
              prompts.map((prompt, index) => (
                <Stack.Item
                  key={prompt.path}
                  grow
                  className={`Box-row--hover-gray d-flex py-2 px-3 ${index > 0 ? 'border-top' : ''}`}
                >
                  <div className="d-inline-flex flex-items-center width-full">
                    <div className="pt-1 flex-self-start">
                      <NoteIcon size={16} />
                    </div>

                    <div className="flex-1 pl-2 d-flex flex-column overflow-hidden">
                      <Link
                        className="f4 fgColor-default"
                        href={repoModelsPromptPath({
                          repo: repository,
                          path: prompt.path,
                          action: promptAction,
                          commitish: repository.defaultBranch,
                        })}
                      >
                        {prompt.name}
                      </Link>
                      <Truncate title={prompt.description} className="color-fg-muted" maxWidth="100%">
                        {prompt.description}
                      </Truncate>
                    </div>

                    <div className="d-inline-flex flex-items-center flex-self-start">
                      {prompt.model && <PromptLabel modelId={prompt.model} />}
                      <ActionMenu>
                        <ActionMenu.Anchor>
                          <IconButton icon={KebabHorizontalIcon} variant="invisible" aria-label="Open menu" />
                        </ActionMenu.Anchor>
                        <ActionMenu.Overlay>
                          <ActionList>
                            <ActionList.LinkItem
                              href={blobPath({
                                owner: repository.ownerLogin,
                                repo: repository.name,
                                filePath: prompt.path,
                                commitish: repository.defaultBranch,
                              })}
                            >
                              <ActionList.LeadingVisual>
                                <LinkExternalIcon />
                              </ActionList.LeadingVisual>
                              View file
                            </ActionList.LinkItem>
                          </ActionList>
                        </ActionMenu.Overlay>
                      </ActionMenu>
                    </div>
                  </div>
                </Stack.Item>
              ))}
            <PromptListPagination
              page={page}
              totalPages={totalPages}
              onPromptsLoaded={handleLoadPromptsPage}
              repository={repository}
            />
          </Stack>
        </>
      )}
    </div>
  )
}

function PromptListReadOnly() {
  return (
    <Blankslate>
      <Blankslate.Visual>
        <AiModelIcon size="medium" />
      </Blankslate.Visual>
      <Blankslate.Description>
        Get write permissions or higher for this repository to create and manage prompts.
      </Blankslate.Description>
    </Blankslate>
  )
}

// Blankslate.PrimaryAction does not support setting a variant of "default" so we inline an implementation.
// Copies: https://github.com/primer/react/blob/a470e14bf143f5be50047f6c43c7853980d6e952/packages/react/src/Blankslate/Blankslate.tsx#L70-L78
function BlanklateActionAsDefaultButton({href, children}: PropsWithChildren<{href: string}>) {
  return (
    <div className={clsx('Blankslate-Action', styles.BlankslateAction)}>
      <Button as="a" href={href} variant="default">
        {children}
      </Button>
    </div>
  )
}
