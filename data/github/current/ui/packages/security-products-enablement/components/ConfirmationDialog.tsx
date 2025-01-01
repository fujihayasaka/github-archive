import type React from 'react'
import pluralize from 'pluralize'
import {Spinner, Text, Link as PrimerLink, Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import ControlGroupDropDown from './ControlGroupDropDown'
import {useNewRepoPolicyDropdown} from '../hooks/UseNewRepoPolicyDropdown'
import {
  RenderContext,
  RequestStatus,
  type ConfigurationConfirmationSummary,
  type PendingConfigurationChanges,
} from '../security-products-enablement-types'
import {testIdProps} from '@github-ui/test-id-props'
import {getIcon} from '../utils/helpers'
import {useAppContext} from '../contexts/AppContext'
import styles from './ConfirmationDialog.module.css'
import {businessLicensingPath, orgBillingSettingsPath} from '@github-ui/paths'

type ConfirmationDialogProps = {
  confirmationDialogSummary: ConfigurationConfirmationSummary | null
  pendingConfigurationChanges: PendingConfigurationChanges
  hasPublicRepos: boolean
  showDefaultForNewReposDropDown?: boolean
  docsBillingUrl: string
}

type ErrorObject = {
  message: string
  variant: 'danger' | 'warning' | undefined
}

const DefaultForNewReposDropDown = ({hasPublicRepos}: {hasPublicRepos: boolean}) => {
  const {options, onSelect} = useNewRepoPolicyDropdown({hasPublicRepos})

  const newRepoDefaultProps = {
    title: 'Use as default for newly created repositories:',
    testId: 'repo-default',
    options,
    onSelect,
  }

  return <ControlGroupDropDown {...newRepoDefaultProps} />
}

const ConfirmationDialog: React.FC<ConfirmationDialogProps> = ({
  confirmationDialogSummary,
  pendingConfigurationChanges,
  showDefaultForNewReposDropDown = false,
  hasPublicRepos,
  docsBillingUrl,
}) => {
  const {
    organization,
    enterprise,
    renderContext,
    capabilities: {advancedSecurity, enterpriseOwned},
  } = useAppContext()
  const {config} = pendingConfigurationChanges
  const {
    private_and_internal_repo_count,
    bundled,
    licenses_needed,
    code_scanning_licenses_needed,
    code_scanning_licenses_missing,
    secret_scanning_licenses_needed,
    secret_scanning_licenses_missing,
    cost_estimate,
    private_and_internal_repos_count_exceeding_licenses,
    requestStatus,
    uses_action_minutes,
  } = confirmationDialogSummary || {}

  // We only render the cost estimate for Team organizations (no business) with metered SKU split
  const shouldRenderCostEstimate = advancedSecurity.metered && renderContext === 'organization' && !enterpriseOwned
  const costEstimateEmpty = !(cost_estimate?.code_security || cost_estimate?.secret_protection)

  const getConfirmationDialogErrors = (): ErrorObject[] => {
    const errors: Array<{message: string; variant: string}> = []

    const exceeded_message =
      private_and_internal_repos_count_exceeding_licenses === 0
        ? `Private repositories that do not have GitHub Advanced Security will only have free features enabled.`
        : `${private_and_internal_repos_count_exceeding_licenses} private ${pluralize(
            'repository',
            private_and_internal_repos_count_exceeding_licenses,
          )} do not have GitHub Advanced Security and will only have free features enabled.`

    const additional_license_sentence =
      licenses_needed && licenses_needed > 0
        ? `You need ${licenses_needed} additional ${pluralize('license', licenses_needed)}. `
        : ''

    if (!advancedSecurity.bundled) {
      const configUsesCSWithoutLicense = config.code_security_sku_enabled && !advancedSecurity.codeSecurityPurchased
      const configUsesSPWithoutLicense =
        config.secret_protection_sku_enabled && !advancedSecurity.secretProtectionPurchased

      if (configUsesCSWithoutLicense && configUsesSPWithoutLicense) {
        errors.push({
          message: `This configuration enables Code Security and Secret Protection features, which your ${renderContext} has not purchased. Private repositories will only have free features enabled.`,
          variant: 'warning',
        })
      } else if (configUsesCSWithoutLicense) {
        errors.push({
          message: `This configuration enables Code Security features, which your ${renderContext} has not purchased. Private repositories will only have free features enabled.`,
          variant: 'warning',
        })
      } else if (configUsesSPWithoutLicense) {
        errors.push({
          message: `This configuration enables Secret Protection features, which your ${renderContext} has not purchased. Private repositories will only have free features enabled.`,
          variant: 'warning',
        })
      }
    }

    if (confirmationDialogSummary?.errors) {
      const repos = hasPublicRepos ? 'private and internal' : 'all'

      let skipApplyingWillExceedSKUErrors = false
      if (
        confirmationDialogSummary?.errors.includes('applying_will_exceed_code_security_license_limit') &&
        confirmationDialogSummary?.errors.includes('applying_will_exceed_secret_protection_license_limit')
      ) {
        // Ensure we don't add individual errors in the loop:
        skipApplyingWillExceedSKUErrors = true

        // Add a combined error message for both SKUs:
        errors.push({
          message: `You need ${code_scanning_licenses_missing} additional Code Security ${pluralize(
            'license',
            code_scanning_licenses_missing,
          )} and ${secret_scanning_licenses_missing} additional Secret Protection ${pluralize(
            'license',
            secret_scanning_licenses_missing,
          )}. Private repositories will only have free features enabled.`,
          variant: 'warning',
        })
      }

      for (const error of confirmationDialogSummary?.errors) {
        switch (error) {
          case 'internal_ghas_error':
            errors.push({
              message: 'An error ocurred and license usage could not be calculated.',
              variant: 'danger',
            })
            break
          case 'license_limit_exceeded':
            errors.push({
              message: `${additional_license_sentence}${exceeded_message}`,
              variant: 'warning',
            })
            break
          case 'blocked_by_enterprise_policy': {
            const message = advancedSecurity.bundled
              ? 'Modifying GitHub Advanced Security and related settings has been blocked by an enterprise policy. Continue with free features for all repositories, or cancel and change your selection.'
              : `Modifying GitHub Advanced Security and related settings has been blocked by an enterprise policy. Continue without Advanced Security features for ${repos} repositories, or cancel and change your selection.`
            errors.push({message, variant: 'warning'})
            break
          }
          case 'code_security_blocked_by_enterprise_policy':
            errors.push({
              message: `Modifying Code Security and related settings has been blocked by an enterprise policy. Continue without Code Security features for ${repos} repositories, or cancel and change your selection.`,
              variant: 'warning',
            })
            break
          case 'secret_protection_blocked_by_enterprise_policy':
            errors.push({
              message: `Modifying Secret Protection and related settings has been blocked by an enterprise policy. Continue without Secret Protection features for ${repos} repositories, or cancel and change your selection.`,
              variant: 'warning',
            })
            break
          case 'ghas_not_purchased':
            if (private_and_internal_repo_count && private_and_internal_repo_count > 0)
              errors.push({
                message:
                  'This organization does not have GitHub Advanced Security. Private repositories will only have free features enabled.',
                variant: 'warning',
              })
            break
          case 'code_security_license_limit_exceeded':
            errors.push({
              message: 'You are currently exceeding your Code Security license limit.',
              variant: 'warning',
            })
            break
          case 'secret_protection_license_limit_exceeded':
            errors.push({
              message: 'You are currently exceeding your Secret Protection license limit.',
              variant: 'warning',
            })
            break
          case 'applying_will_exceed_code_security_license_limit':
            if (skipApplyingWillExceedSKUErrors) continue
            errors.push({
              message: `You need ${code_scanning_licenses_missing || ''} additional Code Security ${pluralize(
                'license',
                code_scanning_licenses_missing,
              )}. Private repositories will only have free features enabled.`,
              variant: 'warning',
            })
            break
          case 'applying_will_exceed_secret_protection_license_limit':
            if (skipApplyingWillExceedSKUErrors) continue
            errors.push({
              message: `You need ${secret_scanning_licenses_missing || ''} additional Secret Protection ${pluralize(
                'license',
                secret_scanning_licenses_missing,
              )}. Private repositories will only have free features enabled.`,
              variant: 'warning',
            })
            break
          default:
            // If the error is not recognized, skip it
            break
        }
      }
    }
    return errors.map(error => ({message: error.message, variant: error.variant as 'danger' | 'warning'}))
  }

  const showNoLicensesText = shouldRenderCostEstimate && costEstimateEmpty

  // We only want to show this text in the bundled version of the banner.
  const showEnforcementDisclaimerInReposSection = bundled && config.enforcement === 'enforced'
  const reposSection = (
    <p>
      This will apply {config.enforcement === 'enforced' && 'and enforce '}
      <span className="text-bold">{pendingConfigurationChanges.config.name}</span> to{' '}
      {pluralize('repository', confirmationDialogSummary?.total_repo_count, true)}.{' '}
      {showEnforcementDisclaimerInReposSection &&
        'Repository admins will not be able to change security settings set by this configuration. '}
      {showNoLicensesText && 'No additional licenses will be consumed.'}
    </p>
  )

  const usingActionMinutesSection = ' and some features in this configuration use Action minutes.'

  const unableToCalculateLicenseMessage =
    renderContext === RenderContext.Enterprise ? (
      <>
        We are currently unable to calculate the number of licenses needed for this application. You can click
        &#39;Apply&#39; anyway, or do more fine-grained rollout at the organization level for a pre-application
        estimate.
      </>
    ) : (
      <>
        We are currently unable to calculate the required number of licenses for this application. To get an estimate,
        try selecting fewer repositories at a time. Alternatively, you can proceed by clicking &#39;Apply&#39;.
      </>
    )
  const bundledLicensesNeededSection = (
    <>
      {licenses_needed === null ? (
        unableToCalculateLicenseMessage
      ) : (
        <>
          This will consume{' '}
          <span className={styles.Text}>
            {' '}
            {licenses_needed} GitHub Advanced Security {pluralize('license', licenses_needed)}
          </span>
          {uses_action_minutes ? usingActionMinutesSection : '.'}{' '}
          <PrimerLink inline href={docsBillingUrl} target="_blank">
            Learn about license consumption
          </PrimerLink>
        </>
      )}
    </>
  )

  // Helper to generate unbundledCostEstimate line items in the receipt style:
  const lineItem = (quantity: number, product: string, total: string, pricePerActiveCommitter: number) => {
    return (
      <div className="border-top py-2">
        <div className="d-flex flex-justify-between fgColor-default text-normal">
          <span>
            {quantity} additional {product} {pluralize('license', quantity)}
          </span>
          <span className="text-bold ml-1">{total}</span>
        </div>
        ${pricePerActiveCommitter.toLocaleString()} per active committer within the last 90 days
      </div>
    )
  }

  const billingInfoLink =
    renderContext === 'organization'
      ? orgBillingSettingsPath({org: organization})
      : businessLicensingPath({businessSlug: enterprise!.slug})

  const unbundledCostEstimate = (
    <div className="fgColor-muted text-small">
      <div className="my-2 py-2 px-3 bgColor-inset rounded-2">
        <div className="my-2 fgColor-default">
          <span className="f3">{cost_estimate?.total.cost}</span>
          <span className="f5"> / month</span>
        </div>

        <div className="mb-2">
          New estimated cost for your organization, based on {cost_estimate?.total.licenses} additional billable{' '}
          {pluralize('license', cost_estimate?.total.licenses)}.
        </div>

        {cost_estimate?.code_security &&
          lineItem(
            cost_estimate?.code_security.seat_count,
            'Code Security',
            cost_estimate?.code_security.total_cost,
            30,
          )}
        {cost_estimate?.secret_protection &&
          lineItem(
            cost_estimate?.secret_protection.seat_count,
            'Secret Protection',
            cost_estimate?.secret_protection.total_cost,
            19,
          )}
      </div>

      <div>
        You will be charged for additional committers in your next billing cycle.{' '}
        <PrimerLink inline href={billingInfoLink} target="_blank">
          Review billing information
        </PrimerLink>{' '}
        for more details.
      </div>
    </div>
  )

  const renderCodeSecurityLicenses =
    advancedSecurity.codeSecurityPurchased && Number.isFinite(code_scanning_licenses_needed)
  const renderSecretProtectionLicenses =
    advancedSecurity.secretProtectionPurchased && Number.isFinite(secret_scanning_licenses_needed)
  const unbundledLicensesNeededSection = (
    <>
      {bundled === null ? (
        unableToCalculateLicenseMessage
      ) : (
        <>
          <ul className={styles.detailsList}>
            {renderCodeSecurityLicenses && (
              <li className="mb-1">
                You will be consuming{' '}
                <span className="text-bold">
                  {code_scanning_licenses_needed} additional Code Security{' '}
                  {pluralize('license', code_scanning_licenses_needed)}.
                </span>
              </li>
            )}
            {renderSecretProtectionLicenses && (
              <li className="mb-1">
                You will be consuming{' '}
                <span className="text-bold">
                  {secret_scanning_licenses_needed} additional Secret Protection{' '}
                  {pluralize('license', secret_scanning_licenses_needed)}.
                </span>
              </li>
            )}
            {uses_action_minutes && <li>Some features in this configuration use Action minutes.</li>}
          </ul>

          <div>
            <Text size="small" className="fgColor-muted">
              License consumption is based on active committers within the last 90 days. Learn more about{' '}
              <PrimerLink inline href={docsBillingUrl} target="_blank">
                Advanced Security billing
              </PrimerLink>
              .
            </Text>
          </div>
        </>
      )}
    </>
  )

  const summarySection = () => {
    if (renderContext === 'user') return reposSection

    const renderBundledLicenses = advancedSecurity.purchased && advancedSecurity.bundled

    // Only render when SKU-split and owned by an enterprise *or* SKU-split Enterprise-level configs:
    const renderUnbundledLicenses =
      !advancedSecurity.bundled &&
      ((enterpriseOwned && renderContext === 'organization') || renderContext === 'enterprise')

    switch (requestStatus) {
      case RequestStatus.InProgress:
        return (
          <div className="text-center">
            <Spinner size="small" />
          </div>
        )
      case RequestStatus.Success:
        return (
          <div>
            {reposSection}
            {renderBundledLicenses && bundledLicensesNeededSection /* Bundled (legacy) confirmation */}
            {renderUnbundledLicenses && unbundledLicensesNeededSection /* Unbundled license summary */}
            {shouldRenderCostEstimate && !costEstimateEmpty && unbundledCostEstimate /* Unbundled cost estimate */}
          </div>
        )
      default:
        return unableToCalculateLicenseMessage
    }
  }

  return (
    <div {...testIdProps('confirmation-dialog-content')}>
      {renderContext !== 'user' &&
        getConfirmationDialogErrors().map((error, index) => (
          <Flash
            // eslint-disable-next-line @eslint-react/no-array-index-key
            key={index}
            variant={error.variant}
            className="mb-2"
            {...testIdProps('flash')}
          >
            <Octicon icon={getIcon(error.variant)} />
            {error.message}
          </Flash>
        ))}
      {summarySection()}
      {requestStatus === RequestStatus.Success && showDefaultForNewReposDropDown && (
        <div className="mt-2 border-top">
          <DefaultForNewReposDropDown hasPublicRepos={hasPublicRepos} />
        </div>
      )}
    </div>
  )
}

export default ConfirmationDialog
