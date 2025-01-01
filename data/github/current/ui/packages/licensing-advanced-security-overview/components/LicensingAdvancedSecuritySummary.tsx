import {ShieldCheckIcon} from '@primer/octicons-react'
import {Stack, Button} from '@primer/react'
import {clsx} from 'clsx'
import {useMemo, useState} from 'react'

import styles from './LicensingAdvancedSecuritySummary.module.css'
import type {Sku} from '../types/sku'

import {format, parseISO} from 'date-fns'
import {SummaryCard} from '@github-ui/licensing-common/components/SummaryCard'
import {UsageSummary} from '@github-ui/licensing-common/components/UsageSummary'
import {PaymentSummary} from '@github-ui/licensing-common/components/PaymentSummary'
import {UsageHint} from '@github-ui/licensing-common/components/UsageHint'
import {LicenseUsageSummaryItem} from './LicenseUsageSummaryItem'
import {pluralize} from '@github-ui/licensing-common/helpers/pluralize'
import {AdvancedSecuritySummaryHeaderActions} from './AdvancedSecuritySummaryHeaderActions'
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
import {SummaryCardBanner} from '@github-ui/licensing-common/components/SummaryCardBanner'
import {InlineMessage} from '@primer/react/experimental'
import type {InvoiceLicenseInfo} from '@github-ui/licensing-common/types/invoice-license-info'
import {Product} from '@github-ui/licensing-common/types/product'
import {InvoiceRenewalLabel} from '@github-ui/licensing-common/components/InvoiceRenewalLabel'
import type {TrialInfo} from '@github-ui/licensing-common/types/trial-info'
import {ProductActivationState} from '@github-ui/licensing-common/types/product-activation-state'

import type {ServerLicensesInfo, LicenseCountPart} from './ServerLicensesFooter'
import {ServerLicensesFooter} from './ServerLicensesFooter'

import {trialDisclaimer} from '@github-ui/licensing-common/helpers/trial-disclaimer'
import {AdvancedSecurityFeatures} from './AdvancedSecurityFeatures'
import type {TradeScreeningResult} from '../types/trade-screening'
import {StartTrialDialog} from './StartTrialDialog'
import {startTrial} from '../services/trials'
import type {SelfServeTrialInfo} from '../types/self-serve-trial-info'
import {AdvancedSecuritySummaryHeaderMenu} from './AdvancedSecuritySummaryHeaderMenu'

export interface SelfServeSubscriptionInfo {
  expiration: string
  pendingCycleChange?: PendingCycleChange
}

export interface LicensingAdvancedSecuritySummaryProps {
  billingCycle: string
  billableLicenses: number
  billingTermEndDate: string
  buyButtonPath: string
  configureButtonPath: string
  ghasFeaturesUrl: string
  currentPayment: string
  eligibleForTrial: boolean
  invoiceLicenseInfo?: InvoiceLicenseInfo
  isAdvancedSecurityEnabled: boolean
  isBundled: boolean
  isManagingSeats: boolean
  isMeteredLicensed: boolean
  isSelfServeAdvancedSecurity: boolean
  paymentMethod: PaymentMethod
  selfServeSubscriptionInfo?: SelfServeSubscriptionInfo
  selfServeTrialInfo?: SelfServeTrialInfo
  skus: Sku[]
  tradeScreeningResult?: TradeScreeningResult
  trialInfo?: TrialInfo
  unlimitedLicense: boolean
  usageExceededMessage?: string
  usageAtCapacityMessage?: string
}

