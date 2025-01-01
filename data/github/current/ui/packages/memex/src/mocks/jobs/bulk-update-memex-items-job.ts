import type {
  BulkUpdateMemexItemsRequest,
  IUpdateMemexItemRequest,
  UpdateMemexItemResponse,
} from '../../client/api/memex-items/contracts'
import {MemexPaginatedRefreshEvents} from '../data/memex-refresh-events'
import {BaseJob} from './base-job'
import {JobQueuesTypes} from './job'

/**
 * A limited interface representing the pieces of the mock server needed by this job
 */
interface MockServerInterface {
  memexItems: MemexItemsControllerInterface
  liveUpdate: LiveUpdatesControllerInterface
  sleep: (delay: number) => Promise<unknown>
}

/**
 * A limited interface representing the pieces of the MemexItemsController needed by this job
 */
interface MemexItemsControllerInterface {
  update: (request: IUpdateMemexItemRequest) => Promise<UpdateMemexItemResponse>
}

/**
 * A limited interface representing the pieces of the LiveUpdatesController needed by this job
 */
interface LiveUpdatesControllerInterface {
  sendSocketMessage: (args: {type: ObjectValues<typeof MemexPaginatedRefreshEvents>}) => boolean | undefined
  sendBulkUpdateProgressSocketMessage: (args: {percentage: number; requestId: string}) => boolean | undefined
  sendBulkUpdateCompleteSocketMessage: (args: {bulkUpdateSuccess: boolean; requestId: string}) => boolean | undefined
}

export class BulkUpdateMemexItemsJob extends BaseJob {
  #args: BulkUpdateMemexItemsRequest
  #server: MockServerInterface
  #requestId: string
  queue = JobQueuesTypes.BULK_UPDATE_MEMEX_ITEMS

  constructor(server: MockServerInterface, args: BulkUpdateMemexItemsRequest, requestId: string) {
    super()
    this.#server = server
    this.#args = args
    this.#requestId = requestId
  }

  async perform() {
    let complete = 0

    for (const request of this.#args.memexProjectItems) {
      await this.#server.sleep(200)

      this.#server.memexItems.update({
        memexProjectItemId: request.id,
        layoutType: 'table',
        fieldIds: this.#args.fieldIds,
        ...request,
      })
      complete += 1

      this.#server.liveUpdate.sendSocketMessage({
        type: MemexPaginatedRefreshEvents.ProjectItemDenormalizedToElasticsearch,
      })

      this.#server.liveUpdate.sendBulkUpdateProgressSocketMessage({
        percentage: Math.round((complete / this.#args.memexProjectItems.length) * 100),
        requestId: this.#requestId,
      })
    }

    this.#server.liveUpdate.sendBulkUpdateCompleteSocketMessage({
      bulkUpdateSuccess: true,
      requestId: this.#requestId,
    })
  }
}
