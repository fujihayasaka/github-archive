import {Button} from '@primer/react'
import {FileIcon} from '@primer/octicons-react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useState} from 'react'
import {BannerPortal} from '../../BannerPortal'
import type {AppListing} from '@github-ui/marketplace-common'

export function ExportButton({app}: {app: AppListing}) {
  const [loading, setLoading] = useState(false)
  const [showBanner, setShowBanner] = useState(false)
  const [bannerMessage, setBannerMessage] = useState('')

  const handleError = () => {
    setBannerMessage('An error occurred while exporting the CSV.')
    setShowBanner(true)
  }

  const handleCsvExport = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setLoading(true)

    try {
      const response = await verifiedFetch(`/marketplace/${app.slug}/transparency_report_exports`, {
        method: 'POST',
        headers: {Accept: 'text/csv'},
      })

      if (response.ok) {
        const blob = await response.blob()

        // Download the file
        const a = document.createElement('a')
        const href = URL.createObjectURL(blob)
        a.href = href
        a.download = `${app.slug}-transparency-report.csv`
        a.click()
        a.remove()
        URL.revokeObjectURL(href)
      } else {
        handleError()
      }
    } catch {
      handleError()
    } finally {
      setLoading(false)
    }
  }

  return (
    <>
      {showBanner && <BannerPortal message={bannerMessage} variant="critical" onDismiss={() => setShowBanner(false)} />}
      <form onSubmit={handleCsvExport}>
        <Button loading={loading} disabled={loading} type="submit" leadingVisual={FileIcon}>
          Export CSV
        </Button>
      </form>
    </>
  )
}
