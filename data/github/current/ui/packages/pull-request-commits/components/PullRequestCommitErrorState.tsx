import {AlertIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'

export function PullRequestCommitErrorState() {
  return (
    <div>
      <Blankslate border={false} spacious={false}>
        <Blankslate.Visual>
          <AlertIcon size="medium" className="mb-2 fgColor-muted" />
        </Blankslate.Visual>
        <Blankslate.Heading>{'Unable to load page.'}</Blankslate.Heading>
        <Blankslate.Description>
          <p className="d-flex flex-justify-center mt-2">{'The page is unavailable due to a system error.'}</p>
          <p className="d-flex flex-justify-center mt-2">
            {' Try reloading the page, or if the problem persists, contact support.'}
          </p>
          <p className="d-flex flex-justify-center mt-2">
            <a href={'https://www.githubstatus.com'}>{'GitHub status'}</a>
          </p>
        </Blankslate.Description>
      </Blankslate>
    </div>
  )
}
