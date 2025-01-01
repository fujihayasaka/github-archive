import {AlertIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'

export const ErrorState = ({message}: {message: string}): JSX.Element => {
  return (
    <div className="my-3">
      <Blankslate>
        <Blankslate.Visual>
          <AlertIcon size="medium" />
        </Blankslate.Visual>
        <Blankslate.Heading>An error has occurred.</Blankslate.Heading>
        <Blankslate.Description>{message}</Blankslate.Description>
      </Blankslate>
    </div>
  )
}
