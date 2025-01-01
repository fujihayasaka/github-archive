import type {ComponentType, MouseEvent} from 'react'

import type {CopilotChatState} from '../utils/copilot-chat-reducer'
import type {CreateMessageStreamingParams} from '../utils/copilot-chat-service'
import type {CopilotChatMessage, CopilotChatReference} from '../utils/copilot-chat-types'

export interface EmptyStateComponentProps {
  chatState: CopilotChatState
}

export type EmptyStateComponent = ComponentType<EmptyStateComponentProps>

export interface PreviewAreaComponentProps {
  chatState: CopilotChatState
  plugin: ImmersivePlugin
  closePreviewPane: () => void
}

export type PreviewAreaComponent = ComponentType<PreviewAreaComponentProps>

export interface NavigationComponentProps {
  chatState: CopilotChatState
  onLinkClick: (e: MouseEvent<HTMLAnchorElement>, pluginId: string) => void
}

export type NavigationComponent = ComponentType<NavigationComponentProps>

export interface ImmersivePlugin {
  /**
   * The unique identifier for the plugin.
   */
  readonly id: string

  /**
   * The display name of the plugin.
   */
  readonly displayName: string

  /*
   * Given a thread, return whether this plugin should be activated when it is selected.
   */
  matchThread?: (
    selectedThreadId: string | null,
    messages: CopilotChatMessage[],
    references: CopilotChatReference[],
  ) => boolean

  /**
   * Override the options for the create message streaming call.
   * This is useful for plugins that need to add additional data to the message.
   */
  overrideCreateMessageOptions?: (options: CreateMessageStreamingParams) => Promise<CreateMessageStreamingParams>

  /**
   * The empty state component to render when there are no messages in the current thread.
   */
  EmptyStateComponent?: EmptyStateComponent

  /**
   * The preview area component to render when the plugin is active.
   */
  PreviewAreaComponent?: PreviewAreaComponent

  /**
   * The navigation component to render in the immersive chat navigation sidebar. Should be a variant of PluginNavigation component.
   */
  NavigationComponent?: NavigationComponent

  /**
   * Allows the plugin to display a wider preview area (67vw).
   */
  widePreviewArea?: boolean
}
