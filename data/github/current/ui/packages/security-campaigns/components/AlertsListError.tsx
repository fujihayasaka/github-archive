import {AlertIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'
import {BlankslateListItem} from './BlankslateListItem'

export function AlertsListError(): JSX.Element {
  return (
    <BlankslateListItem>
      <Blankslate.Visual>
        <AlertIcon size={'medium'} />
      </Blankslate.Visual>
      <Blankslate.Heading>An error has occurred.</Blankslate.Heading>
      <Blankslate.Description>Alert data could not be loaded right now.</Blankslate.Description>
    </BlankslateListItem>
  )
}
