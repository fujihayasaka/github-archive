import {Banner} from '@primer/react/experimental'

function PrimaryAction() {
  return <Banner.PrimaryAction onClick={() => window.location.reload()}>Refresh</Banner.PrimaryAction>
}

export function PreviewAuthFailedBanner() {
  return (
    <Banner
      variant="critical"
      title="Preview authentication error"
      className="mx-3 mb-2"
      hideTitle
      description="Unable to authenticate the app preview. Try refreshing the page."
      primaryAction={<PrimaryAction />}
    />
  )
}
