// components
import {Button} from '@primer/react'
import {GlobeIcon} from '@primer/octicons-react'
import {InlineMessage} from '@primer/react/experimental'
import {EnterpriseCloudSummaryHeaderMenu} from './EnterpriseCloudSummaryHeaderMenu'
import {EnterpriseCloudSeatCount} from './EnterpriseCloudSeatCount'
import {ExportStatusBanner} from './ExportStatusBanner'
import {ManageSeats} from '@github-ui/licensing-common/components/ManageSeats'
import {PendingPlanChange} from '@github-ui/licensing-common/components/PendingPlanChange'
import {SummaryCard} from '@github-ui/licensing-common/components/SummaryCard'
import {SummaryCardBanner} from '@github-ui/licensing-common/components/SummaryCardBanner'

// types/enums
import {ProductActivationState} from '@github-ui/licensing-common/types/product-activation-state'
import type {PaymentMethod} from '@github-ui/licensing-common/types/payment-method'
import type {TrialInfo} from '../types/trial-info'
import {ExportJobState} from '../types/export-job-state'
import type {PendingCycleChange} from '@github-ui/licensing-common/types/pending-cycle-change'
import type {InvoiceLicenseInfo} from '../types/invoice-license-info'

// styles/utils
import {format} from 'date-fns'
import {ERRORS} from '@github-ui/licensing-common/helpers/constants'
import {clsx} from 'clsx'
import styles from './EnterpriseCloudSummary.module.css'

// services
import {updateSeats} from '@github-ui/licensing-common/services/seats'
import {cancelPlanChange} from '../services/pending-plan-changes'

// hooks/contexts
import {useState} from 'react'
import {useExportStatus} from '../hooks/use-export-status'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'

