// components
import {Button, Stack} from '@primer/react'
import {DownloadIcon, GlobeIcon} from '@primer/octicons-react'
import {EnterpriseCloudSummaryHeaderMenu} from './EnterpriseCloudSummaryHeaderMenu'
import {EnterpriseCloudUsageSummary} from '@github-ui/licensing-common/components/EnterpriseCloudUsageSummary'
import {ExportStatusBanner} from './ExportStatusBanner'
import {EnterpriseCloudPaymentSummary} from '@github-ui/licensing-common/components/EnterpriseCloudPaymentSummary'
import {ManageSeats} from '@github-ui/licensing-common/components/ManageSeats'
import {PendingPlanChange} from '@github-ui/licensing-common/components/PendingPlanChange'
import {SummaryCard} from '@github-ui/licensing-common/components/SummaryCard'
import {SummaryCardBanner} from '@github-ui/licensing-common/components/SummaryCardBanner'
import {InvoiceRenewalButton} from '@github-ui/licensing-common/components/InvoiceRenewalButton'
import {InvoiceRenewalLabel} from '@github-ui/licensing-common/components/InvoiceRenewalLabel'

// types/enums
import {Product} from '@github-ui/licensing-common/types/product'
import {ProductActivationState} from '@github-ui/licensing-common/types/product-activation-state'
import type {PaymentMethod} from '@github-ui/licensing-common/types/payment-method'
import type {TrialInfo} from '@github-ui/licensing-common/types/trial-info'
import {ExportJobState} from '../types/export-job-state'
import type {PendingCycleChange} from '@github-ui/licensing-common/types/pending-cycle-change'
import type {InvoiceLicenseInfo} from '@github-ui/licensing-common/types/invoice-license-info'

// styles/utils
import {ERRORS} from '@github-ui/licensing-common/helpers/constants'
import {trialDisclaimer} from '@github-ui/licensing-common/helpers/trial-disclaimer'
import {clsx} from 'clsx'
import styles from './EnterpriseCloudSummary.module.css'

// services
import {updateSeats} from '@github-ui/licensing-common/services/seats'
import {cancelPlanChange} from '../services/pending-plan-changes'

// hooks/contexts
import {useRef, useEffect, useState} from 'react'
import {useExportStatus} from '../hooks/use-export-status'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'

export interface EnterpriseCloudSummaryProps {
  billingTermEndDate: string
  canManageDetails: boolean
  canViewMembers: boolean
  currentPayment: string
  enterpriseLicensesBillable: number
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
  unitCost: string
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

  const {basePath, isStafftools} = useNavigation()
  const csvDownloadUrl = `${basePath}/people/export?use_licensing_settings=true`

  let activationState: ProductActivationState = ProductActivationState.Active
  if (props.trialInfo) {
    activationState = props.trialInfo?.isActive ? ProductActivationState.Trial : ProductActivationState.TrialExpired
  }

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

  // Focus the result banners when they appear
  const manageSeatsResultBannerRef = useFocusOnShow(manageSeatsResult)
  const errorBannerRef = useFocusOnShow(errorBannerMessage)
  const cancelPlanChangeResultBannerRef = useFocusOnShow(cancelPlanChangeResult)

