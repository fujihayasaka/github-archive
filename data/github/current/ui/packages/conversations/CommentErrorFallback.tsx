import {AlertIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'

export function CommentErrorFallback() {
  return (
    <div className={`position-relative`}>
      <Blankslate border>
        <Blankslate.Visual>
          <AlertIcon size={24} className="fgColor-muted mt-3 mb-3" />
        </Blankslate.Visual>
        <Blankslate.Heading>
          <strong>Comments cannot be loaded right now</strong>
        </Blankslate.Heading>
        <div className="mb-n2">
          <Blankslate.Description>Refresh the page or try again later</Blankslate.Description>
        </div>
        <Blankslate.SecondaryAction href="https://www.githubstatus.com/">GitHub status</Blankslate.SecondaryAction>
      </Blankslate>
    </div>
  )
}
