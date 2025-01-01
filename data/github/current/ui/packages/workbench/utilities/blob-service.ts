import {ApiCache} from '@github-ui/copilot-chat/utils/api-cache'
import {ERROR_MSG} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {FailedAPIResult, SuccessfulAPIResult} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {reactFetchJSON} from '@github-ui/verified-fetch'

import type {BlobPayload} from '../../workspace-editor/utilities/workspace-editor-types'
import {lightweightFileUrl} from '../utilities/urls'

export class BlobService {
  private blobCache = new ApiCache(this.fetchBlob)

  private async fetchBlob(filePath: string, sparkId: string) {
    try {
      const fileUrl = lightweightFileUrl({
        sparkId,
        path: filePath,
      })

      const response = await reactFetchJSON(fileUrl, {
        method: 'GET',
      })
      if (response.ok) {
        const payload = (await response.json()) as BlobPayload
        return {status: response.status, ok: true, payload} as SuccessfulAPIResult<BlobPayload>
      }

      return {status: response.status, ok: false, error: ERROR_MSG} as FailedAPIResult
    } catch {
      return {status: 500, ok: false, error: ERROR_MSG} as FailedAPIResult
    }
  }

  /**
   * Fetch a file blob from the server with caching.
   */
  public async getBlob(filePath: string, sparkId: string) {
    return this.blobCache.get(filePath, sparkId)
  }
}