export interface EnterpriseCloudSummaryProps {
  billingTermEndDate: Date
  canViewMembers: boolean
  currentPayment: string
  enterpriseLicensesConsumed: number
  enterpriseLicensesPurchased: number
  invoiceLicenseInfo?: InvoiceLicenseInfo
  isManagingSeats?: boolean
  isMonthly: boolean
  isSelfServe: boolean
  isSelfServeBlocked: boolean
  isVolumeLicensed: boolean
  isVssEnabled: boolean
  paymentMethod: PaymentMethod
  pendingCycleChange?: PendingCycleChange
  trialInfo?: TrialInfo
  unitCost: number
  vssLicensesConsumed: number
  vssLicensesPurchasedWithOverage: number
}
export function EnterpriseCloudSummary(props: EnterpriseCloudSummaryProps) {
  const [cancelPlanChangeResult, setCancelPlanChangeResult] = useState<string | null>(null)
  const [currentPayment, setCurrentPayment] = useState<string>(props.currentPayment)
  const [enterpriseLicenseCount, setEnterpriseLicenseCount] = useState<number>(props.enterpriseLicensesPurchased)
  const [isManagingSeats, setIsManagingSeats] = useState<boolean>(props.isManagingSeats || false)
  const [manageSeatsResult, setManageSeatsResult] = useState<string | null>(null)
  const [errorBannerMessage, setErrorBannerMessage] = useState<string | null>(null)
  const [pendingCycleChange, setPendingCycleChange] = useState<PendingCycleChange | null>(
    props.pendingCycleChange ?? null,
  )

  const {basePath} = useNavigation()
  const csvDownloadUrl = `${basePath}/people/export?use_licensing_settings=true`

  let activationState: ProductActivationState = ProductActivationState.Active
  if (props.trialInfo) {
    activationState = props.trialInfo?.isActive ? ProductActivationState.Trial : ProductActivationState.TrialExpired
  }

  const paymentTermLabel = props.trialInfo
    ? props.isMonthly
      ? 'Estimated monthly payment'
      : 'Estimated yearly payment'
    : props.isMonthly
      ? 'Monthly payment'
      : 'Yearly payment'

  const {exportJobState, emailNotificationMessage, startExport, dismissExport, doDownload, autoDownloadExport} =
    useExportStatus(csvDownloadUrl)

  const beginManageSeats = () => {
    setIsManagingSeats(true)
  }
  const cancelManageSeats = () => {
    setIsManagingSeats(false)
  }
  const saveSeatChange = async (newSeats: number) => {
    setErrorBannerMessage(null)
    setManageSeatsResult(null)

    try {
      const seatsPath = `${basePath}/settings/billing`
      const {successMessage, newPayment, newSeatCount, newPendingCycleChange} = await updateSeats(seatsPath, newSeats)

      if (newSeatCount) {
        setEnterpriseLicenseCount(newSeatCount)
      }
      if (newPayment) {
        setCurrentPayment(newPayment)
      }
      if (newPendingCycleChange) {
        setPendingCycleChange(newPendingCycleChange)
      }

      setManageSeatsResult(successMessage)
      setIsManagingSeats(false)
    } catch (error) {
      setErrorBannerMessage(error instanceof Error ? error.message : ERRORS.UPDATE_SEATS_FAILED_REASON_UNKNOWN)
    }
  }
  const dismissManageSeatsResult = () => {
    setManageSeatsResult(null)
  }

  const cancelPendingPlanChange = async () => {
    setErrorBannerMessage(null)

    try {
      const {successMessage} = await cancelPlanChange(basePath)
      setCancelPlanChangeResult(successMessage)
      setPendingCycleChange(null)
    } catch (error) {
      setCancelPlanChangeResult(null)
      if (error instanceof Error) {
        if (error.message === 'There are no pending changes to update.') {
          // probably the pending change was already applied or cancelled; remove from view
          setPendingCycleChange(null)
        }
        setErrorBannerMessage(error.message)
      } else {
        setErrorBannerMessage(ERRORS.CANCEL_PLAN_CHANGE_FAILED_REASON_UNKNOWN)
      }
    }
  }
  const dismissCancelPlanChangeResult = () => {
    setCancelPlanChangeResult(null)
  }

  const dismissErrorMessage = () => {
    setErrorBannerMessage(null)
  }

  return (
    <SummaryCard
      productActivationState={activationState}
      headerIconComponent={GlobeIcon}
      title="Enterprise Cloud"
      headerMenu={
        <EnterpriseCloudSummaryHeaderMenu
          isCsvDownloadDisabled={exportJobState === ExportJobState.Pending}
          isSelfServe={props.isSelfServe}
          isSelfServeBlocked={props.isSelfServeBlocked}
          isVolumeLicensed={props.isVolumeLicensed}
          onDownloadCsvSelect={startExport}
          onManageSeatsSelect={beginManageSeats}
        />
      }
    >
      {errorBannerMessage && (
        <SummaryCardBanner
          description={errorBannerMessage}
          hideTitle
          onDismiss={dismissErrorMessage}
          title={errorBannerMessage}
          variant="critical"
        />
      )}
      {manageSeatsResult && (
        <SummaryCardBanner
          description={manageSeatsResult}
          hideTitle
          onDismiss={dismissManageSeatsResult}
          title={manageSeatsResult}
          variant="success"
        />
      )}
      {cancelPlanChangeResult && (
        <SummaryCardBanner
          description={cancelPlanChangeResult}
          hideTitle
          onDismiss={dismissCancelPlanChangeResult}
          title={cancelPlanChangeResult}
          variant="success"
        />
      )}
      {exportJobState !== ExportJobState.Inactive && (
        <ExportStatusBanner
          exportJobState={exportJobState}
          onDismissClick={dismissExport}
          emailNotificationMessage={emailNotificationMessage}
          showDownloadButtonOnReady={!autoDownloadExport}
          onDownloadButtonClick={doDownload}
        />
      )}
      {isManagingSeats ? (
        <ManageSeats
          analyticsEventCategory="enterprise_account_manage_seats"
          currentPrice={currentPayment}
          isMonthlyPlan={props.isMonthly}
          isTrial={!!props.trialInfo}
          onCancelClick={cancelManageSeats}
          onSaveClick={saveSeatChange}
          paymentMethod={props.paymentMethod}
          licensesPurchased={enterpriseLicenseCount}
          seatsConsumed={props.enterpriseLicensesConsumed}
          seatsPath="/settings/billing"
        />
      ) : (
        <div className={clsx('pt-4', 'px-4', 'pb-4', 'd-flex', 'flex-column')}>
          <div className={clsx('d-flex', 'flex-md-row', 'flex-column', styles.gap6)}>
            <div className="flex-1">
              <EnterpriseCloudSeatCount
                canViewMembers={props.canViewMembers}
                isTrial={!!props.trialInfo}
                isVolumeLicensed={props.isVolumeLicensed}
                enterpriseLicensesConsumed={props.enterpriseLicensesConsumed}
                enterpriseLicensesPurchased={enterpriseLicenseCount}
                vssLicensesConsumed={props.vssLicensesConsumed}
                vssLicensesPurchasedWithOverage={props.vssLicensesPurchasedWithOverage}
              />
            </div>
            <div className="flex-1">
              <div className="d-flex flex-column mb-3" data-testid="payment-info">
                <h3>{paymentTermLabel}</h3>
                <div className={clsx('f3', styles.lineHeightSpacious)}>{currentPayment}</div>
                <div className="text-small color-fg-muted">
                  Each billable license is {props.unitCost}, valid until{' '}
                  {format(props.billingTermEndDate, 'MMMM d, yyyy')}
                </div>
              </div>
            </div>
          </div>
          {props.invoiceLicenseInfo?.statusMessage && (
            <InlineMessage variant={props.invoiceLicenseInfo.statusMessage.variant} className="mt-4">
              {props.invoiceLicenseInfo.statusMessage.text}
            </InlineMessage>
          )}
        </div>
      )}
      <Footer
        billingTermEndDate={props.billingTermEndDate}
        invoiceLicenseInfo={props.invoiceLicenseInfo}
        isManagingSeats={isManagingSeats}
        isVolumeLicensed={props.isVolumeLicensed}
        cancelPendingPlanChange={cancelPendingPlanChange}
        pendingCycleChange={pendingCycleChange}
        trialInfo={props.trialInfo}
      />
    </SummaryCard>
  )
}

