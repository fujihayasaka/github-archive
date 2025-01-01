import {Link} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {number as formatNumber} from '@github-ui/formatters'

type AlertsLimitReachedDialogProps = {
  setIsOpen: (isOpen: boolean) => void
  onProceed: () => void
  maxAlerts: number
  bestPracticeCampaignsDocsUrl: string
}

export const AlertsLimitReachedDialog = ({
  setIsOpen,
  onProceed,
  maxAlerts,
  bestPracticeCampaignsDocsUrl,
}: AlertsLimitReachedDialogProps) => {
  return (
    <Dialog
      title="This looks like a big campaign"
      onClose={() => setIsOpen(false)}
      width="large"
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: () => setIsOpen(false),
        },
        {
          buttonType: 'primary',
          content: 'Proceed',
          onClick: onProceed,
        },
      ]}
    >
      Campaigns can include up to {formatNumber(maxAlerts)} alerts. The current list of alerts exceeds the campaign
      limit, consider editing your filters to reduce the list of alerts.{' '}
      <Link inline href={bestPracticeCampaignsDocsUrl}>
        Learn more about optimizing security campaigns.
      </Link>
    </Dialog>
  )
}
