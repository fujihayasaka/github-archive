import {CanIndexStatus, TopicIndexStatus, useReposIndexingState} from '@github-ui/copilot-chat/utils/copilot-chat-hooks'
import type {Docset} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {BookIcon, CheckIcon, PencilIcon, SkipFillIcon, TrashIcon, XIcon} from '@primer/octicons-react'
import {Button, Flash, Heading, IconButton, PageHeader, Spinner, Truncate} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {AriaAlert, Banner, Blankslate, Dialog} from '@primer/react/experimental'
import {useContext, useEffect, useState, type Dispatch, type SetStateAction} from 'react'
import {KnowledgeBaseFormProviders} from '../components/docs/KnowledgeBaseFormProviders'
import {CopilotChatSettingsServiceContext} from '../utils/copilot-chat-settings-service'
import {updateUrl} from '@github-ui/history'

import styles from './ChatSettings.module.css'

export interface ChatSettingsPayload {
  newKnowledgeBasePath: string
  currentOrganizationLogin: string
}

const truncationWidths = ['220px', '300px', null, '550px', '800px']

export function ChatSettings() {
  const payload = useRoutePayload<ChatSettingsPayload>()

  const [knowledgeBases, setKnowledgeBases] = useState<Docset[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [hadError, setHadError] = useState(false)
  const service = useContext(CopilotChatSettingsServiceContext)

  useEffect(() => {
    let ignore = false

    const fetch = async () => {
      try {
        const kbs = await service.fetchKnowledgeBases(payload.currentOrganizationLogin)

        setKnowledgeBases(kbs)
      } catch {
        setHadError(true)
      } finally {
        if (!ignore) {
          setIsLoading(false)
        }
      }
    }

    setIsLoading(true)
    fetch()

    return () => {
      ignore = true
    }
  }, [payload.currentOrganizationLogin, service])

  return (
    <KnowledgeBaseFormProviders>
      <KnowledgeBaseActionBanner />
      <PageHeader role="banner" aria-label="Knowledge bases">
        <PageHeader.TitleArea>
          <PageHeader.Title>Knowledge bases</PageHeader.Title>
        </PageHeader.TitleArea>
        <PageHeader.Actions>
          {knowledgeBases.length > 0 && (
            <Button as="a" href={payload.newKnowledgeBasePath} variant="primary">
              New knowledge base
            </Button>
          )}
        </PageHeader.Actions>
      </PageHeader>
      <p className="mt-2 mb-2">
        Knowledge bases are groups of repositories that are used by Copilot to ground responses in your organization’s
        data. When chatting with Copilot on GitHub.com, members of your organization may choose which knowledge base
        should be used to answer their questions.
      </p>
      {isLoading ? (
        <div className={styles.Box}>
          <Spinner />
        </div>
      ) : hadError ? (
        <Flash variant="danger">Failed to load knowledge bases.</Flash>
      ) : knowledgeBases.length > 0 ? (
        <>
          <KnowledgeBaseList
            currentOrganizationLogin={payload.currentOrganizationLogin}
            knowledgeBases={knowledgeBases}
            setKnowledgeBases={setKnowledgeBases}
          />
          <p className={styles.Text}>
            Knowledge bases are automatically reindexed when changes are pushed or merged to a repository&apos;s default
            branch.
          </p>
        </>
      ) : (
        <div className={styles.Box_1}>
          <Blankslate border>
            <Blankslate.Visual>
              <Octicon icon={BookIcon} size={24} className={styles.Octicon} />
            </Blankslate.Visual>
            <Blankslate.Heading>No knowledge bases</Blankslate.Heading>
            <Blankslate.Description>
              Create a knowledge base to enable your team to get quick and relevant answers from your organization’s
              Markdown documentation.
            </Blankslate.Description>
            <Blankslate.PrimaryAction href={payload.newKnowledgeBasePath}>New knowledge base</Blankslate.PrimaryAction>
          </Blankslate>
        </div>
      )}
    </KnowledgeBaseFormProviders>
  )
}

function getRepositoriesCount(knowledgeBase: Docset): string {
  if (knowledgeBase.sourceRepos) {
    return `${knowledgeBase.sourceRepos.length} ${
      knowledgeBase.sourceRepos.length === 1 ? 'repository' : 'repositories'
    }`
  }
  // TODO: remove this return statement once we fully move to sourceRepos
  return `${knowledgeBase.repos.length} ${knowledgeBase.repos.length === 1 ? 'repository' : 'repositories'}`
}

function KnowledgeBaseList({
  currentOrganizationLogin,
  knowledgeBases,
  setKnowledgeBases,
}: {
  currentOrganizationLogin: string
  knowledgeBases: Docset[]
  setKnowledgeBases: Dispatch<SetStateAction<Docset[]>>
}) {
  return (
    <div className={styles.Box_2}>
      {knowledgeBases.map((knowledgeBase: Docset) => (
        <div key={knowledgeBase.id} className={styles.Box_3}>
          <div className={styles.Box_4}>
            <Heading as="h2" className={styles.Heading}>
              <Truncate inline title={knowledgeBase.name} sx={{maxWidth: truncationWidths}}>
                {knowledgeBase.name}
              </Truncate>
            </Heading>
            <span className={styles.Text_1}>
              {knowledgeBase.description && (
                <Truncate inline title={knowledgeBase.description} sx={{maxWidth: truncationWidths}}>
                  {`${knowledgeBase.description}`}
                </Truncate>
              )}
            </span>
            <span className={styles.Text_2}>
              <KnowledgeBaseIndexStatus repos={knowledgeBase.repos} />
              {getRepositoriesCount(knowledgeBase)}
            </span>
          </div>
          <div className={styles.Box_5}>
            <IconButton
              as="a"
              href={`/organizations/${currentOrganizationLogin}/settings/copilot/chat_settings/${knowledgeBase.id}/edit`}
              aria-label={`Edit knowledge base`}
              variant="invisible"
              icon={PencilIcon}
            />
            <DeleteKnowledgeBaseButton
              knowledgeBase={knowledgeBase}
              currentOrganizationLogin={currentOrganizationLogin}
              setKnowledgeBases={setKnowledgeBases}
            />
          </div>
        </div>
      ))}
    </div>
  )
}

function DeleteKnowledgeBaseButton({
  knowledgeBase,
  currentOrganizationLogin,
  setKnowledgeBases,
}: {
  knowledgeBase: Docset
  currentOrganizationLogin: string
  setKnowledgeBases: Dispatch<SetStateAction<Docset[]>>
}) {
  const service = useContext(CopilotChatSettingsServiceContext)
  const [showDeleteConfirmation, setShowDeleteConfirmation] = useState(false)
  const [hasDeleteError, setHadDeleteError] = useState(false)
  const onDelete = async () => {
    try {
      await service.deleteKnowledgeBase(currentOrganizationLogin, knowledgeBase)
    } catch {
      setHadDeleteError(true)
    }

    setKnowledgeBases((prevKnowledgeBases: Docset[]) => prevKnowledgeBases.filter(kb => kb.id !== knowledgeBase.id))
    setShowDeleteConfirmation(false)
    // KnowledgeBaseActionBanner() uses the url to determine if a KB was created or updated. Deleting
    // a KB does not trigger a redirect so in order to make KnowledgeBaseActionBanner() easily reusable
    // we can just append the delete action param and KnowledgeBaseActionBanner() will handle the banner for it
    // We should also clear any existing action values before appending
    const url = new URL(location.href, window.location.origin)
    url.searchParams.delete('action')
    url.searchParams.append('action', 'deleted')
    updateUrl(url.toString())
  }
  return (
    <div>
      <IconButton
        aria-label="Delete knowledge base"
        icon={TrashIcon}
        onClick={() => setShowDeleteConfirmation(true)}
        variant="invisible"
      />
      {showDeleteConfirmation && (
        <Dialog
          footerButtons={[
            {buttonType: 'normal', content: 'Cancel', onClick: () => setShowDeleteConfirmation(false)},
            {buttonType: 'danger', content: 'Delete', onClick: () => void onDelete()},
          ]}
          onClose={() => setShowDeleteConfirmation(false)}
          renderBody={() => (
            <Dialog.Body>
              {hasDeleteError && (
                <Flash variant="danger" className={styles.Flash}>
                  Failed to delete knowledge base.
                </Flash>
              )}
              <span>
                You are about to delete the <strong>{knowledgeBase.name}</strong> knowledge base.
              </span>
            </Dialog.Body>
          )}
          title="Confirm deletion"
        />
      )}
    </div>
  )
}

function KnowledgeBaseActionBanner() {
  const [isHidden, setIsHidden] = useState(false)
  const search = ssrSafeLocation.search && new URLSearchParams(ssrSafeLocation.search)

  if (isHidden || !search) return null
  const action = search.get('action')
  if (!action || !['created', 'updated', 'deleted'].includes(action)) return null
  const flashMessage = `Knowledge base ${action}. ${
    action === 'created' || action === 'updated' ? 'Repositories may need to be indexed.' : ''
  }`

  return (
    <Banner
      title={'Knowledge bases'}
      hideTitle
      variant={action === 'created' ? 'success' : 'info'}
      description={<AriaAlert>{flashMessage}</AriaAlert>}
      className="mb-4"
      onDismiss={() => {
        // Determine what action parameter is provided in the url (eg. ?action=created)
        const url = new URL(location.href, window.location.origin)
        url.searchParams.delete('action')
        updateUrl(url.toString())
        setIsHidden(true)
      }}
    />
  )
}

// If we have any indexing errors, we should show the error state
// If we have no errors and the state is indexed, we should show the success state
// If we have no errors and the state is indexing, we should show the loading state
// If we have no errors and the state is unindexed, we should show the waiting state
function KnowledgeBaseIndexStatus({repos}: {repos: string[]}) {
  const [indexingState] = useReposIndexingState(repos)

  return (
    <div className={styles.Box_6}>
      {indexingState.requestStatus === CanIndexStatus.IndexingError ? (
        <>
          <Octicon icon={XIcon} color="danger.fg" className={styles.Octicon_1} />
          <span className={styles.Octicon}>Indexing error • See edit page for more details •</span>
          &nbsp;
        </>
      ) : indexingState.code === TopicIndexStatus.Indexed ? (
        <>
          <Octicon icon={CheckIcon} color="success.fg" className={styles.Octicon_1} />
          <span className={styles.Octicon}>Fully indexed •</span>
          &nbsp;
        </>
      ) : indexingState.code === TopicIndexStatus.Unindexed ? (
        <>
          <Spinner size="small" className={styles.Octicon_1} />
          <span className={styles.Octicon}>Indexing queued •</span>
          &nbsp;
        </>
      ) : indexingState.code === TopicIndexStatus.Indexing ? (
        <>
          <Spinner size="small" className={styles.Octicon_1} />
          <span className={styles.Octicon}>Indexing •</span>
          &nbsp;
        </>
      ) : indexingState.code === TopicIndexStatus.PartiallyIndexed ? (
        <>
          <Octicon icon={SkipFillIcon} color="success.fg" className={styles.Octicon_1} />
          <span className={styles.Octicon}>Partially indexed •</span>
          &nbsp;
        </>
      ) : (
        <></>
      )}
    </div>
  )
}
