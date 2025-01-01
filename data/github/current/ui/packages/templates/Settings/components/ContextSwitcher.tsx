import {IconButton, Heading} from '@primer/react'
import {Tooltip} from '@primer/react/deprecated'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {ArrowSwitchIcon} from '@primer/octicons-react'

import styles from './ContextSwitcher.module.css'

interface ContextSwitcherProps {
  title: string
  subtitle: string
}

const ContextSwitcher = ({title, subtitle}: ContextSwitcherProps) => {
  return (
    <div className={styles.Box}>
      <GitHubAvatar src="https://avatars.githubusercontent.com/u/9919?s=200&v=4" size={40} />
      <div className={styles.Box_1}>
        <Heading as="h2" className="h5" id="context-name">
          {title}
          <span className="d-block fgColor-muted f5 text-normal">{subtitle}</span>
        </Heading>
      </div>
      <div className={styles.Box_2}>
        <Tooltip text="Switch settings context" noDelay direction="s">
          {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
          <IconButton
            unsafeDisableTooltip
            icon={ArrowSwitchIcon}
            aria-label="Switch settings context"
            className={styles.IconButton}
          />
        </Tooltip>
      </div>
    </div>
  )
}

export default ContextSwitcher
