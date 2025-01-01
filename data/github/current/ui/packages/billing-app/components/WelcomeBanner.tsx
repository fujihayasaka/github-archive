import {InfoIcon} from '@primer/octicons-react'

import {Link, Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

const BILLING_PLATFORM_BETA_DOC_LINK =
  'https://docs.github.com/enterprise-cloud@latest/early-access/billing/billing-private-beta'

const BILLING_PLATFORM_DOC_LINK =
  'https://docs.github.com/billing/using-the-new-billing-platform/about-the-new-billing-platform'

interface Props {
  multiTenant: boolean
  isEnterprise: boolean
}

export default function WelcomeBanner({multiTenant, isEnterprise}: Props) {
  const docsLink = isEnterprise ? BILLING_PLATFORM_BETA_DOC_LINK : BILLING_PLATFORM_DOC_LINK
  const linkText = 'please refer to the docs content here'
  const bannerText = multiTenant
    ? 'You can view your usage in the billing pages, starting from the date you gained access. For more information'
    : isEnterprise
      ? 'For more information on using these billing pages and cost center functionality'
      : 'For more information on using these billing pages'
  return (
    <Flash sx={{mb: 3}}>
      <Octicon aria-label="Alert icon" icon={InfoIcon} />
      <span>
        {bannerText}{' '}
        <Link inline href={docsLink}>
          {linkText}
        </Link>
        .
      </span>
    </Flash>
  )
}
