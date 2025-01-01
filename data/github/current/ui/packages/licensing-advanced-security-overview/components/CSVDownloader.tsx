import {DownloadIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button} from '@primer/react'
import {useMemo} from 'react'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'
import type {Sku} from '../types/sku'

export interface CSVDownloaderProps {
  skus: Sku[]
}

export function CSVDownloader({skus}: CSVDownloaderProps) {
  const {basePath, isStafftools, isTeams, slug} = useNavigation()

  const csvDownloadUrl = useMemo(() => {
    if (isTeams) {
      return `/organizations/${slug}/download_active_committers`
    } else if (isStafftools) {
      return `${basePath}/advanced_security/download_active_committers`
    } else {
      return `${basePath}/enterprise_licensing/download_active_committers`
    }
  }, [basePath, isStafftools, isTeams, slug])

  if (skus.length === 0) {
    return null
  }

  if (skus.length === 1) {
    return (
      <Button as="a" href={csvDownloadUrl} data-testid="csv-downloader-button">
        <DownloadIcon size={16} className="mr-1" aria-hidden="true" />
        Download CSV report
      </Button>
    )
  }

  return (
    <ActionMenu data-testid="csv-downloader-menu">
      <ActionMenu.Button aria-label="Download CSV report" leadingVisual={DownloadIcon}>
        Download CSV report
      </ActionMenu.Button>
      <ActionMenu.Overlay width="auto">
        <ActionList>
          {skus.map(sku => (
            <ActionList.LinkItem
              key={sku.sku}
              as="a"
              href={`${csvDownloadUrl}?sku=${sku.sku}`}
              data-testid={`csv-download-${sku.sku}`}
            >
              {sku.name}
            </ActionList.LinkItem>
          ))}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
