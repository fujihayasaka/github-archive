import {Box, Button, Flash, Heading, Link, PageLayout, Pagination, TextInput} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {SearchIcon, AlertIcon, ShieldLockIcon} from '@primer/octicons-react'
import {useNavigate} from '@github-ui/use-navigate'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useEffect, useState} from 'react'
import type {NetworkConfiguration} from '../classes/network-configuration'
import {NetworkConfigurationConsts} from '../constants/network-configuration-consts'
import {ListView} from '@github-ui/list-view'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {announce} from '@github-ui/aria-live'
import {NetworkConfigurationListItem} from '../components/NetworkConfigurationListItem'

export interface NetworkConfigurationsPayload {
  networks: NetworkConfiguration[]
  removeNetworkConfigurationPath: string
  updateNetworkConfigurationPath: string
  newPrivateNetworkPath: string
  networkConfigurationsPath: string
  enabledForCodespaces: boolean
  displayConfigStatusBanner: boolean
  displayAllVNetStatusBanner: boolean
  orgCanEditNetworkConfiguration: boolean
  userCanEditNetworkConfiguration: boolean
  isBusiness: boolean
}

export function NetworkConfigurations() {
  const payload = useRoutePayload<NetworkConfigurationsPayload>()
  const [networkConfigurations, setNetworkConfigurations] = useState<NetworkConfiguration[]>(payload.networks ?? [])
  const [searchText, setSearchText] = useState('')
  const defaultNetworkConfigurationPerPage = 25

  const removeNetworkConfiguration = async (networkId: string) => {
    setNetworkConfigurations(networkConfigurations.filter(item => item.id !== networkId))
  }

  const filteredNetworks = networkConfigurations.filter(
    item => !searchText || item.name.toLowerCase().includes(searchText.toLowerCase()),
  )

  const totalNetworkConfigurations = filteredNetworks.length
  const pageCount = Math.ceil(totalNetworkConfigurations / defaultNetworkConfigurationPerPage)
  const [currentPage, setCurrentPage] = useState(1)
  const canEditNetworkConfiguration = payload.orgCanEditNetworkConfiguration && payload.userCanEditNetworkConfiguration
  //Set the message to the higher impact text, AllVNet, if both flags are set.
  const statusBannerMessage = payload.displayAllVNetStatusBanner
    ? NetworkConfigurationConsts.statusAllVNetBannerMessage
    : NetworkConfigurationConsts.statusConfigBannerMessage

  return (
    <PageLayout containerWidth="full" padding="none" sx={{p: 0}}>
      <PageLayout.Header>
        {(payload.displayConfigStatusBanner || payload.displayAllVNetStatusBanner) && (
          <Flash variant="warning" sx={{alignItems: 'center', display: 'flex', mb: 4}}>
            <Octicon icon={AlertIcon} />
            <div>
              <p>
                <b>Warning:</b> {statusBannerMessage}
              </p>
            </div>
          </Flash>
        )}
        <div className="border-bottom">
          <Heading as="h2" className="h2 text-normal h1-override-shared-component">
            {NetworkConfigurationConsts.hostedComputeNetworkingTitle}
          </Heading>
          <p className="color-fg-muted mb-2">
            {NetworkConfigurationConsts.networkConfigurationsDescription}{' '}
            <Link inline href={NetworkConfigurationConsts.learnMoreLink}>
              {NetworkConfigurationConsts.learnMore}
            </Link>
          </p>
        </div>
      </PageLayout.Header>
      <PageLayout.Content as="div">
        {networkConfigurations.length === 0 && (
          <EmptyStateCard
            newPrivateNetworkPath={payload.newPrivateNetworkPath}
            isBusiness={payload.isBusiness}
            orgCanEditNetworkConfiguration={payload.orgCanEditNetworkConfiguration}
            userCanEditNetworkConfiguration={payload.userCanEditNetworkConfiguration}
          />
        )}
        {networkConfigurations.length > 0 && (
          <div>
            <Box sx={{display: 'flex', flexDirection: 'row', justifyContent: 'end', pb: '17px'}}>
              <TextInput
                block
                leadingVisual={SearchIcon}
                aria-label={NetworkConfigurationConsts.searchBoxPlaceholder}
                name="privateNetwork"
                placeholder={NetworkConfigurationConsts.searchBoxPlaceholder}
                onChange={e => setSearchText(e.target.value)}
              />
              {canEditNetworkConfiguration && (
                <Box sx={{ml: 2}}>
                  <NetworkConfigurationActionMenu newPrivateNetworkPath={payload.newPrivateNetworkPath} />
                </Box>
              )}
            </Box>
            <NetworkConfigurationList
              networkConfigurationsPath={payload.networkConfigurationsPath}
              searchText={searchText}
              networks={filteredNetworks}
              updateNetworkConfigurationPath={payload.updateNetworkConfigurationPath}
              removeNetworkConfigurationPath={payload.removeNetworkConfigurationPath}
              removeNetworkConfigurationFunction={removeNetworkConfiguration}
              enabledForCodespaces={payload.enabledForCodespaces}
              pageNumber={currentPage}
              defaultNetworkConfigurationPerPage={defaultNetworkConfigurationPerPage}
              canEditNetworkConfiguration={canEditNetworkConfiguration}
            />
          </div>
        )}
      </PageLayout.Content>
      <PageLayout.Footer>
        {pageCount > 1 && (
          <Pagination
            pageCount={pageCount}
            currentPage={currentPage}
            onPageChange={(e, newPage) => {
              e.preventDefault()
              if (currentPage !== newPage) {
                setCurrentPage(newPage)
              }
            }}
            showPages={{narrow: false}}
          />
        )}
      </PageLayout.Footer>
    </PageLayout>
  )
}

