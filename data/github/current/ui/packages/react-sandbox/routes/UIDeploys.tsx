import {Heading} from '@primer/react'
import {useSyncExternalStore} from 'react'

export function UIDeploys() {
  const uiVersion = useSyncExternalStore(
    () => {
      return () => {}
    },
    () => (globalThis as {UI_VERSION?: string}).UI_VERSION || 'unknown',
    () => 'loading...',
  )
  return (
    <>
      <Heading as="h1">UI Deploys</Heading>
      <p>UI Version: {uiVersion}</p>
    </>
  )
}
