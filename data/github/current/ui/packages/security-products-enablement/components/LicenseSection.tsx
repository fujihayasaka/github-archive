import {settingsOrgSecurityProductsRepositoriesGhasLicenseSummaryPath} from '@github-ui/paths'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useRef, useEffect, useState, useMemo} from 'react'
import type {Repository} from '../security-products-enablement-types'
import {useAppContext} from '../contexts/AppContext'
import {testIdProps} from '@github-ui/test-id-props'
import pluralize from 'pluralize'
import {Text, Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {AlertIcon} from '@primer/octicons-react'
import {useRepositoryContext} from '../contexts/RepositoryContext'

interface LicenseSummary {
  licenses_needed: number
  licenses_freed: number
}

interface LicenseSectionProps {
  selectedReposMap: Record<number, Repository>
  selectedReposCount: number
  totalRepositoryCount: number
  filterQuery: string
}
const LicenseSection: React.FC<LicenseSectionProps> = ({
  selectedReposMap,
  selectedReposCount,
  totalRepositoryCount,
  filterQuery,
}) => {
  const {organization, capabilities} = useAppContext()
  const {licenses, setLicenses} = useRepositoryContext()
  const [licenseSummary, setLicenseSummary] = useState<LicenseSummary | null>(null)
  const [fetchLicenseSummaryFailed, setFetchLicenseSummaryFailed] = useState(false)
  const controllerRef = useRef<AbortController | undefined>(undefined)

  useEffect(() => {
    if (controllerRef.current) controllerRef.current.abort()
    // we only show interactive license data on bundled accounts
    if (!capabilities.advancedSecurity.bundled) {
      return
    }

    controllerRef.current = new AbortController()
    const signal = controllerRef.current.signal

    async function fetchLicenseSummary() {
      try {
        const repository_ids = selectedReposCount === totalRepositoryCount ? [] : Object.keys(selectedReposMap)
        const result = await verifiedFetchJSON(
          settingsOrgSecurityProductsRepositoriesGhasLicenseSummaryPath({org: organization}),
          {
            method: 'POST',
            body: {repository_ids, query: filterQuery, include_license_overview: licenses.failedToFetchLicenses},
            signal,
          },
        )
        if (result.ok) {
          const data = await result.json()
          setLicenseSummary({licenses_needed: data.licenses_needed, licenses_freed: data.licenses_freed})

          if (licenses.failedToFetchLicenses) {
            setLicenses({
              business: data.business,
              bundled: {
                consumedSeats: data.bundled.consumedSeats,
                availableSeats: data.bundled.availableSeats,
                remainingSeats: data.bundled.remainingSeats,
                allowanceExceeded: data.bundled.allowanceExceeded,
                exceededSeats: data.bundled.exceededSeats,
                hasUnlimitedSeats: data.bundled.hasUnlimitedSeats,
                metered: data.bundled.metered,
              },
              failedToFetchLicenses: data.failedToFetchLicenses,
            })
          }

          setFetchLicenseSummaryFailed(false)
        } else {
          setLicenseSummary(null)
          setFetchLicenseSummaryFailed(true)
        }
        // eslint-disable-next-line no-empty
      } catch {} // Aborting a fetch throws an error
    }

    if (selectedReposCount > 0) fetchLicenseSummary()
    else if (selectedReposCount === 0) {
      // Reset these attributes to avoid "flickers" where the previous message is shown, then quickly changes.
      // For example:
      // - We show error message for the license summary
      // - User de-selects all repos, the default "select some repos" message is shown
      // - User selects a repo, the error message is shown again, but is quickly replaced by the license summary
      setLicenseSummary(null)
      setFetchLicenseSummaryFailed(false)
    }
  }, [
    organization,
    selectedReposCount,
    totalRepositoryCount,
    filterQuery,
    selectedReposMap,
    licenses.failedToFetchLicenses,
    setLicenses,
    capabilities.advancedSecurity.bundled,
  ])

  const licensesExceededBanner = useMemo(() => {
    if (licenses.bundled) {
      return (
        <Flash variant="warning" sx={{mt: 3, mb: 3}} {...testIdProps('flash')}>
          <Octicon icon={AlertIcon} />
          Configurations with GitHub Advanced Security cannot be applied because your organization is using{' '}
          {licenses.bundled.exceededSeats} more GitHub Advanced Security{' '}
          {pluralize('license', licenses.bundled.exceededSeats)} than it has purchased. To make changes, remove Advanced
          Security features from some repositories or buy additional licenses.
        </Flash>
      )
    }
  }, [licenses.bundled])

  const ghasText = useMemo(() => {
    const businessName = licenses.business && (
      <>
        {' by '}
        <Text sx={{fontWeight: 'bold'}}>{licenses.business}</Text>
      </>
    )
    if (licenses.bundled) {
      const license = licenses.bundled.hasUnlimitedSeats
        ? licenses.bundled.consumedSeats
        : licenses.bundled.remainingSeats
      return (
        <span>
          {license} GitHub Advanced Security {pluralize('license', license)}{' '}
          {licenses.bundled.hasUnlimitedSeats ? '' : `available, ${licenses.bundled.consumedSeats}`} in use
          {businessName}.
        </span>
      )
    } else if (licenses.secret_protection && licenses.code_security) {
      if (!licenses.secret_protection.hasUnlimitedSeats || !licenses.code_security.hasUnlimitedSeats) {
        return (
          <>
            {!capabilities.advancedSecurity.secretProtectionPurchased ? undefined : (
              <div>
                {licenses.secret_protection.consumedSeats} out of {licenses.secret_protection.availableSeats} Secret
                Protection licenses in use
                {businessName}.
              </div>
            )}
            {!capabilities.advancedSecurity.codeSecurityPurchased ? undefined : (
              <div>
                {licenses.code_security.consumedSeats} out of {licenses.code_security.availableSeats} Code Security{' '}
                licenses in use
                {businessName}.
              </div>
            )}
          </>
        )
      } else {
        return (
          <span>
            {licenses.secret_protection.consumedSeats} Secret Protection{' '}
            {pluralize('license', licenses.secret_protection.consumedSeats)}
            {' • '}
            {licenses.code_security.consumedSeats} Code Security{' '}
            {pluralize('license', licenses.code_security.consumedSeats)} in use
            {businessName}.
          </span>
        )
      }
    }
  }, [
    licenses.business,
    licenses.bundled,
    licenses.secret_protection,
    licenses.code_security,
    capabilities.advancedSecurity.secretProtectionPurchased,
    capabilities.advancedSecurity.codeSecurityPurchased,
  ])

  const licenseSummaryText = useMemo(() => {
    if (licenses.bundled) {
      if (selectedReposCount <= 0 || (licenseSummary === null && !fetchLicenseSummaryFailed)) {
        return <span>Select repositories to apply configurations and view license consumption information.</span>
      } else if (fetchLicenseSummaryFailed) {
        return (
          <span>
            We are unable to calculate how many licenses this application would require in advance. Try selecting fewer
            repositories at a time if you need a license estimate prior to application.
          </span>
        )
      } else {
        return (
          <span>
            For configurations with GitHub Advanced Security:{' '}
            {pluralize('license', licenseSummary!.licenses_needed, true)} required if applying and{' '}
            {pluralize('license', licenseSummary!.licenses_freed, true)} freed up if disabling.
          </span>
        )
      }
    }
  }, [licenses.bundled, selectedReposCount, licenseSummary, fetchLicenseSummaryFailed])

  const licenseContent = useMemo(() => {
    if (licenses.failedToFetchLicenses && fetchLicenseSummaryFailed) {
      return (
        <span>
          We are unable to calculate how many licenses this application would require in advance. Try selecting fewer
          repositories at a time if you need a license estimate prior to application.
        </span>
      )
    } else if (licenses.failedToFetchLicenses) {
      return <span>Unable to calculate license information. Please try again later.</span>
    } else {
      return (
        <>
          <span>{ghasText}</span>
          <p>{licenseSummaryText}</p>
        </>
      )
    }
  }, [licenses.failedToFetchLicenses, fetchLicenseSummaryFailed, ghasText, licenseSummaryText])

  return (
    <div className="Subhead-description mb-3" {...testIdProps('license-summary')}>
      {!licenses.failedToFetchLicenses && licenses.bundled?.allowanceExceeded && licensesExceededBanner}
      {licenseContent}
    </div>
  )
}

export default LicenseSection
