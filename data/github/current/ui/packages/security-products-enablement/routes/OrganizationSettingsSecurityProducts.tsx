import {useState, useMemo, useCallback} from 'react'
import {Link as PrimerLink} from '@primer/react'
import {
  orgOnboardingAdvancedSecurityPath,
  settingsOrgSecurityConfigurationsNewPath,
  settingsEnterpriseSecurityProductsPath,
} from '@github-ui/paths'
import {OnboardingTipBanner} from '@github-ui/onboarding-tip-banner'
import {ShieldCheckIcon} from '@primer/octicons-react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useSearchParams} from '@github-ui/use-navigate'
import {useAlive} from '@github-ui/use-alive'
import {useDebounce} from '@github-ui/use-debounce'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useAppContext} from '../contexts/AppContext'
import {RepositoryContext} from '../contexts/RepositoryContext'
import {fetchRefresh} from '../utils/api-helpers'
import {dismissNoticePath} from '../utils/banner-helper'
import {Link} from '@github-ui/react-core/link'
import RepositorySection from '../components/RepositorySection'
import Subhead from '../components/Subhead'
import Banner from '../components/Banner'
import TalkToUs from '../components/TalkToUs'
import BlankSlate from '../components/BlankSlate'
import SecurityConfigurationTable from '../components/SecurityConfiguration/Table'
import {
  type MiniSecurityConfiguration,
  type OrganizationSettingsSecurityProductsPayload,
  type FailureCounts,
  SecurityProductAvailability,
  type Repository,
  type OrganizationLicensePayload,
  type Enterprise,
} from '../security-products-enablement-types'

import styles from './OrganizationSettingsSecurityProducts.module.css'