  return (
    <SummaryCard
      productActivationState={activationState}
      headerIconComponent={GlobeIcon}
      title="Enterprise Cloud"
      headerLabels={
        props.invoiceLicenseInfo
          ? [
              <InvoiceRenewalLabel
                key={Product.GHEC}
                invoiceLicenseInfo={props.invoiceLicenseInfo}
                product={Product.GHEC}
              />,
            ]
          : undefined
      }
      headerActions={
        <>
          <Button
            leadingVisual={DownloadIcon}
            data-testid="download-csv-button"
            onClick={startExport}
            inactive={exportJobState === ExportJobState.Pending}
          >
            Download CSV report
          </Button>
          {!isStafftools && props.canManageDetails && (
            <Button as="a" href={`${basePath}/enterprise_licensing/ghec`} variant="default" data-testid="manage-button">
              Manage
            </Button>
          )}
          {props.invoiceLicenseInfo && (
            <InvoiceRenewalButton invoiceLicenseInfo={props.invoiceLicenseInfo} product={Product.GHEC} />
          )}
        </>
      }
      headerMenu={
        <EnterpriseCloudSummaryHeaderMenu
          isSelfServe={props.isSelfServe}
          isSelfServeBlocked={props.isSelfServeBlocked}
          isVolumeLicensed={props.isVolumeLicensed}
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
          role="status"
          aria-label={errorBannerMessage}
          ref={errorBannerRef}
          tabIndex={-1}
          data-testid="error-banner"
        />
      )}
      {manageSeatsResult && (
        <SummaryCardBanner
          description={manageSeatsResult}
          hideTitle
          onDismiss={dismissManageSeatsResult}
          title={manageSeatsResult}
          variant="success"
          role="status"
          aria-label={manageSeatsResult}
          ref={manageSeatsResultBannerRef}
          tabIndex={-1}
          data-testid="manage-seats-result-banner"
        />
      )}
      {cancelPlanChangeResult && (
        <SummaryCardBanner
          description={cancelPlanChangeResult}
          hideTitle
          onDismiss={dismissCancelPlanChangeResult}
          title={cancelPlanChangeResult}
          variant="success"
          role="status"
          aria-label={cancelPlanChangeResult}
          ref={cancelPlanChangeResultBannerRef}
          tabIndex={-1}
          data-testid="cancel-plan-change-result-banner"
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
        <>
          <Stack className={clsx(styles.stackResponsive)} gap="spacious" padding="spacious" align="stretch">
            <div className={clsx(styles.flexEqualPart)}>
              <EnterpriseCloudUsageSummary
                canViewMembers={props.canViewMembers}
                isTrial={!!props.trialInfo}
                isVolumeLicensed={props.isVolumeLicensed}
                enterpriseLicensesConsumed={props.enterpriseLicensesConsumed}
                enterpriseLicensesPurchased={enterpriseLicenseCount}
                vssLicensesConsumed={props.vssLicensesConsumed}
                vssLicensesPurchasedWithOverage={props.vssLicensesPurchasedWithOverage}
                isVssEnabled={props.isVssEnabled}
              />
            </div>
            <div className={clsx(styles.dividerResponsive)} />
            <div className={clsx(styles.flexEqualPart)}>
              <EnterpriseCloudPaymentSummary
                billingTermEndDate={props.billingTermEndDate}
                currentPayment={currentPayment}
                enterpriseLicensesBillable={props.enterpriseLicensesBillable}
                isMonthly={props.isMonthly}
                isTrial={!!props.trialInfo}
                isVolumeLicensed={props.isVolumeLicensed}
                isVssEnabled={props.isVssEnabled}
                unitCost={props.unitCost}
              />
            </div>
          </Stack>
        </>
      )}
      <Footer
        isManagingSeats={isManagingSeats}
        cancelPendingPlanChange={cancelPendingPlanChange}
        pendingCycleChange={pendingCycleChange}
        trialInfo={props.trialInfo}
      />
    </SummaryCard>
  )
}

interface FooterProps {
  isManagingSeats: boolean
  cancelPendingPlanChange: () => void
  pendingCycleChange: PendingCycleChange | null
  trialInfo?: TrialInfo
}
function Footer({isManagingSeats, cancelPendingPlanChange, pendingCycleChange, trialInfo}: FooterProps) {
  return (
    <>
      {!isManagingSeats && <>{trialInfo && <TrialFooter trialInfo={trialInfo} />}</>}
      {pendingCycleChange && (
        <div className="Box-footer py-2 px-3 flash-warn">
          <PendingPlanChange pendingChange={pendingCycleChange} onCancelConfirmed={cancelPendingPlanChange} />
        </div>
      )}
    </>
  )
}

function TrialFooter({trialInfo}: {trialInfo: TrialInfo}) {
  return (
    <div className="Box-footer f5 border-top">
      <span className="color-fg-muted" data-testid="ghe-summary-trial-footer">
        {trialDisclaimer(trialInfo)}
      </span>
    </div>
  )
}

// Focus the element when the trigger changes. Consider extracting this to a common hook if we need it in more places.
function useFocusOnShow(trigger: string | null | undefined | false): React.RefObject<HTMLDivElement> {
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (trigger && ref.current) {
      ref.current.focus()
    }
  }, [trigger])
  return ref
}
