import type React from 'react'
import {Flash, Link as PrimerLink, IconButton} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {InfoIcon, XIcon} from '@primer/octicons-react'
import {Link} from '@github-ui/react-core/link'

import styles from './Banner.module.css'
import {clsx} from 'clsx'

interface BannerProps {
  bannerText: string
  linkText?: string
  linkHref?: string
  dismissible?: boolean
  onDismiss?: () => void
  bannerType?: string
}

const Banner: React.FC<BannerProps> = ({
  bannerText,
  linkText,
  linkHref,
  dismissible = false,
  onDismiss,
  bannerType,
}) => {
  const handleDismiss = () => {
    if (onDismiss) onDismiss()
  }

  return (
    <Flash data-testid={`banner-${bannerType}`} className={styles.Flash}>
      <div className={styles.Box}>
        <Octicon icon={InfoIcon} className={styles.Octicon} />
        <span data-testid="banner-text" className={styles.Text}>
          {bannerText}
          {/* inline Pimer prop is not working properly with as= so we will continue to use our styling here */}
          {linkText && linkHref && (
            <PrimerLink
              as={Link}
              to={linkHref}
              className={clsx('Link--inTextBlock', styles.PrimerLink)}
              data-testid="banner-link"
            >
              {linkText}
            </PrimerLink>
          )}
        </span>
        {dismissible && (
          // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
          <IconButton
            unsafeDisableTooltip
            aria-label="Hide this notice forever"
            size="small"
            variant="invisible"
            icon={XIcon}
            data-testid="banner-dismiss-button"
            onClick={handleDismiss}
            className={styles.IconButton}
          />
        )}
      </div>
    </Flash>
  )
}

export default Banner
