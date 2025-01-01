import {verifiedFetch} from '@github-ui/verified-fetch'
import {XIcon} from '@primer/octicons-react'
import {Flash, IconButton, LinkButton} from '@primer/react'

import {useState} from 'react'
import LinkButtonCSS from '../css/LinkButton.module.css'

import styles from './PublishBanners.module.css'
import {clsx} from 'clsx'

export default function PublishBanners({
  showPublishActionBanner,
  releasePath,
  dismissActionNoticePath,
  className,
}: {
  showPublishActionBanner: boolean
  releasePath: string
  dismissActionNoticePath: string
  className?: string
}) {
  const [hidden, setHidden] = useState(false)

  const onDismissPublishAction = () => {
    verifiedFetch(dismissActionNoticePath, {method: 'POST'})
    setHidden(true)
  }

  return showPublishActionBanner ? (
    <Flash hidden={hidden} className={clsx(className, styles.Flash)}>
      {showPublishActionBanner && <div className="flex-1">You can publish this Action to the GitHub Marketplace</div>}
      <LinkButton href={releasePath} className={clsx(LinkButtonCSS['code-view-link-button'], 'f6 mr-2')}>
        Draft a release
      </LinkButton>
      <IconButton
        icon={XIcon}
        tooltipDirection="s"
        aria-label="Dismiss"
        className="bgColor-transparent border-0 pr-0"
        onClick={showPublishActionBanner ? onDismissPublishAction : () => {}}
      />
    </Flash>
  ) : null
}
