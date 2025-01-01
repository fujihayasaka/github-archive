import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {RelayEnvironmentProvider} from 'react-relay'

export function KnowledgeBaseFormProviders({children}: React.PropsWithChildren<{}>) {
  const environment = relayEnvironmentWithMissingFieldHandlerForNode()
  return <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
}
