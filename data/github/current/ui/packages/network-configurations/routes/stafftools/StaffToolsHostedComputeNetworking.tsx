import {Box, Heading, PageLayout, Text} from '@primer/react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useState} from 'react'
import type {NetworkConfiguration} from '../../classes/network-configuration'
import {StaffToolsNetworkConfigurationDataTable} from '../../components/stafftools/NetworkConfigurationDataTable'

export interface IStaffToolsHostedComputeNetworkingPayload {
  networkConfigurations: NetworkConfiguration[]
  isEnterprise: boolean
  actor: string
}

export function StaffToolsHostedComputeNetworking() {
  const payload = useRoutePayload<IStaffToolsHostedComputeNetworkingPayload>()
  const [networkConfigurations] = useState<NetworkConfiguration[]>(payload.networkConfigurations ?? [])

  return (
    <PageLayout containerWidth="full" padding="none" rowGap="none">
      <PageLayout.Header divider="line" padding="none">
        <Heading as="h2" className="h2 text-normal" sx={{mb: 2}}>
          Hosted compute networking
        </Heading>
      </PageLayout.Header>
      <PageLayout.Content as="div" sx={{mt: 2}}>
        <Heading as="h3" className="h3 text-normal" sx={{mb: 2}}>
          Network configurations
        </Heading>
        <Box
          sx={{
            border: '1px solid',
            borderColor: 'border.muted',
            borderRadius: 2,
          }}
        >
          {networkConfigurations.length === 0 ? (
            <EmptyStateCard isEnterprise={payload.isEnterprise} />
          ) : (
            <StaffToolsNetworkConfigurationDataTable
              networkConfigurations={networkConfigurations}
              isEnterprise={payload.isEnterprise}
              actor={payload.actor}
            />
          )}
        </Box>
      </PageLayout.Content>
    </PageLayout>
  )
}

interface IEmptyStateCardProps {
  isEnterprise: boolean
}
function EmptyStateCard(props: IEmptyStateCardProps) {
  const entity = props.isEnterprise ? 'enterprise' : 'organization'
  return (
    <Box
      sx={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        flexDirection: 'column',
      }}
    >
      <Text as="p" sx={{p: 32}}>
        {`There are no network configurations configured for this ${entity}.`}
      </Text>
    </Box>
  )
}
