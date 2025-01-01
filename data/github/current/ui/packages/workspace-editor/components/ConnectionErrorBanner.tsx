import {Spinner} from '@primer/react'
import {Banner} from '@primer/react/experimental'

import {ConnectionStatus, useServerEvents} from '../../workbench/contexts/ServerEventsContext'

function PrimaryAction({connectionStatus}: {connectionStatus: ConnectionStatus}) {
  const {reconnect} = useServerEvents()
  switch (connectionStatus) {
    case ConnectionStatus.DISCONNECTED:
      return <Banner.PrimaryAction onClick={reconnect}>Retry</Banner.PrimaryAction>
    case ConnectionStatus.RECONNECTING:
    case ConnectionStatus.CONNECTING:
      return <Spinner size="small" srText="Reconnecting" />
  }
}

export function ConnectionErrorBanner() {
  const {connectionStatus} = useServerEvents()
  return (
    <Banner
      variant="critical"
      title="Connection error"
      className="mx-3 mb-2"
      hideTitle
      description="Unable to connect to the server. Please check your internet connection and try again."
      primaryAction={<PrimaryAction connectionStatus={connectionStatus} />}
    />
  )
}