export function LicensingAdvancedSecuritySummary(props: LicensingAdvancedSecuritySummaryProps) {
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
  const [showStartTrialDialog, setShowStartTrialDialog] = useState<boolean>(false)
  const [isStartingTrial, setIsStartingTrial] = useState<boolean>(false)
  const [skus, setSkus] = useState<Sku[]>(props.skus)
  const {basePath, isTeams, isStafftools} = useNavigation()
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const bundledSku = useMemo(() => {
    return skus.find(sku => sku.sku === 'bundled')
  }, [skus])

  const unbundledSkus = useMemo(() => {
    return skus.filter(sku => sku.sku !== 'bundled')
  }, [skus])

  // Return early if the user is not eligible for a trial and the UI is not enabled
  if (!props.isAdvancedSecurityEnabled && !props.eligibleForTrial && !props.trialInfo) {
    return null
  }

  const paymentSummaryTitle = props.isMeteredLicensed ? 'Estimated next payment' : `${props.billingCycle} payment`
  const paymentSummaryDescription = () => {
    const licenseCount = pluralize(billableLicenses, 'license', false)
    if (props.isMeteredLicensed) {
      return `Amount based on ${billableLicenses.toLocaleString()} billable ${licenseCount}, due by ${format(
        parseISO(props.billingTermEndDate),
        'MMMM d, yyyy',
      )}.`
    }
    return `Amount based on ${billableLicenses.toLocaleString()} purchased ${licenseCount}.`
  }
  const formatSkuLabel = (sku: Sku): string => {
    const count = sku.billableLicenses.toLocaleString()
    const suffix = pluralize(sku.billableLicenses, 'license', false)
    const name = sku.name

    return `${count} ${name} ${suffix}`
  }
  const usageDetailsHref = `${basePath}/billing/usage?group=2&query=product:ghas`

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

  const dismissStartFreeTrialDialog = () => {
    setShowStartTrialDialog(false)
    setIsStartingTrial(false)
  }

  const getServerLicensesInfo = (): ServerLicensesInfo | undefined => {
    if (props.isMeteredLicensed || props.skus.length === 0) {
      return undefined
    }

    const parts: LicenseCountPart[] = []
    const prefix = 'Additional users from GitHub Connect: '

    if (props.isBundled) {
      if (bundledSku && bundledSku.serverOnlyConsumedLicenses > 0) {
        parts.push({
          count: bundledSku.serverOnlyConsumedLicenses,
          suffix: ` for Advanced Security`,
        })
        return {
          prefix,
          parts,
        }
      }
      return undefined
    }

    const totalServerOnlyLicenses = props.skus.reduce((total, sku) => total + sku.serverOnlyConsumedLicenses, 0)

    if (totalServerOnlyLicenses === 0) {
      return undefined
    }

    for (const sku of unbundledSkus) {
      if (sku.serverOnlyConsumedLicenses > 0) {
        parts.push({
          count: sku.serverOnlyConsumedLicenses,
          suffix: ` for ${sku.name}`,
        })
      }
    }

    if (parts.length > 0) {
      return {
        prefix,
        parts,
      }
    }

    return undefined
  }

  const startFreeTrial = async () => {
    if (!props.selfServeTrialInfo) return
    sendClickAnalyticsEvent({
      category: 'advanced_security_self_serve_trial',
      action: 'click_start_free_trial',
      label: 'ref_cta:start_free_trial;ref_loc:enterprise_licensing',
    })
    setIsStartingTrial(true)
    try {
      await startTrial(basePath)
      window.location.href = props.selfServeTrialInfo.organizationToOnboard
        ? `/orgs/${props.selfServeTrialInfo.organizationToOnboard}/organization_onboarding/advanced_security`
        : `${basePath}/enterprise_licensing`
    } catch (error) {
      setErrorBannerMessage(error instanceof Error ? error.message : 'Sorry, we were unable to start your free trial.')
    } finally {
      dismissStartFreeTrialDialog()
    }
  }

  let activationState: ProductActivationState = ProductActivationState.Active
  if (props.trialInfo) {
    activationState = props.trialInfo?.isActive ? ProductActivationState.Trial : ProductActivationState.TrialExpired
  }

  const usageSummaryDescription =
    'Active committers who contributed to at least one private organization-owned or user-owned repository.'
  const totalConsumed = skus.reduce((total, s) => total + s.consumedLicenses, 0)
  const totalBillable = skus.reduce((total, s) => total + s.billableLicenses, 0)

  const teamsUsage = totalConsumed !== 0 || totalBillable !== 0

  return (
    <SummaryCard
      productActivationState={activationState}
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
      headerActions={
        <AdvancedSecuritySummaryHeaderActions
          buyButtonPath={props.buyButtonPath}
          teamsUsage={teamsUsage}
          configureButtonPath={props.configureButtonPath}
          trialInfo={props.trialInfo}
          selfServeTrialInfo={props.selfServeTrialInfo}
          invoiceLicenseInfo={props.invoiceLicenseInfo}
          skus={props.skus}
          isTeams={isTeams}
          isStafftools={isStafftools}
          eligibleForTrial={props.eligibleForTrial}
          onFreeTrialClick={() => setShowStartTrialDialog(true)}
        />
      }
      headerMenu={
        <AdvancedSecuritySummaryHeaderMenu
          eligibleForTrial={props.eligibleForTrial}
          isSelfServeAdvancedSecurity={props.isSelfServeAdvancedSecurity}
          invoiceLicenseInfo={props.invoiceLicenseInfo}
          isTeams={isTeams}
          skus={props.skus}
          trialInfo={props.trialInfo}
          onManageSeatsSelect={beginManageSeats}
          onCancelSubscriptionSelect={() => setShowCancelSubscriptionDialog(true)}
        />
      }
    >
      {errorBannerMessage && (
        <SummaryCardBanner
          description={errorBannerMessage}
          hideTitle
          onDismiss={dismissErrorMessage}
          variant="critical"
          title="Error"
        />
      )}
      {props.usageExceededMessage && (
        <SummaryCardBanner
          description={props.usageExceededMessage}
          hideTitle
          variant="critical"
          title="Error"
          data-testid="usage-exceeded-banner"
        />
      )}
      {props.usageAtCapacityMessage && (
        <SummaryCardBanner
          description={props.usageAtCapacityMessage}
          hideTitle
          variant="warning"
          title="Warning"
          data-testid="usage-at-capacity-banner"
        />
      )}
      {successBannerMessage && (
        <SummaryCardBanner
          description={successBannerMessage}
          hideTitle
          onDismiss={dismissSuccessMessage}
          title="Success"
          variant="success"
        />
      )}
      {infoBannerMessage && (
        <SummaryCardBanner
          description={infoBannerMessage}
          hideTitle
          onDismiss={dismissInfoMessage}
          title="Info"
          variant="info"
        />
      )}
      {props.selfServeTrialInfo ? (
        <AdvancedSecurityFeatures
          isTeams={isTeams}
          ghasFeaturesUrl={props.ghasFeaturesUrl}
          trialDays={props.selfServeTrialInfo.trialDays}
          selfServeTrialInfo={props.selfServeTrialInfo}
        />
      ) : isTeams && !teamsUsage ? (
        <AdvancedSecurityFeatures isTeams={isTeams} ghasFeaturesUrl={props.ghasFeaturesUrl} />
      ) : isManagingSeats && props.isBundled ? (
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
        <Stack className={clsx(styles.stackResponsive)} gap="spacious" padding="spacious" align="stretch">
          <UsageSummary
            title="Consumed licenses"
            usageHint={
              <UsageHint
                title="Consumed licenses"
                label="About consumed licenses"
                description={usageSummaryDescription}
                learnMoreUrl="https://docs.github.com/enterprise-cloud@latest/billing/managing-billing-for-your-products/managing-billing-for-github-advanced-security/about-billing-for-github-advanced-security#understanding-usage"
              />
            }
          >
            <Stack className={clsx('width-full', styles.skuStackResponsive)} gap="condensed" padding="none">
              {skus.map(sku => (
                <LicenseUsageSummaryItem
                  consumedLicenses={sku.consumedLicenses}
                  description={sku.sku === 'bundled' ? `${sku.name} licenses` : sku.name}
                  purchasedLicenses={sku.purchasedLicenses}
                  isTrial={!!props.trialInfo}
                  isVolumeLicensed={!props.isMeteredLicensed}
                  key={sku.sku}
                  unlimitedLicense={sku.unlimitedLicense}
                />
              ))}
            </Stack>
          </UsageSummary>
          <div className={clsx(styles.dividerResponsive)} />
          <PaymentSummary
            title={paymentSummaryTitle}
            currentPayment={currentPayment}
            description={paymentSummaryDescription()}
            moreDetailsBody={
              <>
                <div className="f2 text-normal lh-default" data-testid="current-payment">
                  {currentPayment}
                </div>
                <div className="text-normal f5 lh-default color-fg-muted my-2" data-testid="payment-description">
                  {paymentSummaryDescription()}
                </div>
                {skus.map(sku => (
                  <Stack direction="vertical" className="border-top py-2" key={sku.sku}>
                    <Stack direction="horizontal" gap="condensed" className="width-full">
                      <Stack direction="vertical" className="width-full">
                        <span className="text-normal f5 lh-default" data-testid={`${sku.sku}-billable-licenses`}>
                          {formatSkuLabel(sku)}
                        </span>
                        <span
                          className="text-normal f5 lh-default color-fg-muted"
                          data-testid={`${sku.sku}-unit-price`}
                        >
                          ${sku.unitPrice}/month each
                        </span>
                      </Stack>
                      <span className="text-bold f5 lh-default" data-testid={`${sku.sku}-billable-amount`}>
                        ${sku.billableAmount}
                      </span>
                    </Stack>
                  </Stack>
                ))}
              </>
            }
            moreDetailsButtons={
              props.isMeteredLicensed && (
                <Button as="a" href={usageDetailsHref} data-testid="view-usage-details-btn">
                  View billing details
                </Button>
              )
            }
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
        <InlineMessage variant={props.invoiceLicenseInfo.statusMessage.variant} className="px-4 pb-4">
          {props.invoiceLicenseInfo.statusMessage.text}
        </InlineMessage>
      )}
      {pendingCycleChange && !props.trialInfo && (
        <div className={clsx('Box-footer', 'py-2', 'px-3', 'flash-warn')}>
          <PendingPlanChange onCancelConfirmed={cancelPendingPlanChange} pendingChange={pendingCycleChange} />
        </div>
      )}
      {props.trialInfo && (
        <div className="Box-footer px-4 f5">
          <span className="color-fg-muted" data-testid="ghas-summary-trial-footer">
            {trialDisclaimer(props.trialInfo)}
          </span>
        </div>
      )}
      {showStartTrialDialog && props.selfServeTrialInfo && (
        <StartTrialDialog
          onClose={dismissStartFreeTrialDialog}
          onConfirmStart={startFreeTrial}
          isStartingTrial={isStartingTrial}
          selfServeTrialInfo={props.selfServeTrialInfo}
          tradeScreeningResult={props.tradeScreeningResult}
          ghasFeaturesUrl={props.ghasFeaturesUrl}
        />
      )}
      <ServerLicensesFooter licensesInfo={getServerLicensesInfo()} />
    </SummaryCard>
  )
}
