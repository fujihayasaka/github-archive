import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import type {CreateMessageStreamingParams} from '@github-ui/copilot-chat/utils/copilot-chat-service'
import {WorkbenchEmptyState} from './components/WorkbenchEmptyState'
import {WorkbenchNavigation} from './components/WorkbenchNavigation'
import {WORKBENCH_PLUGIN_ID, WORKBENCH_PLUGIN_NAME} from './utils/constants'

export class WorkbenchPlugin implements ImmersivePlugin {
  public id = WORKBENCH_PLUGIN_ID

  public displayName = WORKBENCH_PLUGIN_NAME

  public widePreviewArea = true

  public EmptyStateComponent = WorkbenchEmptyState

  public NavigationComponent = WorkbenchNavigation

  public async overrideCreateMessageOptions(
    options: CreateMessageStreamingParams,
  ): Promise<CreateMessageStreamingParams> {
    return {
      ...options,
      mode: WORKBENCH_PLUGIN_ID,
    }
  }
}
