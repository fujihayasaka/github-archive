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

type ConfirmationDialogProps = {
  confirmationDialogSummary: ConfigurationConfirmationSummary | null
  pendingConfigurationChanges: PendingConfigurationChanges
  hasPublicRepos: boolean
  showDefaultForNewReposDropDown?: boolean
  ghasPurchased: boolean
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
  ghasPurchased,
  docsBillingUrl,
}) => {
  const {renderContext} = useAppContext()
  const {config} = pendingConfigurationChanges
  const {
    private_and_internal_repo_count,
    licenses_needed,
    private_and_internal_repos_count_exceeding_licenses,
    requestStatus,
    uses_action_minutes,
  } = confirmationDialogSummary || {}

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

    if (confirmationDialogSummary?.errors) {
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
          case 'blocked_by_enterprise_policy':
            errors.push({
              message:
                'Modifying GitHub Advanced Security and related settings has been blocked by an enterprise policy. Continue with free features for all repositories, or cancel and change your selection.',
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
          default:
            // If the error is not recognized, skip it
            break
        }
      }
    }
    return errors.map(error => ({message: error.message, variant: error.variant as 'danger' | 'warning'}))
  }

  const reposSection = (
    <p>
      This will apply {config.enforcement === 'enforced' && 'and enforce'} {pendingConfigurationChanges.config.name} to{' '}
      {pluralize('repository', confirmationDialogSummary?.total_repo_count, true)}. Repository admins will not be able
      to change security settings set by this configuration.
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
  const licensesNeededSection = (
    <>
      {licenses_needed === null ? (
        unableToCalculateLicenseMessage
      ) : (
        <>
          This will consume{' '}
          <Text sx={{fontWeight: 'bold'}}>
            {' '}
            {licenses_needed} GitHub Advanced Security {pluralize('license', licenses_needed)}
          </Text>
          {uses_action_minutes ? usingActionMinutesSection : '.'}
        </>
      )}{' '}
      <PrimerLink inline href={docsBillingUrl} target="_blank">
        Learn about license consumption
      </PrimerLink>
    </>
  )

  const summarySection = () => {
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
            {ghasPurchased && licensesNeededSection}
          </div>
        )
      default:
        return unableToCalculateLicenseMessage
    }
  }

  return (
    <div {...testIdProps('confirmation-dialog-content')}>
      {getConfirmationDialogErrors().map((error, index) => (
        <Flash
          // eslint-disable-next-line @eslint-react/no-array-index-key
          key={index}
          variant={error.variant}
          {...testIdProps('flash')}
        >
          <Octicon icon={getIcon(error.variant)} />
          {error.message}
        </Flash>
      ))}
      {summarySection()}
      {requestStatus === RequestStatus.Success && (
        <>
          <br />
          {showDefaultForNewReposDropDown && <DefaultForNewReposDropDown hasPublicRepos={hasPublicRepos} />}
        </>
      )}
    </div>
  )
}

export default ConfirmationDialog
