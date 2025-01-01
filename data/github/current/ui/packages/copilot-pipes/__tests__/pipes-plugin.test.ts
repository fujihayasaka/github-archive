import type {CreateMessageStreamingParams} from '@github-ui/copilot-chat/utils/copilot-chat-service'
import {PipesPlugin} from '../pipes-plugin'
import {IndexedDBPipesStorage} from '../service/pipes-storage'
import {defaultExecutionState} from '../state/pipes-state'

jest.spyOn(IndexedDBPipesStorage.prototype, 'getExecutionState').mockImplementation(async () => defaultExecutionState)
jest.spyOn(IndexedDBPipesStorage.prototype, 'getPipeline').mockImplementation(async () => null)

test('overrideCreateMessageOptions', async () => {
  const plugin = new PipesPlugin('', '', [])
  const requestOptions = await plugin.overrideCreateMessageOptions({mode: 'immersive'} as CreateMessageStreamingParams)
  expect(requestOptions.mode).toBe('pipes')
})
