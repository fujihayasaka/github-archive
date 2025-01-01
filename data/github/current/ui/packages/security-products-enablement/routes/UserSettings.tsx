import type React from 'react'
import type {
  OrganizationLicensePayload,
  OrganizationSecurityConfiguration,
  Repository,
  UserSettingsPayload,
} from '../security-products-enablement-types'
import SecurityConfigurationTable from '../components/SecurityConfiguration/Table'
import Subhead from '../components/Subhead'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import RepositorySection from '../components/RepositorySection'
import {RepositoryContext} from '../contexts/RepositoryContext'
import {useMemo, useState} from 'react'
import {useAppContext} from '../contexts/AppContext'

const UserSettings: React.FC = () => {
  const {githubRecommendedConfiguration, customSecurityConfigurations} = useAppContext()
  const {repositories: initialRepositories, totalRepositoryCount: initialTotalRepositoryCount} =
    useRoutePayload<UserSettingsPayload>()

  const changes = {
    inProgress: false,
  }

  const initialLicense = {
    allowanceExceeded: false,
    remainingSeats: 10,
    consumedSeats: 5,
    exceededSeats: 0,
    failedToFetchLicenses: false,
    hasUnlimitedSeats: false,
  }

  const [repositories, setRepositories] = useState<Repository[]>(initialRepositories)
  const [repositoryIds, setRepositoryIds] = useState(() => repositories.map(({id}) => id))
  const [totalRepositoryCount, setTotalRepositoryCount] = useState(initialTotalRepositoryCount)
  const [licenses, setLicenses] = useState<OrganizationLicensePayload>(initialLicense)
  // TODO: update this once we can apply a configuration
  // eslint-disable-next-line unused-imports/no-unused-vars
  const [changesInProgress, setChangesInProgress] = useState(changes)
  const configs: OrganizationSecurityConfiguration[] = useMemo(
    () => [
      ...(githubRecommendedConfiguration ? [githubRecommendedConfiguration] : []),
      ...customSecurityConfigurations,
    ],
    [githubRecommendedConfiguration, customSecurityConfigurations],
  )

  const repositoryContextValue = useMemo(
    () => ({
      repositories,
      setRepositories,
      repositoryIds,
      setRepositoryIds,
      totalRepositoryCount,
      setTotalRepositoryCount,
      licenses,
      setLicenses,
    }),
    [repositoryIds, repositories, totalRepositoryCount, licenses, setLicenses],
  )

  return (
    <>
      <Subhead
        description="Define and apply security configurations to make sure your repositories are protected."
        newConfigButton
        allSecurityProductsUnavailable={false}
      >
        Code security configurations
      </Subhead>

      <SecurityConfigurationTable tableType="user" header={'Configurations'} />
      <RepositoryContext.Provider value={repositoryContextValue}>
        <RepositorySection setChangesInProgress={setChangesInProgress} configs={configs} />
      </RepositoryContext.Provider>
    </>
  )
}

export default UserSettings
