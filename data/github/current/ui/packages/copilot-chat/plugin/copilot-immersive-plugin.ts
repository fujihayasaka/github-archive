import type {CopilotMarkdownExtension} from '@github-ui/copilot-markdown/extension'
import type {ComponentType, MouseEvent} from 'react'
import type {Location} from 'react-router-dom'

import type {CopilotChatState} from '../utils/copilot-chat-reducer'
import type {CreateMessageStreamingParams} from '../utils/copilot-chat-service'
import type {CopilotChatMessage, CopilotChatReference} from '../utils/copilot-chat-types'

export interface ViewComponentProps {
  chatState: CopilotChatState
  closePreviewPane: () => void
  openPreviewPane: () => void
  plugin: ImmersivePlugin
}

export type ViewComponent = ComponentType<ViewComponentProps>

export interface PageComponentProps {
  chatState: CopilotChatState
  plugin: ImmersivePlugin
}

export type PageComponent = ComponentType<PageComponentProps>

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

  /**
   * List of regex patterns that will be used to match the URL path. If the current URL path matches any of these patterns,
   * the plugin will be activated.
   *
   * @example ['/copilot/loops', '/copilot/l/.*']
   */
  readonly routes?: RegExp[]

  /**
   * List of markdown extensions that will be used to render markdown in the plugin.
   * These extensions will be used in addition to the default extensions.
   */
  readonly markdownExtensions?: Array<() => CopilotMarkdownExtension>

  /**
   * Tells immersive chat to skip syncing the route to the thread.
   * This is useful for plugins that have their own routing logic and don't want to be
   * tied to the thread ID in the URL.
   */
  readonly skipSyncRouteToThread?: boolean

  /*
   * Given a thread, return whether this plugin should be activated when it is selected.
   */
  matchThread?: (
    selectedThreadId: string | null,
    messages: CopilotChatMessage[],
    references: CopilotChatReference[],
  ) => boolean

  /**
   * Given a location, return whether this plugin's PageComponent should be shown.
   */
  matchPage?: (location: Location) => boolean

  /**
   * Given a location, return whether this plugin's ViewComponent should be shown.
   */
  matchView?: (location: Location) => boolean

  /**
   * Override the options for the create message streaming call.
   * This is useful for plugins that need to add additional data to the message.
   */
  overrideCreateMessageOptions?: (options: CreateMessageStreamingParams) => Promise<CreateMessageStreamingParams>

  /**
   * The view component to render when the plugin is active.
   * This takes over the main content area of the chat (everything but the sidebar).
   * An implementation of matchView must also be provided.
   */
  ViewComponent?: ViewComponent

  /**
   * The view component to render when the plugin is active. This takes over the full page. An implementation of
   * matchPage must also be provided.
   */
  PageComponent?: PageComponent

  /**
   * The navigation component to render in the immersive chat navigation sidebar. Should be a variant of PluginNavigation component.
   */
  NavigationComponent?: NavigationComponent

  /**
   * Allows the plugin to display a fullscreen preview area.
   */
  fullscreenPreviewArea?: boolean
}
