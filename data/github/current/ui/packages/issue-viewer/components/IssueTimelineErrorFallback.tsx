import {Blankslate} from '@primer/react/experimental'
import {AlertIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'

export function IssueTimelineErrorFallback(): JSX.Element {
  return (
    <Blankslate>
      <Blankslate.Visual>
        <AlertIcon size="medium" />
      </Blankslate.Visual>
      <Blankslate.Heading>Timeline cannot be loaded</Blankslate.Heading>
      <Blankslate.Description>
        The timeline is currently unavailable due to a system error. Try reloading the page.{' '}
        <Link inline href="https://support.github.com/contact">
          Contact support
        </Link>{' '}
        if the problem persists.
      </Blankslate.Description>
      <Blankslate.SecondaryAction href="https://www.githubstatus.com/">GitHub Status</Blankslate.SecondaryAction>
    </Blankslate>
  )
}