const OrganizationSettingsSecurityProducts: React.FC = () => {
  const {
    securityProducts,
    organization,
    enterprise,
    enterpriseAdmin,
    docsUrls,
    capabilities,
    githubRecommendedConfiguration: initialGithubRecommendedConfiguration,
    customSecurityConfigurations: initialCustomSecurityConfigurations,
    customEnterpriseSecurityConfigurations: initialCustomEnterpriseSecurityConfigurations,
    enterpriseConfigsAvailable,
  } = useAppContext()
  const [searchParams] = useSearchParams()
  const {
    showInfoBanner: initialShowInfoBanner,
    showTalkToUsBanner: initialShowTalkToUsBanner,
    changesInProgress: changes,
    repositories: initialRepositories,
    channel,
    failureCounts: initialFailureCounts,
    licenses: initialLicenses,
    totalRepositoryCount: initialTotalRepositoryCount,
  } = useRoutePayload<OrganizationSettingsSecurityProductsPayload>()

  const [changesInProgress, setChangesInProgress] = useState(changes)
  const [repositories, setRepositories] = useState<Repository[]>(initialRepositories)
  const [totalRepositoryCount, setTotalRepositoryCount] = useState(initialTotalRepositoryCount)
  const [showInfoBanner, setShowInfoBanner] = useState(initialShowInfoBanner)
  const [showTalkToUsBanner, setShowTalkToUsBanner] = useState(initialShowTalkToUsBanner)

  const [githubRecommendedConfiguration, setGithubRecommendedConfiguration] = useState<
    MiniSecurityConfiguration | undefined
  >(initialGithubRecommendedConfiguration)
  const [customSecurityConfigurations, setCustomSecurityConfigurations] = useState<MiniSecurityConfiguration[]>(
    initialCustomSecurityConfigurations,
  )
  const [customEnterpriseSecurityConfigurations, setCustomEnterpriseSecurityConfigurations] = useState<
    MiniSecurityConfiguration[]
  >(initialCustomEnterpriseSecurityConfigurations)
  const [failureCounts, setFailureCounts] = useState<FailureCounts>(initialFailureCounts)
  const configs: MiniSecurityConfiguration[] = useMemo(
    () => [
      ...(githubRecommendedConfiguration ? [githubRecommendedConfiguration] : []),
      ...customEnterpriseSecurityConfigurations,
      ...customSecurityConfigurations,
    ],
    [githubRecommendedConfiguration, customEnterpriseSecurityConfigurations, customSecurityConfigurations],
  )

  const [licenses, setLicenses] = useState<OrganizationLicensePayload>(initialLicenses)

  const repositoryContextValue = useMemo(
    () => ({
      repositories,
      setRepositories,
      totalRepositoryCount,
      setTotalRepositoryCount,
      licenses,
      setLicenses,
    }),
    [repositories, totalRepositoryCount, licenses, setLicenses],
  )

  const allSecurityProductsUnavailable = Object.values(securityProducts).every(
    product => product.availability === SecurityProductAvailability.Unavailable,
  )

  // Determine the BlankSlate Content
  const blankSlateProps = useMemo(() => {
    if (allSecurityProductsUnavailable) {
      return {
        header: 'No security features installed',
        message: 'Your GitHub Enterprise instance does not have any security features installed. ',
        url: docsUrls.installSecurityProducts,
        linkText: 'Learn about installing security features on GitHub Enterprise',
      }
    }

    if (configs.length === 0 && customEnterpriseSecurityConfigurations.length === 0) {
      return {
        header: 'Protect your code with Advanced Security configurations',
        message:
          'Enable and disable security features for specific repositories, ensure compliance, and manage your GitHub Advanced Security licenses with ',
        url: docsUrls.createConfig,
        linkText: 'security configurations',
        newConfigButtonPath: settingsOrgSecurityConfigurationsNewPath({org: organization}),
      }
    }

    return null
  }, [
    allSecurityProductsUnavailable,
    configs.length,
    customEnterpriseSecurityConfigurations.length,
    docsUrls.installSecurityProducts,
    docsUrls.createConfig,
    organization,
  ])

  const debouncedRefresh = useDebounce(
    useCallback(async () => {
      const repositoryIds = repositories.map(({id}) => id)
      const result = await fetchRefresh(organization, repositoryIds)

      // Update the configurations if the fetch was successful
      if (result) {
        const updatedGithubRecommendedConfiguration = result.githubRecommendedConfiguration as
          | MiniSecurityConfiguration
          | undefined
        const updatedSecurityConfigurations = result.customSecurityConfigurations
        const updatedCustomEnterpriseSecurityConfigurations = result.customEnterpriseSecurityConfigurations

        // Update the repositories_count for GitHub recommended configuration
        if (updatedGithubRecommendedConfiguration) {
          setGithubRecommendedConfiguration(prevConfig => {
            if (prevConfig) {
              return {
                ...prevConfig,
                repositories_count: updatedGithubRecommendedConfiguration.repositories_count,
              }
            }
          })
        }

        // Update the custom security configurations:
        if (updatedSecurityConfigurations) setCustomSecurityConfigurations(updatedSecurityConfigurations)
        if (updatedCustomEnterpriseSecurityConfigurations)
          setCustomEnterpriseSecurityConfigurations(updatedCustomEnterpriseSecurityConfigurations)

        // This needs to specifically check for undefined because we want to update the state if result.inProgress is true or false
        if (result.inProgress !== undefined) setChangesInProgress({inProgress: result.inProgress, type: result.type})

        if (result.repositories) {
          setRepositories(prevRepositories => {
            const updatedRepositories = [...prevRepositories]

            for (const updatedRepo of result.repositories) {
              const index = updatedRepositories.findIndex(repo => repo.id === updatedRepo.id)
              if (index !== -1) {
                updatedRepositories[index] = {...updatedRepositories[index], ...updatedRepo}
              } else {
                updatedRepositories.push(updatedRepo)
              }
            }

            return updatedRepositories
          })
        }

        if (result.failureCounts) setFailureCounts(result.failureCounts)

        if (result.totalRepositoryCount) setTotalRepositoryCount(result.totalRepositoryCount)

        if (result.licenses?.failedToFetchLicenses !== undefined && !result.licenses.failedToFetchLicenses) {
          setLicenses(result.licenses)
        }
      }
    }, [organization, repositories, setLicenses]),
    1500,
    {leading: true, trailing: true},
  )

  const handleAliveEvent = useCallback(() => {
    debouncedRefresh()
  }, [debouncedRefresh])

  useAlive(channel, handleAliveEvent)

  const inProgressText =
    changesInProgress.type === 'enablement_changes'
      ? `Another enablement event is in progress. This may take a while and applying or editing configurations \
  will be unavailable until all repositories have been updated.`
      : 'Applying configurations to repositories. This may take a while and applying or editing configurations\
  will be unavailable until all repositories have been updated.'

  const infoBannerText =
    'This organization does not have GitHub Advanced Security, which is free for public repositories and \
    billed per active committer for private and internal repositories. To apply configurations with GitHub \
    Advanced Security features to private repositories, '
  const infoBannerLinkText = 'upgrade to GitHub Advanced Security.'

  const handleDismiss = async (noticeName: string, setState: (state: boolean) => void) => {
    const result = await verifiedFetch(dismissNoticePath({notice: noticeName}), {
      method: 'POST',
    })

    if (result.ok) setState(false)
  }

  const enterpriseConfigurationsTableHasConfiguration =
    customEnterpriseSecurityConfigurations.length > 0 || initialGithubRecommendedConfiguration

  // we are setting reloadDocument since we need to trigger a full page load to switch the nav shell from Org to Enterprise
  const enterpriseAdminTip = (e: Enterprise) => {
    return (
      <span className={styles.Text}>
        <span className="text-bold">Tip:</span> As a {e.name} admin, you can{' '}
        <PrimerLink inline reloadDocument as={Link} to={settingsEnterpriseSecurityProductsPath({enterprise: e.slug})}>
          manage {organization} configurations in enterprise settings
        </PrimerLink>
        .
      </span>
    )
  }

  return (
    <>
      <Subhead
        description="Define and apply security configurations to make sure your repositories are protected."
        organization={organization}
        newConfigButton
        allSecurityProductsUnavailable={allSecurityProductsUnavailable}
      >
        Security configurations
      </Subhead>
      {blankSlateProps ? (
        <BlankSlate {...blankSlateProps} />
      ) : (
        <>
          {showInfoBanner && (
            <Banner
              bannerText={infoBannerText}
              linkText={infoBannerLinkText}
              linkHref={docsUrls.ghasTrial}
              onDismiss={() => {
                handleDismiss('security_configurations_non_ghas_org_info', setShowInfoBanner)
              }}
              dismissible
              bannerType="info"
            />
          )}

          {changesInProgress.inProgress && <Banner bannerText={inProgressText} bannerType="inprogress" />}
          {/* the controller will hide the talk to us banner if we are showing the info banner above */}
          {/* but we do want to hide the banner if are in the onboarding flow */}
          {searchParams.get('tip') === 'recommended_settings' ? (
            <OnboardingTipBanner
              link={orgOnboardingAdvancedSecurityPath({org: organization})}
              icon={ShieldCheckIcon}
              linkText="Back to onboarding"
              heading="Enable Advanced Security with GitHub recommended configuration"
            >
              Automatically apply our standard settings to Dependabot, code scanning, and secret scanning by selecting{' '}
              <strong> Apply to</strong> below.
            </OnboardingTipBanner>
          ) : (
            showTalkToUsBanner && (
              <TalkToUs
                onDismiss={() => {
                  handleDismiss('security_configurations_talk_to_us', setShowTalkToUsBanner)
                }}
              />
            )
          )}
          {enterpriseConfigsAvailable && capabilities.enterpriseOwned && enterprise && (
            <>
              {enterpriseConfigurationsTableHasConfiguration && (
                <>
                  <SecurityConfigurationTable
                    tableType="enterprise"
                    header="Enterprise configurations"
                    managedBy={`Managed by ${enterprise.name}`}
                  />
                  {/* we should always render the box so that there is spacing between the two tables */}
                  <div className={styles.Box}>{enterpriseAdmin && enterpriseAdminTip(enterprise)}</div>
                </>
              )}
            </>
          )}

          {(!enterpriseConfigsAvailable || (enterpriseConfigsAvailable && customSecurityConfigurations.length > 0)) && (
            <SecurityConfigurationTable
              tableType="organization"
              header={
                capabilities.enterpriseOwned && enterpriseConfigsAvailable
                  ? 'Organization configurations'
                  : 'Configurations'
              }
            />
          )}

          {enterpriseConfigsAvailable &&
            capabilities.enterpriseOwned &&
            enterprise &&
            !enterpriseConfigurationsTableHasConfiguration &&
            enterpriseAdmin && <div className={styles.Box_1}>{enterpriseAdminTip(enterprise)}</div>}

          <RepositoryContext.Provider value={repositoryContextValue}>
            <RepositorySection
              setChangesInProgress={setChangesInProgress}
              configs={configs}
              failureCounts={failureCounts}
            />
          </RepositoryContext.Provider>
        </>
      )}
    </>
  )
}

export default OrganizationSettingsSecurityProducts
