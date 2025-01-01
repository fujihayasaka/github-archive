import {Spinner} from '@primer/react'
import {CheckIcon} from '@primer/octicons-react'
import {SummaryCardBanner} from '@github-ui/licensing-common/components/SummaryCardBanner'
import {ExportJobState} from '../types/export-job-state'
import {Banner} from '@primer/react/experimental'

interface ExportStatusBannerProps {
  exportJobState: ExportJobState
  onDismissClick: () => void
  emailNotificationMessage?: string
  showDownloadButtonOnReady?: boolean
  onDownloadButtonClick?: () => void
}
export function ExportStatusBanner({
  exportJobState,
  onDismissClick,
  emailNotificationMessage,
  showDownloadButtonOnReady,
  onDownloadButtonClick,
}: ExportStatusBannerProps) {
  if (exportJobState === ExportJobState.Inactive) {
    return null
  }

  const commonBannerProps = {
    hideTitle: true,
    onDismiss: onDismissClick,
  }

  if (exportJobState === ExportJobState.Error) {
    return (
      <SummaryCardBanner
        {...commonBannerProps}
        role="status"
        variant="critical"
        title="CSV report download status"
        description="The CSV report could not be generated. Please try again later."
        data-testid="export-status-banner-error"
      />
    )
  }

  if (exportJobState === ExportJobState.Pending) {
    return (
      <SummaryCardBanner
        {...commonBannerProps}
        role="status"
        variant="info"
        title="CSV report download status"
        description={emailNotificationMessage || 'The CSV report is being generated.'}
        secondaryAction={
          <div className="d-flex flex-row flex-items-center gap-1" data-testid="export-status-text-short">
            <Spinner size="small" data-testid="export-status-pending-spinner" />
            <div className="ml-1 color-fg-muted">Generating CSV</div>
          </div>
        }
        data-testid="export-status-banner-pending"
      />
    )
  }

  if (exportJobState === ExportJobState.Ready) {
    return (
      <SummaryCardBanner
        {...commonBannerProps}
        role="status"
        variant="success"
        title="CSV report download status"
        description="CSV report generation complete"
        secondaryAction={
          !showDownloadButtonOnReady && (
            <div className="d-flex flex-row flex-items-center gap-1" data-testid="export-status-text-short">
              <CheckIcon size={16} data-testid="export-status-ready-icon" />
              <div className="ml-1">Downloaded CSV</div>
            </div>
          )
        }
        primaryAction={
          showDownloadButtonOnReady && (
            <Banner.PrimaryAction onClick={onDownloadButtonClick}>Download CSV</Banner.PrimaryAction>
          )
        }
        data-testid="export-status-banner-ready"
      />
    )
  }
}
