import type {Decorator} from '@storybook/react'

export const withAriaLive: Decorator = (Story, context) => {
  return (
    <div>
     <div id="js-global-screen-reader-notice" data-testid="sr-polite" className="sr-only" aria-live="polite" />
     <div id="js-global-screen-reader-notice-assertive" data-testid="sr-assertive" className="sr-only" aria-live="assertive" />
      {Story(context)}
    </div>
  )
}
