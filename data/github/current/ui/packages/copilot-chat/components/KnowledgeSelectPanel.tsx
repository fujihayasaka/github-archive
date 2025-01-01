import {GitHubAvatar} from '@github-ui/github-avatar'
import safeStorage from '@github-ui/safe-storage'
import {testIdProps} from '@github-ui/test-id-props'
import {AlertIcon, BookIcon, XIcon} from '@primer/octicons-react'
import {
  ActionList,
  AnchoredOverlay,
  type BetterSystemStyleObject,
  Box,
  Button,
  Heading,
  IconButton,
  Link,
  SelectPanel,
  Text,
  Truncate,
} from '@primer/react'
import {type ActionListGroupedListProps, type ActionListItemInput, Octicon} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import {forwardRef, type RefObject, useEffect, useMemo, useRef, useState} from 'react'
import {flushSync} from 'react-dom'

import {isDocset, makeDocsetReference} from '../utils/copilot-chat-helpers'
import type {CopilotChatMode, CopilotChatOrg, Docset} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {copilotLocalStorage} from '../utils/copilot-local-storage'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import styles from './KnowledgeSelectPanel.module.css'

const KBIconButton = forwardRef<HTMLButtonElement, {open: boolean; setOpen: (v: boolean) => void}>(
  function KBIconButtonInner({open, setOpen, ...buttonProps}, ref) {
    return (
      <IconButton
        ref={ref}
        aria-expanded={open ? true : undefined}
        aria-haspopup
        aria-label="Attach knowledge base"
        aria-labelledby={undefined}
        icon={BookIcon}
        onClick={() => setOpen(!open)}
        sx={{color: 'fg.muted'}}
        variant="invisible"
        {...buttonProps}
      />
    )
  },
)

interface KnowledgeSelectPanelProps {
  disabledForPreviewModelsProps?: Partial<DisabledForPreviewModelsProps>
  emptyKnowledgeBaseProps?: Partial<EmptyKnowledgeBaseProps>
  open: boolean
  onOpenChange: (val: boolean) => void
  anchorRef: RefObject<HTMLElement>
}

