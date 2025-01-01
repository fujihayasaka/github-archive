import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import type {CreateMessageStreamingParams} from '@github-ui/copilot-chat/utils/copilot-chat-service'
import {PipesEmptyState} from './components/PipesEmptyState'
import {PipesPreviewArea} from './components/PipesPreviewArea'
import {PipesNavigation} from './components/PipesNavigation'
import {PIPES_PLUGIN_ID, PIPES_PLUGIN_NAME} from './utils/constants'
import {getLatestPipe} from './utils/chat-helpers'
import type {CopilotChatMessage, CopilotChatReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {PipesService} from './service/pipes-service'
import {IndexedDBPipesStorage} from './service/pipes-storage'
import {ChatCompletionsClient} from './service/chat-completions-client'
import {GraphQLClient} from './service/graphql-client'

export class PipesPlugin implements ImmersivePlugin {
  public id = PIPES_PLUGIN_ID

  public displayName = PIPES_PLUGIN_NAME

  constructor(completionsApiUrl: string, graphqlApiUrl: string, ssoOrgIDs: string[], realIp?: string) {
    this.service = new PipesService(
      new IndexedDBPipesStorage(),
      new GraphQLClient(graphqlApiUrl),
      new ChatCompletionsClient(completionsApiUrl, ssoOrgIDs, realIp),
    )
  }

  public service: PipesService

  public widePreviewArea = true

  public EmptyStateComponent = PipesEmptyState

  public PreviewAreaComponent = PipesPreviewArea

  public NavigationComponent = PipesNavigation

  public matchThread(selectedThreadId: string | null, messages: CopilotChatMessage[]): boolean {
    const pipeFromThread = getLatestPipe(selectedThreadId, messages)
    return !!pipeFromThread
  }

  public async overrideCreateMessageOptions(
    options: CreateMessageStreamingParams,
  ): Promise<CreateMessageStreamingParams> {
    return {
      ...options,
      references: await this.addReferenceForEditedPipeline(options.threadID, options.references),
      mode: PIPES_PLUGIN_ID,
    }
  }

  private async addReferenceForEditedPipeline(
    threadID: string,
    references: CopilotChatReference[],
  ): Promise<CopilotChatReference[]> {
    if (!this.service) return references

    const currentPipeline = await this.service.getPipeline(threadID)
    return currentPipeline ? [...references, {type: 'text', text: JSON.stringify(currentPipeline)}] : references
  }
}
