import {renderHook, act, waitFor} from '@testing-library/react'
import {useExportStatus} from '../use-export-status'
import {ExportJobState} from '../../types/export-job-state'
import {createExportJob, pollForExportJobCompletion} from '../../services/jobs'

jest.mock('../../services/jobs')

describe('useExportStatus', () => {
  const csvDownloadUrl = '/export'
  const jobUrl = '/job'
  const exportUrl = '/export'

  let assignSpy: typeof jest.fn

  beforeEach(() => {
    jest.clearAllMocks()

    // This is a workaround to mock window.location.assign to avoid actually navigating to the URL when running tests.
    // We can't just assign a new value to window.location.assign because it's a read-only property.
    // We need to delete the property and reassign it.
    // @ts-expect-error overriding window.location in test
    delete window.location
    assignSpy = jest.fn()
    window.location = {assign: assignSpy} as unknown as string & Location
  })

  test('initializes with the expected default state', () => {
    const {result} = renderHook(() => useExportStatus(csvDownloadUrl))

    expect(result.current.exportJobState).toBe(ExportJobState.Inactive)
  })

  describe('without email notification', () => {
    beforeEach(() => {
      const createExportJobMock = createExportJob as jest.Mock
      const pollForExportJobCompletionMock = pollForExportJobCompletion as jest.Mock

      createExportJobMock.mockResolvedValue({job_url: jobUrl, download_url: exportUrl})
      pollForExportJobCompletionMock.mockResolvedValue({})
    })

    test('when export job completes, auto-download happens', async () => {
      const {result} = renderHook(() => useExportStatus(csvDownloadUrl))

      act(() => {
        result.current.startExport()
      })

      expect(result.current.exportJobState).toBe(ExportJobState.Pending)

      await waitFor(() => {
        expect(result.current.exportJobState).toBe(ExportJobState.Ready)
      })

      expect(assignSpy).toHaveBeenCalledWith(exportUrl)
    })

    test('on createExportJob error, exportJobState is updated to Error', async () => {
      const createExportJobMock = createExportJob as jest.Mock
      createExportJobMock.mockRejectedValue(new Error('Error'))

      const {result} = renderHook(() => useExportStatus(csvDownloadUrl))

      act(() => {
        result.current.startExport()
      })

      await waitFor(() => {
        expect(result.current.exportJobState).toBe(ExportJobState.Error)
      })

      expect(createExportJobMock).toHaveBeenCalledWith(csvDownloadUrl, expect.any(AbortSignal))
    })

    test('on pollForExportJobCompletion error, exportJobState is updated to Error', async () => {
      const pollForExportJobCompletionMock = pollForExportJobCompletion as jest.Mock
      pollForExportJobCompletionMock.mockRejectedValue(new Error('Error'))

      const {result} = renderHook(() => useExportStatus(csvDownloadUrl))

      act(() => {
        result.current.startExport()
      })

      await waitFor(() => {
        expect(result.current.exportJobState).toBe(ExportJobState.Error)
      })

      expect(pollForExportJobCompletionMock).toHaveBeenCalledWith(jobUrl, expect.any(AbortSignal))
    })
  })
})