interface FooterProps {
  billingTermEndDate: Date
  invoiceLicenseInfo?: InvoiceLicenseInfo
  isManagingSeats: boolean
  isVolumeLicensed: boolean
  cancelPendingPlanChange: () => void
  pendingCycleChange: PendingCycleChange | null
  trialInfo?: TrialInfo
}
function Footer({
  billingTermEndDate,
  invoiceLicenseInfo,
  isManagingSeats,
  isVolumeLicensed,
  cancelPendingPlanChange,
  pendingCycleChange,
  trialInfo,
}: FooterProps) {
  const {isStafftools} = useNavigation()
  return (
    <>
      {!isManagingSeats && (
        <>
          {trialInfo ? (
            <TrialFooter trialInfo={trialInfo} />
          ) : invoiceLicenseInfo && !isStafftools ? (
            <InvoiceLicenseFooter invoiceLicenseInfo={invoiceLicenseInfo} />
          ) : (
            <ValidUntilFooter isVolumeLicensed={isVolumeLicensed} billingTermEndDate={billingTermEndDate} />
          )}
        </>
      )}
      {pendingCycleChange && (
        <div
          className={clsx('mt-3', 'py-2', 'px-3', 'flash-warn', styles.warnFooter, 'rounded-bottom-2', 'border-top')}
        >
          <PendingPlanChange pendingChange={pendingCycleChange} onCancelConfirmed={cancelPendingPlanChange} />
        </div>
      )}
    </>
  )
}

function ValidUntilFooter({
  isVolumeLicensed,
  billingTermEndDate,
}: {
  isVolumeLicensed: boolean
  billingTermEndDate: Date
}) {
  return (
    <div className={clsx('pt-3', 'px-4', 'pb-0', 'f6', 'border-top')}>
      <span className="color-fg-muted" data-testid="ghe-summary-active-footer">
        {isVolumeLicensed
          ? `Valid until ${format(billingTermEndDate, 'MMMM d, yyyy')} (includes support and updates).`
          : `Billing date on ${format(billingTermEndDate, 'MMMM d, yyyy')}.`}
      </span>
    </div>
  )
}

function TrialFooter({trialInfo}: {trialInfo: TrialInfo}) {
  return (
    <div className={clsx('pt-3', 'px-4', 'pb-0', 'f6', 'border-top')}>
      <span className="color-fg-muted" data-testid="ghe-summary-trial-footer">
        Trial {trialInfo.isActive ? 'ends' : 'ended'}
        {trialInfo.expirationDate && ` on ${format(trialInfo.expirationDate, 'MMMM d, yyyy')}.`}
      </span>
    </div>
  )
}

function InvoiceLicenseFooter({invoiceLicenseInfo}: {invoiceLicenseInfo: InvoiceLicenseInfo}) {
  const {basePath} = useNavigation()
  const invoiceRenewalUrl = `${basePath}/settings/billing/renew`
  const invoiceUpgradeUrl = `${basePath}/settings/billing/add_seats`
  const contactSales = invoiceLicenseInfo.statusMessage?.variant === 'critical'
  const renew = !contactSales && invoiceLicenseInfo.actionType === 'renewal'
  const upgrade = !contactSales && !renew && invoiceLicenseInfo.actionType === 'upgrade'

  if (contactSales || renew || upgrade) {
    return (
      <div
        className={clsx('pt-3', 'px-4', 'pb-0', 'f6', 'border-top')}
        data-testid="ghe-summary-invoice-license-footer"
      >
        {contactSales && (
          <Button as="a" href="/renewals-help">
            Contact sales
          </Button>
        )}
        {renew && (
          <Button as="a" variant="primary" href={invoiceRenewalUrl}>
            Renew Enterprise Cloud
          </Button>
        )}
        {upgrade && (
          <Button as="a" variant="primary" href={invoiceUpgradeUrl}>
            Add licenses
          </Button>
        )}
      </div>
    )
  }
}
