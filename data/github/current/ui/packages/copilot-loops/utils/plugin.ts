import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import {PipesService} from '../service/pipes-service'
import {LOOPS_PLUGIN_ID} from './constants'

export function isPipesPlugin(
  plugin: ImmersivePlugin,
): plugin is ImmersivePlugin & {service: PipesService; previewUrl: string} {
  return plugin.id === LOOPS_PLUGIN_ID && 'service' in plugin && plugin.service instanceof PipesService
}
