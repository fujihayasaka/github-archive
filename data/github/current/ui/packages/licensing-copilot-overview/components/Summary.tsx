import {Stack} from '@primer/react'
import {CopilotIcon} from '@primer/octicons-react'
import type {Sku} from '@github-ui/licensing-common/copilot-types'
import {clsx} from 'clsx'
import styles from './Summary.module.css'

import {SummaryCard} from '@github-ui/licensing-common/components/SummaryCard'
import {CopilotUsageSummary} from '@github-ui/licensing-common/components/CopilotUsageSummary'
import {CopilotPaymentSummary} from '@github-ui/licensing-common/components/CopilotPaymentSummary'
import {SummaryHeaderButtons} from './SummaryHeaderButtons'
import {EnableCTA} from './EnableCTA'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'
import {Banner, InlineMessage} from '@primer/react/experimental'
import {useState} from 'react'

export interface SummaryProps {
  isCopilotEnabled: boolean
  copilotCanBeReenabled: boolean
  businessSlug: string
  copilotTocLink: string
  cfbHelpLink: string
  cfeHelpLink: string
  skus: Sku[]
  billingTermEndDate: string
  totalCost: number
}

export function Summary(props: SummaryProps) {
  const {isStafftools} = useNavigation()
  const [showCsvError, setShowCsvError] = useState(false)
  const handleErrorFromCsvExport = () => {
    setShowCsvError(true)
  }

  const [showEnablementError, setShowEnablementError] = useState(false)
  const handleEnablementError = () => {
    setShowEnablementError(true)
  }

  return (
    <>
      {showCsvError && (
        <Banner
          title="CSV Export Error"
          hideTitle
          variant="critical"
          onDismiss={() => setShowCsvError(false)}
          className="mb-3"
          data-testid="csv-download-error-banner"
        >
          {'An error occurred while exporting the CSV report.'}
        </Banner>
      )}
      {showEnablementError && (
        <Banner
          title="Copilot Enablement Error"
          hideTitle
          variant="critical"
          onDismiss={() => setShowEnablementError(false)}
          className="mb-3"
          data-testid="copilot-enablement-error-banner"
        >
          {'An error occurred while enabling Copilot for your enterprise account.'}
        </Banner>
      )}
      <SummaryCard
        headerIconComponent={CopilotIcon}
        title="Copilot"
        headerActions={
          <SummaryHeaderButtons
            onDownloadError={handleErrorFromCsvExport}
            onEnablementError={handleEnablementError}
            isStafftools={isStafftools}
            {...props}
          />
        }
      >
        {props.isCopilotEnabled ? (
          <Stack
            gap="spacious"
            padding="spacious"
            className={clsx(styles.stackResponsive)}
            align="stretch"
            data-testid="usage-payment-summary"
          >
            <CopilotUsageSummary skus={props.skus} headingLevel="h3" />
            <div className={clsx(styles.dividerResponsive)} />
            <CopilotPaymentSummary
              billingTermEndDate={props.billingTermEndDate}
              skus={props.skus}
              totalCost={props.totalCost}
              headingLevel="h3"
            />
          </Stack>
        ) : isStafftools ? (
          <div className="Box-body" data-testid="stafftools-copilot-disabled">
            Copilot is not enabled on this enterprise.
          </div>
        ) : (
          <EnableCTA {...props} />
        )}
        {props.copilotCanBeReenabled && (
          <InlineMessage size="medium" variant="warning" className="Box-footer pl-4">
            {'Copilot access has been disabled for the entire enterprise'}
          </InlineMessage>
        )}
      </SummaryCard>
    </>
  )
}
