import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import {PipesPreviewArea} from './components/PipesPreviewArea'
import {PipesNavigation} from './components/PipesNavigation'
import {
  CHAT_MODE_LOOPS,
  LOOP_REGEX,
  LOOP_SHARE_REGEX,
  LOOPS_PLUGIN_ID,
  LOOPS_PLUGIN_NAME,
  LOOPS_REGEX,
} from './utils/constants'
import loopBlocksExtension from './markdown-extensions/loop-blocks/LoopBlocksExtension'
import {getLatestPipe} from './utils/chat-helpers'
import type {CopilotChatMessage} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {PipesService} from './service/pipes-service'
import {IndexedDBPipesStorage} from './service/pipes-storage'
import {ChatCompletionsClient} from './service/chat-completions-client'
import {GraphQLClient} from './service/graphql-client'
import {LoopsView} from './components/loops-view/LoopsView'
import type {CreateMessageStreamingParams} from '@github-ui/copilot-chat/utils/copilot-chat-service'
import type {Location} from 'react-router-dom'
import {ssrSafeLocation} from '@github-ui/ssr-utils'

export class PipesPlugin implements ImmersivePlugin {
  public id = LOOPS_PLUGIN_ID

  public displayName = LOOPS_PLUGIN_NAME

  constructor(
    completionsApiUrl: string,
    graphqlApiUrl: string,
    ssoOrgIDs: string[],
    previewUrl: string,
    realIp?: string,
  ) {
    this.service = new PipesService(
      new IndexedDBPipesStorage(),
      new GraphQLClient(graphqlApiUrl),
      new ChatCompletionsClient(completionsApiUrl, ssoOrgIDs, realIp),
    )
    this.previewUrl = previewUrl
  }

  public service: PipesService

  public previewUrl: string

  public markdownExtensions = [loopBlocksExtension]

  public matchPage(location: Location): boolean {
    if (!location) return false

    return LOOP_REGEX.test(location.pathname) || LOOP_SHARE_REGEX.test(location.pathname)
  }

  public matchView(location: Location): boolean {
    if (!location) return false

    return LOOPS_REGEX.test(location.pathname)
  }

  public routes = [LOOPS_REGEX, LOOP_REGEX, LOOP_SHARE_REGEX]

  public skipSyncRouteToThread = true

  public PageComponent = PipesPreviewArea

  public ViewComponent = LoopsView

  public NavigationComponent = PipesNavigation

  public matchThread(selectedThreadId: string | null, messages: CopilotChatMessage[]): boolean {
    if (this.routes.some(route => route.test(ssrSafeLocation.pathname))) return true

    const pipeFromThread = getLatestPipe(selectedThreadId, messages, /** searchUserMessages */ true)
    return !!pipeFromThread
  }

  public async overrideCreateMessageOptions(
    options: CreateMessageStreamingParams,
  ): Promise<CreateMessageStreamingParams> {
    return {
      ...options,
      mode: CHAT_MODE_LOOPS,
    }
  }
}
