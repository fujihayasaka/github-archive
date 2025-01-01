/**
 * Extended from @primer/react story-helpers, adds css variable `data` properties to
 * ensure correct themes are applied for non-react elements
 */
import type {Decorator} from '@storybook/react'

export const WithA11yLinkUnderline: Decorator = (
  Story,
  context,
) => {
  return (
    <div data-a11y-link-underlines={context.globals.linkUnderlines === 'off' ? 'false' : 'true'}>{Story(context)}</div>
  )
}
