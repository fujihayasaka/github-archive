import {AlertIcon} from '@primer/octicons-react'
import {Tooltip} from '@primer/react/deprecated'

export function HiddenUnicodeAlert() {
  return (
    <Tooltip direction="n" text="This line has hidden Unicode characters">
      <AlertIcon className="mr-2" />
    </Tooltip>
  )
}
