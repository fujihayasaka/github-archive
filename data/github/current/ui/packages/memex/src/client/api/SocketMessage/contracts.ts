import type {BulkUpdateError} from '../memex-items/contracts'
import type {ProjectMigration} from '../project-migration/contracts'

export type SocketMessageData = {
  type: string
  actor: {id: number}
  /**
   * Payloads are not entirely defined yet, but will be similar to the following:
   */
  payload: {
    [x: string]: number
  }
  /**  An amount of ms to wait for replication lag, if any */
  wait?: number
  project_migration?: ProjectMigration
  bulkUpdateSuccess?: boolean
  bulkUpdateErrors?: Array<BulkUpdateError>
  bulkCopySuccess?: boolean
  invalidateQueryCache?: boolean
  requestId?: string
}

export type SocketMessageIssueData = {
  timestamp: number
  reason: string
  gid: string
  /**  An amount of ms to wait for replication lag, if any */
  wait?: number
}

export type UnvalidatedSocketMessageDetail = {
  data: unknown
}

export const paginatedRefreshEvent = 'memex_item_denormalized_to_elasticsearch'
export type PaginatedRefreshSocketMessageData = {
  type: typeof paginatedRefreshEvent
  // the timestamp is the point in time when the update which triggered this event was made
  timestamp?: number
  // the ID of the request that originated from the web client and led to this refresh
  request_id?: string
}

export const bulkUpdateProgressEvent = 'project_items_bulk_update_progress'
export type BulkUpdateProgressSocketMessageData = {
  type: typeof bulkUpdateProgressEvent
  actor: {id: number}
  percentage: number
  requestId?: string
}

export const bulkUpdateCompleteEvent = 'project_items_bulk_update_complete'
export type BulkUpdateCompleteSocketMessageData = {
  type: typeof bulkUpdateCompleteEvent
  actor: {id: number}
  bulkUpdateSuccess?: boolean
  bulkUpdateErrors?: Array<BulkUpdateError>
  invalidateQueryCache?: boolean
  requestId?: string
}
