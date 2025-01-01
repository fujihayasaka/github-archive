import {verifiedFetch} from '@github-ui/verified-fetch'
import {useState} from 'react'

type useDownloadConfigs = {
  endpoint: string
  filename: string
  onSuccess?: () => void
  onError?: () => void
}

export function useDownload(config: useDownloadConfigs) {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function download() {
    setLoading(true)

    const downloadPath = config.endpoint

    try {
      const response = await verifiedFetch(downloadPath, {
        method: 'GET',
        headers: {Accept: 'text/csv'},
      })

      if (response.ok) {
        const blob = await response.blob()
        const a = document.createElement('a')
        const href = URL.createObjectURL(blob)
        a.href = href
        a.download = config.filename
        a.click()
        a.remove()
        URL.revokeObjectURL(href)
        config.onSuccess?.()
      } else {
        const errMsg = `Download failed: ${response.statusText}`
        setError(errMsg)
        config.onError?.()
      }
    } catch {
      setError('Could not download. Try your request again.')
      config.onError?.()
    }

    setLoading(false)
  }

  return {loading, error, download}
}
