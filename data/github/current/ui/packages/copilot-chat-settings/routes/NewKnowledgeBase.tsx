import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {RelayEnvironmentProvider} from 'react-relay'

import {NewKnowledgeBaseForm} from '../components/docs/NewKnowledgeBaseForm'
import type {NewKnowledgeBasePayload} from './payloads'

export function NewKnowledgeBase() {
  const payload = useRoutePayload<NewKnowledgeBasePayload>()

  return (
    <Providers>
      <NewKnowledgeBaseForm docsetOwner={payload.docsetOwner} />
    </Providers>
  )
}

function Providers({children}: React.PropsWithChildren<{}>) {
  const environment = relayEnvironmentWithMissingFieldHandlerForNode()
  return <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
}
