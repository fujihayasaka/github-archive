import {GitHubAvatar} from '@github-ui/github-avatar'
import {sendEvent} from '@github-ui/hydro-analytics'
import {LinkExternalIcon, MentionIcon, TelescopeIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'

import {AGENT_PREFIX, AGENTS_MARKETPLACE_URL, useAvailableAgents} from '../utils/agents-helpers'
import type {CopilotChatAgent} from '../utils/copilot-chat-types'
import type {AttachmentMenuPanelType} from './AttachmentMenuPanelType'

export function AgentMenu({
  onSelectPanel,
  onSelectAgent,
}: {
  onSelectPanel: (panel: AttachmentMenuPanelType) => void
  onSelectAgent: (agent: CopilotChatAgent) => void
}) {
  const {availableAgents, showLimit, disabled, loading} = useAvailableAgents()
  const agentsAreAvailable = availableAgents && availableAgents.length > 0

  if (loading)
    return (
      <ActionList.Item disabled>
        <ActionList.LeadingVisual>
          <MentionIcon />
        </ActionList.LeadingVisual>
        Extension
      </ActionList.Item>
    )

  if (disabled)
    return (
      <ActionList.Item
        onSelect={() => {
          sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_EXTENSION_NOT_SUPPORTED', mode: 'immersive'})
          onSelectPanel('agents-not-supported')
        }}
      >
        <ActionList.LeadingVisual>
          <MentionIcon />
        </ActionList.LeadingVisual>
        Extension&hellip;
      </ActionList.Item>
    )

  if (!agentsAreAvailable)
    return (
      <ActionList.Item
        onSelect={() => {
          sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_EXTENSION_NOT_AVAILABLE', mode: 'immersive'})
          onSelectPanel('no-agents-available')
        }}
      >
        <ActionList.LeadingVisual>
          <MentionIcon />
        </ActionList.LeadingVisual>
        Extension&hellip;
      </ActionList.Item>
    )

  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <ActionList.Item
          onSelect={() => {
            sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_EXTENSION', mode: 'immersive'})
          }}
        >
          <ActionList.LeadingVisual>
            <MentionIcon />
          </ActionList.LeadingVisual>
          Extension
        </ActionList.Item>
      </ActionMenu.Anchor>
      <ActionMenu.Overlay width="small">
        <ActionList>
          {availableAgents.map(agent => (
            <ActionList.Item
              key={agent.slug}
              onSelect={() => {
                sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_EXTENSION_SELECTED', mode: 'immersive'})
                onSelectAgent(agent)
              }}
            >
              <ActionList.LeadingVisual>
                <GitHubAvatar src={agent.avatarUrl} />
              </ActionList.LeadingVisual>
              {agent.name}
              <ActionList.Description variant="inline" truncate>
                {AGENT_PREFIX}
                {agent.slug}
              </ActionList.Description>
              {showLimit && (
                <ActionList.Description variant="block">
                  Start a new conversation to use other extensions.
                </ActionList.Description>
              )}
            </ActionList.Item>
          ))}
          <ActionList.Divider />
          <ActionList.LinkItem
            href={AGENTS_MARKETPLACE_URL}
            onClick={() => {
              sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU_EXTENSION_MARKETPLACE', mode: 'immersive'})
            }}
          >
            <ActionList.LeadingVisual>
              <TelescopeIcon />
            </ActionList.LeadingVisual>
            Marketplace
            <ActionList.TrailingVisual>
              <LinkExternalIcon />
            </ActionList.TrailingVisual>
          </ActionList.LinkItem>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
