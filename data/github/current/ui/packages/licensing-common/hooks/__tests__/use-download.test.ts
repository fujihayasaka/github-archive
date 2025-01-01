import {act, renderHook, waitFor} from '@testing-library/react'
import {useDownload} from '../use-download'
import {verifiedFetch} from '@github-ui/verified-fetch'

const mockVerifiedFetch = verifiedFetch as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

describe('useDownload', () => {
  const slug = 'github-inc'
  const endpoint = '/my-endpoint/'
  const filename = `${slug}-seat-usage.csv`

  test('initializes with the expected default state', () => {
    const {result} = renderHook(() => useDownload({endpoint, filename}))

    expect(result.current.loading).toBe(false)
    expect(result.current.error).toBe(null)
  })

  test('sets loading to true while download is happening, and sets it back to false when download is complete', async () => {
    mockVerifiedFetch.mockResolvedValue({ok: true})

    const {result} = renderHook(() => useDownload({endpoint, filename}))

    act(() => {
      result.current.download()
    })

    await waitFor(() => {
      expect(result.current.loading).toBe(true)
    })

    expect(mockVerifiedFetch).toHaveBeenCalledWith(endpoint, {
      method: 'GET',
      headers: {Accept: 'text/csv'},
    })

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
    })
  })

  test('sets loading to true while download is happening, sets it back to false when download is complete, and runs custom success handling logic, if specified', async () => {
    const mockBlob = jest.fn().mockResolvedValue(new Blob(['test']))
    mockVerifiedFetch.mockResolvedValue({
      ok: true,
      blob: mockBlob,
    })
    const handleSuccess = jest.fn()
    global.URL.createObjectURL = jest.fn().mockReturnValue('test')
    global.URL.revokeObjectURL = jest.fn()

    const {result} = renderHook(() => useDownload({endpoint, filename, onSuccess: handleSuccess}))

    act(() => {
      result.current.download()
    })

    await waitFor(() => {
      expect(result.current.loading).toBe(true)
    })

    expect(mockVerifiedFetch).toHaveBeenCalledWith(endpoint, {
      method: 'GET',
      headers: {Accept: 'text/csv'},
    })

    await waitFor(() => {
      expect(mockBlob).toHaveBeenCalled()
    })

    await waitFor(() => {
      expect(handleSuccess).toHaveBeenCalledTimes(1)
    })

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
    })
  })

  test('if request fails, sets an error message specifying the response status, and resets loading to false', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: false,
      statusText: 'BAD REQUEST',
      status: 400,
    })

    const {result} = renderHook(() => useDownload({endpoint, filename}))

    act(() => {
      result.current.download()
    })

    await waitFor(() => {
      expect(result.current.loading).toBe(true)
    })

    expect(mockVerifiedFetch).toHaveBeenCalledWith(endpoint, {
      method: 'GET',
      headers: {Accept: 'text/csv'},
    })

    await waitFor(() => {
      expect(result.current.error).toBe('Download failed: BAD REQUEST')
    })

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
    })
  })

  test('if request fails and custom error logic has been specified, runs the error logic and resets loading to false', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: false,
      statusText: 'BAD REQUEST',
      status: 400,
    })

    const handleError = jest.fn()

    const {result} = renderHook(() => useDownload({endpoint, filename, onError: handleError}))

    act(() => {
      result.current.download()
    })

    await waitFor(() => {
      expect(result.current.loading).toBe(true)
    })

    expect(mockVerifiedFetch).toHaveBeenCalledWith(endpoint, {
      method: 'GET',
      headers: {Accept: 'text/csv'},
    })

    await waitFor(() => {
      expect(handleError).toHaveBeenCalledTimes(1)
    })

    await waitFor(() => {
      expect(result.current.error).toBe('Download failed: BAD REQUEST')
    })

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
    })
  })

  test('if request throws an error, catches the error and runs the custom error logic, if specified', async () => {
    mockVerifiedFetch.mockRejectedValue(new Error('boom!'))

    const handleError = jest.fn()

    const {result} = renderHook(() => useDownload({endpoint, filename, onError: handleError}))

    act(() => {
      result.current.download()
    })

    await waitFor(() => {
      expect(result.current.loading).toBe(true)
    })

    expect(mockVerifiedFetch).toHaveBeenCalledWith(endpoint, {
      method: 'GET',
      headers: {Accept: 'text/csv'},
    })

    await waitFor(() => {
      expect(handleError).toHaveBeenCalledTimes(1)
    })

    await waitFor(() => {
      expect(result.current.error).toBe('Could not download. Try your request again.')
    })

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
    })
  })
})
