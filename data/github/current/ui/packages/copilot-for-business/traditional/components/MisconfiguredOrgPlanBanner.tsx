import {Link} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {createPortal} from 'react-dom'

type Props = {
  visible: boolean
  slug: string | undefined
}

export function MisconfiguredOrgPlanBanner(props: Props) {
  const container = document.getElementById('js-flash-container')

  if (!container) {
    return null
  }

  if (!props.visible) {
    return null
  }

  return createPortal(
    <Banner
      title="This organization has an unconfigured Copilot plan."
      variant="warning"
      data-testid="cfb-unconfigured-org-banner"
      description={
        <p>
          Soon, access management will be unavailable for this organization if no Copilot plan is configured. Visit your{' '}
          <Link inline href={`/enterprises/${props.slug}/settings/copilot`}>
            enterprise&apos;s settings page
          </Link>{' '}
          to choose a plan for this organization.
        </p>
      }
    />,
    container,
  )
}
