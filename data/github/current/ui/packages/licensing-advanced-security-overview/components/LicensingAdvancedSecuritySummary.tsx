import {ShieldCheckIcon} from '@primer/octicons-react'
import {Stack, useResponsiveValue} from '@primer/react'
import {clsx} from 'clsx'
import styles from './LicensingAdvancedSecuritySummary.module.css'
import type {Sku} from '../utils'

import {SummaryCard} from '@github-ui/licensing-common/components/SummaryCard'
import {LicenseUsageSummary} from './LicenseUsageSummary'
import {PaymentSummary} from './PaymentSummary'
import {AdvancedSecuritySummaryHeaderMenu} from './AdvancedSecuritySummaryHeaderMenu'
import {useMemo, useState} from 'react'
import type {PaymentMethod} from '@github-ui/licensing-common/types/payment-method'
import {ManageSeats} from '@github-ui/licensing-common/components/ManageSeats'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'
import {ERRORS} from '@github-ui/licensing-common/helpers/constants'
import {updateSeats} from '@github-ui/licensing-common/services/seats'
import {CancelSubscriptionDialog} from './CancelSubscriptionDialog'
import {cancelPendingSubscriptionChange, cancelSubscription} from '../services/subscriptions'
import type {PendingCycleChange} from '@github-ui/licensing-common/types/pending-cycle-change'
import {PendingPlanChange} from '@github-ui/licensing-common/components/PendingPlanChange'
import {useClickAnalytics} from '@github-ui/use-analytics'
import {Banner, InlineMessage} from '@primer/react/experimental'
import type {InvoiceLicenseInfo} from '@github-ui/licensing-common/types/invoice-license-info'
import {InvoiceRenewalButton} from '@github-ui/licensing-common/components/InvoiceRenewalButton'
import {Product} from '@github-ui/licensing-common/types/product'
import {InvoiceRenewalLabel} from '@github-ui/licensing-common/components/InvoiceRenewalLabel'

export interface SelfServeSubscriptionInfo {
  expiration: string
  pendingCycleChange?: PendingCycleChange
}
export interface LicensingAdvancedSecuritySummaryProps {
  billingCycle: string
  billableLicenses: number
  billingTermEndDate: string
  currentPayment: string
  invoiceLicenseInfo?: InvoiceLicenseInfo
  isAdvancedSecurityEnabled: boolean
  isBundled: boolean
  isManagingSeats: boolean
  isMeteredLicensed: boolean
  isSelfServeAdvancedSecurity: boolean
  paymentMethod: PaymentMethod
  selfServeSubscriptionInfo?: SelfServeSubscriptionInfo
  skus: Sku[]
  unlimitedLicense: boolean
}

