import {useCallback, useEffect, useRef, useState} from 'react'
import {ExportJobState} from '../types/export-job-state'
import {createExportJob, pollForExportJobCompletion} from '../services/jobs'
import type {ServerLicense} from '../types/server-licenses'

export function useExportStatus(csvDownloadUrl: string) {
  const [exportJobState, setExportJobState] = useState<ExportJobState>(ExportJobState.Inactive)
  const [readyExportUrl, setReadyExportUrl] = useState<string>('')
  const abortControllerRef = useRef<AbortController | null>(null)

  const doDownload = useCallback(() => {
    window.location.assign(readyExportUrl)
  }, [readyExportUrl])

  // clean up on unmount
  useEffect(() => {
    return () => {
      abortControllerRef.current?.abort()
    }
  }, [])

  // when export is ready, do the download
  useEffect(() => {
    if (exportJobState === ExportJobState.Ready && readyExportUrl) {
      doDownload()
    }
  }, [exportJobState, readyExportUrl, doDownload])

  const startExport = async (): Promise<{license: ServerLicense} | undefined> => {
    // abort any pending export
    abortControllerRef.current?.abort()

    abortControllerRef.current = new AbortController()
    const signal = abortControllerRef.current.signal

    setExportJobState(ExportJobState.Pending)

    try {
      const {job_url: jobUrl, download_url: downloadUrl, license} = await createExportJob(csvDownloadUrl, signal)

      await pollForExportJobCompletion(jobUrl, signal)

      setReadyExportUrl(downloadUrl)
      setExportJobState(ExportJobState.Ready)

      return {license}
    } catch (error) {
      if ((error as Error).name !== 'AbortError') {
        // ignore abort errors
        setExportJobState(ExportJobState.Error)
      }
    }
  }

  const dismissExport = () => {
    abortControllerRef.current?.abort()
    setExportJobState(ExportJobState.Inactive)
  }

  return {
    exportJobState,
    startExport,
    dismissExport,
    doDownload,
  }
}