function EmptyStateCard({
  newPrivateNetworkPath,
  isBusiness,
  orgCanEditNetworkConfiguration,
  userCanEditNetworkConfiguration,
}: {
  newPrivateNetworkPath: string
  isBusiness: boolean
  orgCanEditNetworkConfiguration: boolean
  userCanEditNetworkConfiguration: boolean
}) {
  return (
    <Box
      sx={{
        border: '1px solid var(--borderColor-default, var(--color-border-default))',
        borderRadius: '6px',
        p: 132,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        flexDirection: 'column',
      }}
    >
      {orgCanEditNetworkConfiguration ? (
        <>
          <Box sx={{gap: 1, textAlign: 'center'}}>
            <Box sx={{fontSize: 3, color: 'fg.default', fontWeight: 'bold'}}>
              {NetworkConfigurationConsts.noNetworkConfigurationsAdded}
            </Box>
            <Box sx={{color: 'fg.muted', flexWrap: 'wrap', fontSize: '14px'}}>
              {isBusiness
                ? NetworkConfigurationConsts.noNetworkConfigurationsAddedDescriptionBusiness
                : NetworkConfigurationConsts.noNetworkConfigurationsAddedDescriptionOrg}
            </Box>
          </Box>
          {userCanEditNetworkConfiguration && (
            <Box sx={{p: 5}}>
              <NetworkConfigurationActionMenu newPrivateNetworkPath={newPrivateNetworkPath} />
            </Box>
          )}
        </>
      ) : (
        <OrgDisabledEmptyStateCard />
      )}
    </Box>
  )
}

function NetworkConfigurationActionMenu({newPrivateNetworkPath}: {newPrivateNetworkPath: string}) {
  const navigate = useNavigate()
  return (
    <Button variant="primary" onClick={() => navigate(newPrivateNetworkPath)}>
      {NetworkConfigurationConsts.newNetworkConfiguration}
    </Button>
  )
}

function NetworkConfigurationList({
  networkConfigurationsPath,
  searchText,
  networks,
  updateNetworkConfigurationPath,
  removeNetworkConfigurationPath,
  removeNetworkConfigurationFunction,
  enabledForCodespaces,
  pageNumber,
  defaultNetworkConfigurationPerPage,
  canEditNetworkConfiguration,
}: {
  networkConfigurationsPath: string
  searchText: string
  networks: NetworkConfiguration[]
  updateNetworkConfigurationPath: string
  removeNetworkConfigurationPath: string
  removeNetworkConfigurationFunction: (networkId: string) => void
  enabledForCodespaces: boolean
  pageNumber: number
  defaultNetworkConfigurationPerPage: number
  canEditNetworkConfiguration: boolean
}) {
  const itemCount = networks.length
  const title = `${itemCount} ${itemCount === 1 ? 'item' : 'items'}`

  useEffect(() => {
    announce(title)
  }, [title])

  const page = itemCount > 0 && !searchText ? pageNumber : 1
  const filteredNetworksSlice = getNetworkConfigurationsChunk(networks, defaultNetworkConfigurationPerPage, page)

  return (
    <Box sx={{border: '1px solid', borderColor: 'border.muted', borderRadius: 2}}>
      <ListView metadata={<ListViewMetadata title={title} assistiveAnnouncement={title} />} title={title}>
        {filteredNetworksSlice.map(item => (
          <NetworkConfigurationListItem
            networkConfigurationsPath={networkConfigurationsPath}
            key={item.id}
            networkConfig={item}
            updateNetworkConfigurationPath={updateNetworkConfigurationPath}
            removeNetworkConfigurationPath={removeNetworkConfigurationPath}
            removeNetworkConfigurationFunction={removeNetworkConfigurationFunction}
            enabledForCodespaces={enabledForCodespaces}
            canEditNetworkConfiguration={canEditNetworkConfiguration}
          />
        ))}
      </ListView>
    </Box>
  )
}

function getNetworkConfigurationsChunk(
  networkConfigurations: NetworkConfiguration[],
  itemsPerPage: number,
  pageNumber: number,
) {
  const start = (pageNumber - 1) * itemsPerPage
  return networkConfigurations.slice(start, start + itemsPerPage)
}

function OrgDisabledEmptyStateCard() {
  return (
    <Box sx={{gap: 1, textAlign: 'center'}}>
      <Box sx={{fontSize: 3, color: 'fg.default', fontWeight: 'bold'}}>
        {NetworkConfigurationConsts.orgDisabledEmptyStateCardTitle}
      </Box>
      <Box sx={{color: 'fg.muted', flexWrap: 'wrap', fontSize: '14px'}}>
        <Octicon icon={ShieldLockIcon} sx={{pr: 1}} />
        {NetworkConfigurationConsts.orgDisabledEmptyStateCardDescription}
      </Box>
    </Box>
  )
}
