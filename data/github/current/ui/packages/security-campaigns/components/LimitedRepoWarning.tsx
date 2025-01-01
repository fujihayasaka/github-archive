import {Link} from '@primer/react'

export const LimitedRepoWarning = ({href}: {href: string}): JSX.Element => (
  <p data-testid="incomplete-data-warning" className="color-fg-muted mb-3 mt-1">
    Results are based on a{' '}
    <Link href={href} muted inline>
      limited selection
    </Link>{' '}
    of repositories.
  </p>
)
