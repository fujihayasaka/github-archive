import {AlertIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import styles from './RepositoryMilestone.module.css'

type MilestoneErrorProps = {
  title: string
  message: string
}

export const MilestoneError = ({title, message}: MilestoneErrorProps) => (
  <div className={styles.errorFallbackContainer}>
    <Blankslate>
      <Blankslate.Visual>
        <AlertIcon size="medium" />
      </Blankslate.Visual>
      <Blankslate.Heading>{title}</Blankslate.Heading>
      <Blankslate.Description>
        {message} Try reloading the page, or if the problem persists{' '}
        <Link href="https://support.github.com/" inline>
          contact support
        </Link>
      </Blankslate.Description>
    </Blankslate>
    <Link href={'https://www.githubstatus.com/'}>GitHub Status</Link>
  </div>
)
