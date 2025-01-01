import {Dialog, Link, Stack} from '@primer/react'
import type {TradeScreeningResult} from '../types/trade-screening'
import {Banner} from '@primer/react/experimental'
import {useClickAnalytics} from '@github-ui/use-analytics'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'
import type {SelfServeTrialInfo} from '../types/self-serve-trial-info'

export type StartTrialDialogProps = {
  onClose: () => void
  onConfirmStart: () => void
  isStartingTrial: boolean
  selfServeTrialInfo: SelfServeTrialInfo
  tradeScreeningResult?: TradeScreeningResult
  ghasFeaturesUrl: string
}

export function StartTrialDialog({
  onClose,
  onConfirmStart,
  isStartingTrial,
  selfServeTrialInfo,
  tradeScreeningResult,
  ghasFeaturesUrl,
}: StartTrialDialogProps) {
  const {basePath, isStafftools} = useNavigation()
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const createOrganizationUrl = `${basePath}/organizations/new`

  const onClickCreateOrganization = () => {
    sendClickAnalyticsEvent({
      category: 'advanced_security_self_serve_trial',
      action: 'click_organization_ghas_settings',
      label: 'ref_cta:organizations;ref_loc:enterprise_licensing',
    })
  }

  const renderBanner = () => {
    if (tradeScreeningResult?.isTradeRestricted) {
      return (
        <Banner
          className="mb-2"
          description={tradeScreeningResult.description}
          title={tradeScreeningResult.title}
          variant="warning"
        />
      )
    }
    if (selfServeTrialInfo.showNoOrgsWarning) {
      return (
        <Banner
          className="mb-2"
          description={
            <>
              You don&apos;t currently have any organizations.{' '}
              <Link inline href={createOrganizationUrl} onClick={onClickCreateOrganization}>
                Create an organization
              </Link>{' '}
              to get started.
            </>
          }
          title="create an organization"
          hideTitle
          variant="warning"
        />
      )
    }
  }

  return (
    <Dialog
      title={`Start your free ${selfServeTrialInfo.trialDays} day trial`}
      onClose={onClose}
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: onClose,
        },
        {
          'aria-disabled': isStartingTrial,
          buttonType: 'primary',
          content: `${isStartingTrial ? 'Starting' : 'Start'} trial`,
          disabled: tradeScreeningResult?.isTradeRestricted || isStafftools,
          loading: isStartingTrial,
          onClick: onConfirmStart,
        },
      ]}
      renderBody={() => (
        <Dialog.Body>
          {renderBanner()}
          <Stack direction="vertical" gap="condensed">
            <p className="mb-0">
              All organizations and repositories that are a part of your enterprise will have access to GitHub Advanced
              Security{' '}
              <Link inline href={ghasFeaturesUrl} target="_blank" rel="noopener">
                features
              </Link>{' '}
              during your trial period.
            </p>
            {selfServeTrialInfo.organizationToOnboard && (
              <p className="mb-0">
                You will be redirected to organzation{' '}
                <Link inline href={`/organizations/${selfServeTrialInfo.organizationToOnboard}/settings`}>
                  {selfServeTrialInfo.organizationToOnboard}
                </Link>{' '}
                to get started with your new trial.
              </p>
            )}
          </Stack>
        </Dialog.Body>
      )}
      role="dialog"
    />
  )
}