export function LicensingAdvancedSecuritySummary(props: LicensingAdvancedSecuritySummaryProps) {
  const isMobile = useResponsiveValue({narrow: true}, false) as boolean
  const [billableLicenses, setBillableLicenses] = useState<number>(props.billableLicenses)
  const [currentPayment, setCurrentPayment] = useState<string>(props.currentPayment)
  const [errorBannerMessage, setErrorBannerMessage] = useState<string | null>(null)
  const [successBannerMessage, setSuccessBannerMessage] = useState<string | null>(null)
  const [infoBannerMessage, setInfoBannerMessage] = useState<string | null>(null)
  const [isCancelingSubscription, setIsCancelingSubscription] = useState<boolean>(false)
  const [showCancelSubscriptionDialog, setShowCancelSubscriptionDialog] = useState<boolean>(false)
  const [isManagingSeats, setIsManagingSeats] = useState<boolean>(props.isManagingSeats || false)
  const [pendingCycleChange, setPendingCycleChange] = useState<PendingCycleChange | null>(
    props.selfServeSubscriptionInfo?.pendingCycleChange ?? null,
  )
  const [skus, setSkus] = useState<Sku[]>(props.skus)

  const {basePath} = useNavigation()
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const bundledSku = useMemo(() => {
    return skus.find(sku => sku.sku === 'bundled')
  }, [skus])

  const beginManageSeats = () => {
    setIsManagingSeats(true)
  }
  const cancelManageSeats = () => {
    setIsManagingSeats(false)
  }
  const saveSeatChange = async (newSeats: number) => {
    setErrorBannerMessage(null)
    setSuccessBannerMessage(null)

    try {
      const seatsPath = `${basePath}/settings/billing/advanced_security`
      const {successMessage, newPayment, newPendingCycleChange, newSeatCount} = await updateSeats(seatsPath, newSeats)

      if (newSeatCount) {
        setSkus(
          skus.map(sku => {
            if (sku.sku === 'bundled') {
              return {
                ...sku,
                purchasedLicenses: newSeatCount,
              }
            }
            return sku
          }),
        )
        setBillableLicenses(newSeatCount)
      }
      if (newPayment) {
        setCurrentPayment(newPayment)
      }
      if (newPendingCycleChange) {
        setPendingCycleChange(newPendingCycleChange)
      }

      setSuccessBannerMessage(successMessage)
      setIsManagingSeats(false)
    } catch (error) {
      setErrorBannerMessage(error instanceof Error ? error.message : ERRORS.UPDATE_SEATS_FAILED_REASON_UNKNOWN)
    }
  }

  const dismissSuccessMessage = () => {
    setSuccessBannerMessage(null)
  }

  const dismissErrorMessage = () => {
    setErrorBannerMessage(null)
  }

  const dismissInfoMessage = () => {
    setInfoBannerMessage(null)
  }

  const cancelSelfServeSubscription = async () => {
    setErrorBannerMessage(null)
    setIsCancelingSubscription(true)
    try {
      const {successMessage, newPendingCycleChange} = await cancelSubscription(basePath)
      setSuccessBannerMessage(successMessage)
      if (newPendingCycleChange) {
        setPendingCycleChange(newPendingCycleChange)
      }
    } catch (error) {
      setErrorBannerMessage(
        error instanceof Error ? error.message : 'Sorry, we were unable to cancel your subscription.',
      )
    } finally {
      setIsCancelingSubscription(false)
      setShowCancelSubscriptionDialog(false)
    }
  }

  const cancelPendingPlanChange = async () => {
    if (!pendingCycleChange?.id) return
    setErrorBannerMessage(null)

    sendClickAnalyticsEvent({
      action: pendingCycleChange.isCancellation
        ? 'click_to_cancel_pending_cancellation'
        : 'click_to_cancel_pending_change',
      category: 'business_advanced_security_subscription',
      label: `ref_page:${basePath}/enterprise_licensing;ref_cta:cancel;ref_loc:enterprise_licensing`,
    })

    try {
      const {successMessage} = await cancelPendingSubscriptionChange(pendingCycleChange.id)
      setInfoBannerMessage(successMessage)
      setPendingCycleChange(null)
    } catch (error) {
      setErrorBannerMessage(
        error instanceof Error ? error.message : 'Sorry, we were unable to cancel your pending plan change.',
      )
    }
  }

  if (!props.isAdvancedSecurityEnabled) {
    return null
  }
  return (
    <SummaryCard
      headerIconComponent={ShieldCheckIcon}
      title="Advanced Security"
      headerLabels={
        props.invoiceLicenseInfo
          ? [
              <InvoiceRenewalLabel
                key={Product.GHAS}
                invoiceLicenseInfo={props.invoiceLicenseInfo}
                product={Product.GHAS}
              />,
            ]
          : undefined
      }
      headerMenu={
        <>
          {props.invoiceLicenseInfo && (
            <InvoiceRenewalButton invoiceLicenseInfo={props.invoiceLicenseInfo} product={Product.GHAS} />
          )}
          {props.isSelfServeAdvancedSecurity && (
            <AdvancedSecuritySummaryHeaderMenu
              onCancelSubscriptionSelect={() => setShowCancelSubscriptionDialog(true)}
              onManageSeatsSelect={beginManageSeats}
            />
          )}
        </>
      }
    >
      {errorBannerMessage && (
        <Banner
          description={errorBannerMessage}
          hideTitle
          onDismiss={dismissErrorMessage}
          variant="critical"
          title="Error"
        />
      )}
      {successBannerMessage && (
        <Banner
          description={successBannerMessage}
          hideTitle
          onDismiss={dismissSuccessMessage}
          title="Success"
          variant="success"
        />
      )}
      {infoBannerMessage && (
        <Banner description={infoBannerMessage} hideTitle onDismiss={dismissInfoMessage} title="Info" variant="info" />
      )}
      {isManagingSeats && props.isBundled ? (
        <ManageSeats
          analyticsEventCategory="business_advanced_security_subscription"
          analyticsRefPage={`${basePath}/enterprise_licensing`}
          currentPrice={currentPayment}
          isMonthlyPlan={props.billingCycle === 'Monthly'}
          isTrial={false}
          licensesPurchased={bundledSku?.purchasedLicenses || 0}
          onCancelClick={cancelManageSeats}
          onSaveClick={saveSeatChange}
          paymentMethod={props.paymentMethod}
          seatsConsumed={bundledSku?.consumedLicenses || 0}
          seatsPath="/settings/billing/advanced_security"
        />
      ) : (
        <Stack direction={isMobile ? 'vertical' : 'horizontal'} gap="spacious" padding="spacious" align="stretch">
          <LicenseUsageSummary
            isVolumeLicensed={!props.isMeteredLicensed}
            skus={skus}
            unlimitedLicense={props.unlimitedLicense}
          />
          <div className={clsx({[styles.dividerRight]: !isMobile, [styles.dividerBottom]: isMobile})} />
          <PaymentSummary
            billingCycle={props.billingCycle}
            billableLicenses={billableLicenses}
            billingTermEndDate={props.billingTermEndDate}
            currentPayment={currentPayment}
            isBundled={props.isBundled}
            isMeteredLicensed={props.isMeteredLicensed}
            skus={skus}
          />
        </Stack>
      )}
      {showCancelSubscriptionDialog && props.selfServeSubscriptionInfo && (
        <CancelSubscriptionDialog
          expiration={props.selfServeSubscriptionInfo.expiration}
          isCanceling={isCancelingSubscription}
          onClose={() => setShowCancelSubscriptionDialog(false)}
          onConfirmed={cancelSelfServeSubscription}
        />
      )}
      {props.invoiceLicenseInfo?.statusMessage && (
        <InlineMessage variant={props.invoiceLicenseInfo.statusMessage.variant} className="px-4">
          {props.invoiceLicenseInfo.statusMessage.text}
        </InlineMessage>
      )}
      {pendingCycleChange && (
        <div
          className={clsx('mt-3', 'py-2', 'px-3', 'flash-warn', styles.warnFooter, 'rounded-bottom-2', 'border-top')}
        >
          <PendingPlanChange onCancelConfirmed={cancelPendingPlanChange} pendingChange={pendingCycleChange} />
        </div>
      )}
    </SummaryCard>
  )
}
