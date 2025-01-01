import {Banner} from '@primer/react/experimental'

function PrimaryAction() {
  return <Banner.PrimaryAction onClick={() => window.location.reload()}>Refresh</Banner.PrimaryAction>
}

export function ConnectionReloadBanner() {
  return (
    <Banner
      variant="critical"
      title="Connection error"
      className="mx-3 mb-2"
      hideTitle
      description="Unstable connection. Try refreshing the page to reconnect."
      primaryAction={<PrimaryAction />}
    />
  )
}
