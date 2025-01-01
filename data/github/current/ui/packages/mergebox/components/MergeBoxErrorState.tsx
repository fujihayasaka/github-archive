import {AlertIcon, GitMergeIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'
import styles from './MergeBoxErrorState.module.css'
import {MergeabilityIcon} from './MergeabilityIcon'

export function MergeBoxErrorState({hideIcon}: {hideIcon?: boolean}) {
  return (
    <div className={`position-relative ${styles.boundaryContainer}`}>
      {!hideIcon && (
        <MergeabilityIcon
          icon={GitMergeIcon}
          ariaLabel="Merge status cannot be loaded"
          iconBackgroundColor="neutral.emphasis"
        />
      )}
      <Blankslate border>
        <Blankslate.Visual>
          <AlertIcon size={24} className="fgColor-muted mt-3 mb-3" />
        </Blankslate.Visual>
        <Blankslate.Heading>
          <strong>Merge status cannot be loaded</strong>
        </Blankslate.Heading>
        <div className="mb-n2">
          <Blankslate.Description>
            Try reloading the page, or if the problem persists{' '}
            <a className="fgColor-muted" href="https://support.github.com/">
              <u>contact support</u>
              {'.'}
            </a>
          </Blankslate.Description>
        </div>
        <Blankslate.SecondaryAction href="https://www.githubstatus.com/">GitHub status </Blankslate.SecondaryAction>
      </Blankslate>
    </div>
  )
}
