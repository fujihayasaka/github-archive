import type {FailedAPIResult, SuccessfulAPIResult} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {mockFetch} from '@github-ui/mock-fetch'

import {BlobService} from '../blob-service'
import type {BlobPayload} from '../workspace-editor-types'

describe('blob service', () => {
  test('returns and caches blob data', async () => {
    const mockBlobData = {
      blobContents: 'hello world',
      commitOid: 'abc123',
      refName: 'main',
    }

    const mockedFetchCall = mockFetch.mockRouteOnce(
      '/owner/repo/pull/1/workspace_editor/files/abc123/README.md',
      mockBlobData,
    )

    const blobService = new BlobService()
    const blobData = await blobService.getBlob('README.md', 'owner', '1', 'repo', 'abc123')
    expect(blobData.ok).toBeTruthy()
    expect((blobData as SuccessfulAPIResult<BlobPayload>).payload).toEqual(mockBlobData)

    const cachedBlobData = await blobService.getBlob('README.md', 'owner', '1', 'repo', 'abc123')
    expect(cachedBlobData.ok).toBeTruthy()
    expect((cachedBlobData as SuccessfulAPIResult<BlobPayload>).payload).toEqual(mockBlobData)
    expect(mockedFetchCall).toHaveBeenCalledTimes(1)
  })

  test('refetches for new commitOid', async () => {
    const mockBlobData = {
      blobContents: 'hello world',
      commitOid: 'abc123',
      refName: 'main',
    }

    const firstMockedFetch = mockFetch.mockRouteOnce(
      '/owner/repo/pull/1/workspace_editor/files/abc123/README.md',
      mockBlobData,
    )
    const secondMockedFetch = mockFetch.mockRouteOnce(
      '/owner/repo/pull/1/workspace_editor/files/def345/README.md',
      mockBlobData,
    )

    const blobService = new BlobService()
    const blobData = await blobService.getBlob('README.md', 'owner', '1', 'repo', 'abc123')
    expect(blobData.ok).toBeTruthy()
    expect((blobData as SuccessfulAPIResult<BlobPayload>).payload).toEqual(mockBlobData)

    const newBlobData = await blobService.getBlob('README.md', 'owner', '1', 'repo', 'def345')
    expect(newBlobData.ok).toBeTruthy()
    expect((newBlobData as SuccessfulAPIResult<BlobPayload>).payload).toEqual(mockBlobData)

    expect(firstMockedFetch).toHaveBeenCalledTimes(1)
    expect(secondMockedFetch).toHaveBeenCalledTimes(1)
  })

  test('returns error if fetch fails', async () => {
    mockFetch.mockRouteOnce('/owner/repo/pull/1/workspace_editor/files/abc123/README.md', undefined, {
      ok: false,
      status: 500,
    })

    const blobService = new BlobService()
    const blobData = await blobService.getBlob('README.md', 'owner', '1', 'repo', 'abc123')
    expect(blobData.ok).toBeFalsy()
    expect((blobData as FailedAPIResult).error).toBe("I'm sorry but there was an error. Please try again.")
  })
})
