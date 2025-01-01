import CopilotIconAnimation from '@github-ui/copilot-chat/components/CopilotIconAnimation'
import {LegalDisclaimer} from '@github-ui/copilot-chat/components/LegalDisclaimer'
import type {StarterEntry, StarterGroup} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {getCopilotSpacePath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {getSelectedThread} from '@github-ui/copilot-chat/utils/get-selected-thread'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {SafeHTMLDiv, type SafeHTMLString} from '@github-ui/safe-html'
import {ActionList, ActionMenu} from '@primer/react'
import {useMemo, useRef, useState} from 'react'
import {useNavigate} from 'react-router-dom'

import starters from '../../data/starters.json'
import type {CopilotImmersivePayload, Icebreaker} from '../../routes/payloads'
import {ChatInputContainer} from '../ChatInputContainer'
import {CopilotEmptyStateAnimation} from '../CopilotEmptyStateAnimation'
import {CreateIssue} from './CustomStarters/CreateIssue'
import {NewSpace} from './CustomStarters/NewSpace'
import styles from './NewConversation.module.css'
import {NewConversationBanners} from './NewConversationBanners'
import {StarterPill} from './StarterPill'
import {SuggestionCard} from './SuggestionCard'

type IcebreakerType = 'functional' | 'instructional' | 'interactional'

interface IcebreakerData {
  type: IcebreakerType
  data: Icebreaker[]
}

function isIcebreakerDataArray(value: unknown): value is IcebreakerData[] {
  return Array.isArray(value) && value.every(item => 'type' in item && 'data' in item)
}

function getRandomIcebreakers(icebreakers: Icebreaker[], count: number): Icebreaker[] {
  const shuffled = [...icebreakers].sort(() => 0.5 - Math.random())
  return shuffled.slice(0, count)
}

function getStarterGroups(hasSpaces: boolean, spacesStartersEnabled: boolean): StarterGroup[] {
  const allGroups = Object.values(starters) as unknown as StarterGroup[]

  /* When spacesStarters is OFF: show all groups including git-group */
  if (!spacesStartersEnabled) {
    return allGroups
  }

  /* When spacesStarters is ON and there ARE spaces: hide git-group (it's replaced by spacesStarterGroup) */
  if (spacesStartersEnabled && hasSpaces) {
    return allGroups.filter(group => {
      const groupsToHideWithSpaces = ['git-group']
      return !groupsToHideWithSpaces.includes(group.id)
    })
  }

  /* When spacesStarters is ON and there are NO spaces: show all groups including git-group */
  return allGroups
}

interface NewConversationProps {
  textAreaRef: React.RefObject<HTMLTextAreaElement>
  handleUserSubmit: (content: string) => Promise<void>
  nextMessageIndex: number
}

function StarterGroupWithMenu({
  group,
  onEntrySelect,
}: {
  group: StarterGroup
  onEntrySelect: (entry: StarterEntry) => void
}) {
  const [open, setOpen] = useState(false)
  const buttonRef = useRef<HTMLButtonElement>(null)

  const handleClick = () => {
    setOpen(!open)
  }

  return (
    <li className={styles.item}>
      <ActionMenu open={open} onOpenChange={setOpen}>
        <ActionMenu.Anchor>
          <StarterPill
            ref={buttonRef}
            name={group.name}
            icon={group.icon}
            color={group.color}
            onClick={handleClick}
            dropdown
          />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay style={{width: '260px'}}>
          <ActionList>
            {group.entries.map(entry => (
              <ActionList.Item key={entry.id} onSelect={() => onEntrySelect(entry)}>
                <SafeHTMLDiv html={entry.titleHtml} />
              </ActionList.Item>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </li>
  )
}

interface SpaceEntry extends StarterEntry {
  owner?: string
}

export function NewConversation({textAreaRef, handleUserSubmit, nextMessageIndex}: NewConversationProps) {
  const manager = useChatManager()
  const state = useChatState()
  const payload = useAppPayload<CopilotImmersivePayload>()
  const navigate = useNavigate()
  const currentThread = getSelectedThread(state)
  const hasSpaces = Boolean(state.customCopilots && state.customCopilots.length > 0)

  const spacesStarterGroup = useMemo((): StarterGroup | null => {
    const spaces = state.customCopilots
    if (!spaces?.length || !copilotFeatureFlags.spacesStarters) return null

    // Sort by updatedAt in descending order so we can get the "most recent" first
    const sortedSpaces = [...spaces].sort((a, b) => {
      const dateA = new Date(a.updatedAt).getTime()
      const dateB = new Date(b.updatedAt).getTime()
      return dateB - dateA
    })

    return {
      id: 'spaces',
      name: 'Spaces',
      icon: 'spaces',
      color: 'gray',
      entries: sortedSpaces
        .slice(0, 5) // Take just 5 so the menu doesn't get too long
        .map(space => ({
          id: String(space.id),
          titleHtml: space.name as SafeHTMLString,
          message: `@${space.id}`,
          owner: space.owner,
        })),
    }
  }, [state.customCopilots])

  const suggestions = useMemo(() => {
    if (isIcebreakerDataArray(payload.icebreakers)) {
      const selectedIcebreakers = isFeatureEnabled('copilot_showcase_icebreakers')
        ? {
            data: payload.icebreakers
              .filter(ib => ['functional', 'instructional'].includes(ib.type))
              .flatMap(ib => ib.data),
          }
        : payload.icebreakers.find(ib => ib.type === 'functional')
      if (selectedIcebreakers && selectedIcebreakers.data.length > 0) {
        const randomSuggestions: Icebreaker[] = getRandomIcebreakers(selectedIcebreakers.data, 6)
        return randomSuggestions
      }
    }
    return []
  }, [payload.icebreakers])

  const handleStarterEntrySelect = (entry: StarterEntry) => {
    const thread = state.messages.length === 0 ? currentThread : getSelectedThread(state)
    const currentUserLogin = state.currentUserLogin || ''
    const message = entry.message.replaceAll('$$USERNAME$$', currentUserLogin)

    void manager.sendChatMessage({
      thread,
      content: message,
      references: state.currentReferences,
      topic: state.currentTopic,
      context: state.context,
      customInstructions: state.customInstructions,
      model: state.model,
    })

    sendEvent('dotcom_chat.activate', {
      target: 'NEW_CONVERSATION_STARTER_MENU_ITEM',
      topic: state.currentTopic?.name,
      mode: 'immersive',
      starterId: entry.id,
    })
  }

  const handleSpaceSelect = (entry: StarterEntry) => {
    const spaceEntry = entry as SpaceEntry
    const spacePath = getCopilotSpacePath({
      id: Number(spaceEntry.id),
      ...(spaceEntry.owner && {owner: spaceEntry.owner}),
    })
    navigate(spacePath)

    sendEvent('dotcom_chat.activate', {
      target: 'NEW_CONVERSATION_SPACES_MENU_ITEM',
      topic: state.currentTopic?.name,
      mode: 'immersive',
      spaceId: entry.id,
    })
  }

  const starterGroups = useMemo(() => {
    if (copilotFeatureFlags.newConversationStarters) {
      return getStarterGroups(hasSpaces, copilotFeatureFlags.spacesStarters)
    }
    return []
  }, [hasSpaces])

  return (
    <div className={styles.scrollContainer}>
      <div className={styles.container}>
        <div className={styles.banner}>
          <NewConversationBanners />
        </div>
        <div className={styles.main}>
          <div className={styles.content}>
            <div className={styles.alignTop}>
              {useFeatureFlag('copilot_pro_plus_animation') ? (
                <CopilotEmptyStateAnimation />
              ) : (
                <CopilotIconAnimation hidden />
              )}
              <div className={styles.innerContainer}>
                <h1 className="sr-only">Copilot Chat</h1>
                <ChatInputContainer
                  textAreaRef={textAreaRef}
                  handleUserSubmit={handleUserSubmit}
                  nextMessageIndex={nextMessageIndex}
                />
                <h2 className="sr-only">Sample prompts to try</h2>
                <ul className={copilotFeatureFlags.newConversationStarters ? styles.starters : styles.suggestions}>
                  {copilotFeatureFlags.newConversationStarters ? (
                    <>
                      {!copilotFeatureFlags.spacesStarters ? (
                        /* Feature flag OFF: always show CreateIssue */
                        <CreateIssue />
                      ) : /* Feature flag ON: show NewSpace if no spaces and CreateIssue if there are spaces */
                      !hasSpaces ? (
                        <NewSpace />
                      ) : (
                        <CreateIssue />
                      )}

                      {/* Render starter groups (including git-group based on conditions) */}
                      {starterGroups.map(group => (
                        <StarterGroupWithMenu key={group.id} group={group} onEntrySelect={handleStarterEntrySelect} />
                      ))}

                      {/* Only show spacesStarterGroup when spacesStarters is ON and there are spaces */}
                      {copilotFeatureFlags.spacesStarters && spacesStarterGroup && (
                        <StarterGroupWithMenu
                          key={spacesStarterGroup.id}
                          group={spacesStarterGroup}
                          onEntrySelect={handleSpaceSelect}
                        />
                      )}
                    </>
                  ) : (
                    suggestions.map((suggestion: Icebreaker) => (
                      <li key={suggestion.id} className={styles.suggestionButton}>
                        <SuggestionCard
                          titleHtml={suggestion.titleHtml as SafeHTMLString}
                          icon={suggestion.icon}
                          color={suggestion.color}
                          onClick={() => {
                            const thread = state.messages.length === 0 ? currentThread : getSelectedThread(state)
                            const currentUserLogin = state.currentUserLogin
                            const message = suggestion.message
                            void manager.sendChatMessage({
                              thread,
                              content: message.replaceAll('$$USERNAME$$', currentUserLogin),
                              references: state.currentReferences,
                              topic: state.currentTopic,
                              context: state.context,
                              customInstructions: state.customInstructions,
                              model: state.model,
                            })
                            sendEvent('dotcom_chat.activate', {
                              target: 'EMPTY_STATE_SUGGESTION_CARD',
                              topic: state.currentTopic?.name,
                              mode: 'immersive',
                              suggestionId: suggestion.id,
                            })
                          }}
                        />
                      </li>
                    ))
                  )}
                </ul>
              </div>
            </div>
          </div>
        </div>
        <div className={styles.footer}>
          <LegalDisclaimer />
        </div>
      </div>
    </div>
  )
}