/** `SelectPanel` for filtering and selecting a knowledge base (AKA docset). */
export function KnowledgeSelectPanel({
  disabledForPreviewModelsProps,
  emptyKnowledgeBaseProps,
  open,
  onOpenChange,
  anchorRef,
}: KnowledgeSelectPanelProps) {
  const state = useChatState()
  const manager = useChatManager()
  const safeLocalStorage = safeStorage('localStorage')

  const {knowledgeBases} = state
  const [administratedCopilotEnterpriseOrganizations, setAdministratedCopilotEnterpriseOrganizations] = useState<
    CopilotChatOrg[]
  >([])
  const [orgLoading, setOrgLoading] = useState(true)
  const [filter, setFilter] = useState('')
  const containerRef = useRef<HTMLDivElement>(null)

  const lastUsedKnowledgeBaseId = safeLocalStorage.getItem('lastUsedKnowledgeBaseId') || ''
  const lastUsedKnowledgeBaseOrg = safeLocalStorage.getItem('lastUsedKnowledgeBaseOrg') || ''
  const {currentReferences} = state

  useEffect(() => {
    if (!open) setFilter('')
  }, [open])

  const filteredItems = useMemo(() => {
    if (filter === '') return knowledgeBases
    return knowledgeBases.filter(item => {
      return item.name.toLowerCase().includes(filter.toLowerCase())
    })
  }, [filter, knowledgeBases])

  const groups = useMemo(() => {
    return filteredItems.reduce<Array<{org: string; docsets: Docset[]}>>((orgs, item) => {
      const entry = orgs.find(org => org.org === item.ownerLogin)
      if (entry) {
        entry.docsets.push(item)
      } else {
        orgs.push({org: item.ownerLogin, docsets: [item]})
      }
      return orgs
    }, [])
  }, [filteredItems])

  const [isOrgLoadingError, setIsOrgLoadingError] = useState(false)

  const loading = orgLoading || state.knowledgeBasesLoading.state === 'pending'
  const isError = isOrgLoadingError || state.knowledgeBasesLoading.state === 'error'

  useEffect(() => {
    const fetchDocsetsAndOrgs = async () => {
      setOrgLoading(true)
      await manager.fetchKnowledgeBases()
      const orgResponse = await manager.service.listAdministratedCopilotEnterpriseOrganizations()
      if (orgResponse.ok) {
        setAdministratedCopilotEnterpriseOrganizations(orgResponse.payload || [])
      } else {
        setIsOrgLoadingError(true)
      }
      setOrgLoading(false)
    }

    if (open) void fetchDocsetsAndOrgs()
    // Just run once when component loads
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  const ssoMessage = useSSOMessage()

  const setDocsetTopic = (docset: Docset) => {
    void manager.dismissAttachKnowledgeBaseHerePopover()

    // Clear up all existing references
    manager.clearCurrentReferences(['image', 'issue'])
    manager.clearCurrentTopic()
    if (state.selectedThreadID) {
      copilotLocalStorage.setSelectedTopic(state.selectedThreadID, null)
    }

    const reference = makeDocsetReference(docset)

    manager.addReference(reference, 'docsetMenu')

    safeLocalStorage.setItem('lastUsedKnowledgeBaseId', docset.id)
    safeLocalStorage.setItem('lastUsedKnowledgeBaseOrg', docset.ownerLogin)
  }

  const compareLastUsedKb = (a: Docset, b: Docset) => {
    if (a.id === lastUsedKnowledgeBaseId) return -1
    if (b.id === lastUsedKnowledgeBaseId) return 1
    return 0
  }

  const compareLastUsedKbOrg = (a: {org: string; docsets: Docset[]}, b: {org: string; docsets: Docset[]}) => {
    if (a.org === lastUsedKnowledgeBaseOrg) return -1
    if (b.org === lastUsedKnowledgeBaseOrg) return 1
    return 0
  }

  const toggleDocsetReferences = (docsets: Docset[]) => {
    const referencesToAdd = docsets.filter(
      ref => isDocset(ref) && !currentReferences.some(r => isDocset(r) && r.id === ref.id),
    )
    const referencesToRemove = currentReferences.filter(ref => isDocset(ref) && !docsets.some(d => d.id === ref.id))

    for (const ref of referencesToRemove) {
      manager.removeReference(ref)
    }

    for (const ref of referencesToAdd) {
      manager.addReference(makeDocsetReference(ref), 'docsetMenu')
    }
  }

  if (state.model?.hasLimitedCapabilities) {
    return <DisabledForPreviewModels open={open} setOpen={onOpenChange} {...disabledForPreviewModelsProps} />
  }

  if (!loading && knowledgeBases.length === 0) {
    return (
      <EmptyKnowledgeBase
        administratedCopilotEnterpriseOrganizations={administratedCopilotEnterpriseOrganizations}
        persistentPanelStyles={{
          position: ['fixed', 'fixed', 'absolute'],
          bottom: ['60px', '60px', '0 !important'],
          '@media screen and (max-height: 480px)': {
            bottom: '0 !important',
          },
          top: 'initial !important',
          left: ['18px', '18px', 'calc(50% - 360px) !important'],
          maxHeight: '100%',
        }}
        open={open}
        setOpen={onOpenChange}
        mode={state.mode}
        {...emptyKnowledgeBaseProps}
      />
    )
  }

  const onSelectedChange = (selected: ActionListItemInput[] | ActionListItemInput | undefined) => {
    if (copilotFeatureFlags.topicsAsReferences) {
      // this is the entire list of selected docSets in the SelectPanel
      const selectedDocsets: Docset[] = (selected as ActionListItemInput[])
        .map(item => knowledgeBases.find(docset => docset.id === item.id))
        .filter((docset): docset is Docset => docset !== undefined)

      toggleDocsetReferences(selectedDocsets)
    } else {
      // single selected docset (or undefined)
      const selectedDocset = (selected as ActionListItemInput)
        ? knowledgeBases.find(docset => docset.id === (selected as ActionListItemInput).id)
        : undefined

      if (selectedDocset && selected) {
        setDocsetTopic(selectedDocset)
      }
    }
  }

  const items: ActionListItemInput[] = filteredItems.sort(compareLastUsedKb).map(docset => {
    return {
      id: docset.id,
      key: docset.id,
      groupId: docset.ownerLogin,
      text: docset.name,
      description: docset.description,
      disabled: !docset.canChat,
      descriptionVariant: 'block',
    }
  })

  const groupMetadata: ActionListGroupedListProps['groupMetadata'] = [...groups]
    .sort(compareLastUsedKbOrg)
    .map(group => ({
      id: group.org,
      key: group.org,
      text: group.org,
      groupId: group.org,
      header: {title: group.org},
    }))

  const selected = knowledgeBases.filter(item => currentReferences.some(ref => isDocset(ref) && ref.id === item.id))

  const multiSelectProps = {
    selected,
    onSelectedChange: (selectedDocsetItems: ActionListItemInput[]) => onSelectedChange(selectedDocsetItems),
  }

  const singleSelectProps = {
    selected: selected.length > 0 ? selected[0] : undefined,
    onSelectedChange: (selectedItem: ActionListItemInput | undefined) => onSelectedChange(selectedItem),
  }

  return (
    <div ref={containerRef} {...testIdProps('knowledge-select-panel')}>
      {/* eslint-disable-next-line primer-react/no-system-props */}
      <SelectPanel
        title={copilotFeatureFlags.topicsAsReferences ? 'Select knowledge bases' : 'Select a knowledge base'}
        subtitle="Knowledge bases consolidate content from multiple repositories for an improved chat experience."
        onCancel={() => {
          // eslint-disable-next-line @eslint-react/dom/no-flush-sync
          flushSync(() => onOpenChange(false))
          anchorRef.current?.focus()
        }}
        open={open}
        renderAnchor={null}
        anchorRef={anchorRef}
        onOpenChange={onOpenChange}
        loading={loading}
        items={items}
        onFilterChange={setFilter}
        groupMetadata={groupMetadata}
        notice={
          ssoMessage !== null
            ? {
                text: ssoMessage,
                variant: 'info',
              }
            : undefined
        }
        message={
          isError
            ? {
                variant: 'error',
                title: 'Failed to load knowledge bases',
                body: 'Try again later',
              }
            : groups.length === 0
              ? {
                  variant: 'empty',
                  title: `No knowledge bases found for \`${filter}\``,
                  body: 'Try a different search term',
                }
              : undefined
        }
        {...(copilotFeatureFlags.topicsAsReferences ? multiSelectProps : singleSelectProps)}
        variant="modal"
        overlayProps={{
          maxHeight: 'xlarge',
        }}
        width="large"
      />
    </div>
  )
}

interface EmptyKnowledgeBaseProps {
  anchorRef?: RefObject<HTMLButtonElement>
  administratedCopilotEnterpriseOrganizations: CopilotChatOrg[]
  persistentPanelStyles: BetterSystemStyleObject
  open: boolean
  setOpen: (val: boolean) => void
  mode: CopilotChatMode
}

function EmptyKnowledgeBase({
  administratedCopilotEnterpriseOrganizations,
  anchorRef,
  open,
  setOpen,
}: EmptyKnowledgeBaseProps) {
  const ssoMessage = useSSOMessage()
  const anchorProps = anchorRef
    ? {anchorRef, renderAnchor: null}
    : {anchorRef: undefined, renderAnchor: ({...props}) => <KBIconButton open={open} setOpen={setOpen} {...props} />}
  const noAdministratedCopilotEnterpriseOrganizations = administratedCopilotEnterpriseOrganizations?.length === 0
  const middleBoxProps = noAdministratedCopilotEnterpriseOrganizations
    ? {flexGrow: 1, maxHeight: '100%', overflowY: 'auto'}
    : {}
  const subBoxProps = noAdministratedCopilotEnterpriseOrganizations ? {maxHeight: '100%'} : {}
  const boxProps = noAdministratedCopilotEnterpriseOrganizations ? {height: '100%'} : {}

  return (
    <AnchoredOverlay
      open={open}
      onOpen={() => setOpen(true)}
      onClose={() => setOpen(false)}
      overlayProps={{
        anchorSide: 'outside-bottom',
        sx: {
          width: 'min(100%, 350px)',
        },
      }}
      {...anchorProps}
    >
      <Box
        role="dialog"
        aria-labelledby="knowledge-base-dialog-title"
        sx={{display: 'flex', flexDirection: 'column', ...boxProps}}
        {...testIdProps('empty-knowledge-base-picker')}
      >
        <Box
          sx={{
            borderBottom: '1px solid',
            borderColor: 'border.muted',
          }}
        >
          <Box sx={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', py: 2, px: 3}}>
            <Heading id="knowledge-base-dialog-title" as="h4" sx={{fontSize: 1}}>
              Attach a knowledge base
            </Heading>
            {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
            <IconButton
              unsafeDisableTooltip
              aria-label="Close"
              icon={XIcon}
              variant="invisible"
              onClick={() => setOpen(false)}
            />
          </Box>
        </Box>
        <Box sx={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3, pt: 3, ...middleBoxProps}}>
          <Octicon icon={BookIcon} size="medium" sx={{color: 'fg.muted'}} />
          <Box sx={{gap: 2, display: 'flex', alignItems: 'center', flexDirection: 'column', ...subBoxProps}}>
            <Text sx={{fontSize: 1, fontWeight: 600}}>You don&apos;t have any knowledge bases</Text>
            <Box sx={{color: 'fg.muted', textAlign: 'center', fontSize: 0, px: 3}}>
              <p>Knowledge bases consolidate content from multiple repositories for an improved chat experience.</p>
              {noAdministratedCopilotEnterpriseOrganizations && (
                <Text as="p" sx={{mt: 3, mb: 4}} {...testIdProps('ask-admin-for-knowledge-base')}>
                  Speak with an organization owner about creating a knowledge base for your organization.
                </Text>
              )}
            </Box>

            {administratedCopilotEnterpriseOrganizations.length > 0 && (
              <CreateKnowledgeBaseButton
                administratedCopilotEnterpriseOrganizations={administratedCopilotEnterpriseOrganizations}
              />
            )}
          </Box>
        </Box>
        {ssoMessage && (
          <Box sx={{borderTop: '1px solid', borderColor: 'border.muted', px: 2, py: 3}}>
            <SSOFooter message={ssoMessage} />
          </Box>
        )}
      </Box>
    </AnchoredOverlay>
  )
}

function CreateKnowledgeBaseButton({
  administratedCopilotEnterpriseOrganizations,
}: {
  administratedCopilotEnterpriseOrganizations: CopilotChatOrg[]
}) {
  if (administratedCopilotEnterpriseOrganizations.length === 1) {
    return (
      <Button
        as="a"
        href={pathToChatSettings(administratedCopilotEnterpriseOrganizations[0]!)}
        sx={{mb: 4}}
        {...testIdProps('create-knowledge-base-button')}
      >
        Create a knowledge base
      </Button>
    )
  } else {
    return (
      <Box
        sx={{width: '100%', textAlign: 'left', borderTop: '1px solid', borderColor: 'border.muted', pt: 3}}
        {...testIdProps('create-knowledge-base-dropdown')}
      >
        <Heading as="h3" sx={{fontSize: 0, color: 'fg.muted', pl: 3}}>
          Create a knowledge base for an organization
        </Heading>
        <ActionList sx={{maxHeight: '160px', overflow: 'scroll'}}>
          {administratedCopilotEnterpriseOrganizations.map(org => (
            <CreateKnowledgeBaseActionRow key={org.id} org={org} />
          ))}
        </ActionList>
      </Box>
    )
  }
}

function CreateKnowledgeBaseActionRow({org}: {org: CopilotChatOrg}) {
  return (
    <ActionList.Item>
      {/* It is ok to link directly to chats settings even if the org needs SSO. If the user needs to SSO in they
            will be taken to the SSO page and redirected to the chat settings URL on successful authentication */}
      <Link sx={{flex: 1, color: 'fg.default'}} href={pathToChatSettings(org)}>
        <GitHubAvatar square src={org.avatarUrl} alt={org.login} sx={{mr: 2}} aria-hidden="true" />
        <Truncate inline title={org.login} sx={{minWidth: '80%'}}>
          {org.login}
        </Truncate>
      </Link>
    </ActionList.Item>
  )
}

function SSOFooter({message}: {message: string}) {
  if (!message) return null

  return (
    <Box data-testid="knowledge-select-panel-sso" sx={{color: 'fg.muted', fontSize: 0, ml: 2}}>
      {message}
    </Box>
  )
}

function useSSOMessage() {
  const state = useChatState()
  const allProtectedOrgs = state.ssoOrganizations.map(org => org.login)
  for (const item of state.knowledgeBases) {
    const protectedOrganizations = item.protectedOrganizations
    for (const org of protectedOrganizations) {
      if (!allProtectedOrgs.includes(org)) {
        allProtectedOrgs.push(org)
      }
    }
  }

  if (!allProtectedOrgs || allProtectedOrgs.length === 0) {
    return null
  } else if (allProtectedOrgs.length === 1) {
    return `Single sign-on to see content from ${allProtectedOrgs[0]!}.`
  } else if (allProtectedOrgs.length === 2) {
    return `Single sign-on to see content from ${allProtectedOrgs[0]!} and ${allProtectedOrgs[1]!}.`
  } else {
    const remainder = allProtectedOrgs.length - 2
    return `Single sign-on to see content from ${allProtectedOrgs[0]!}, ${allProtectedOrgs[1]!}, and ${remainder} organization${
      remainder > 1 ? 's' : ''
    }`
  }
}

function pathToChatSettings(org: CopilotChatOrg) {
  return `/organizations/${org.login}/settings/copilot/chat_settings/new`
}

export interface DisabledForPreviewModelsProps {
  anchorRef?: RefObject<HTMLButtonElement>
  open: boolean
  setOpen: (v: boolean) => void
}

function DisabledForPreviewModels({anchorRef, open, setOpen}: DisabledForPreviewModelsProps) {
  const anchorProps = anchorRef
    ? {anchorRef, renderAnchor: null}
    : {anchorRef: undefined, renderAnchor: ({...props}) => <KBIconButton open={open} setOpen={setOpen} {...props} />}

  return (
    <AnchoredOverlay open={open} onOpen={() => setOpen(true)} onClose={() => setOpen(false)} {...anchorProps}>
      <div
        className={clsx('m-3 d-flex flex-column flex-items-center text-center', styles.disabledForPreviewModelsPanel)}
      >
        <AlertIcon className="fgColor-attention mb-3" />
        <h3 className="h5 mb-2">Knowledge bases aren&apos;t supported by this model</h3>
        <span className="text-small fgColor-muted">Switch back to the GPT-4o model or start a new conversation</span>
      </div>
    </AnchoredOverlay>
  )
}
