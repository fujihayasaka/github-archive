import type {Icon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'

/**
 *
 * renders a simple blankslate to be used with markers in a side panel when there are no existing markers in a Pull Request
 */
export function ZeroState({heading, description, icon}: {heading: string; description: string; icon: Icon}) {
  const IconComponent = icon
  return (
    <Blankslate>
      <Blankslate.Visual>
        <IconComponent size="medium" />
      </Blankslate.Visual>
      <Blankslate.Heading>{heading}</Blankslate.Heading>
      <Blankslate.Description>{description}</Blankslate.Description>
    </Blankslate>
  )
}
