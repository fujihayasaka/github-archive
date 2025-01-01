import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {BookIcon, LinkExternalIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'

import {reactCoreExamplesLayoutRoute} from './layout-route'

export function ReactCoreExamplesIndex() {
  const {
    data: {login},
  } = useRouteQuery(reactCoreExamplesLayoutRoute, 'mainQuery')

  return (
    <Blankslate>
      <Blankslate.Visual>
        <BookIcon size="medium" />
      </Blankslate.Visual>
      <Blankslate.Heading>Welcome @{login}!</Blankslate.Heading>
      <Blankslate.Description>
        This is a collection of DataRouter recipes that provide common patterns for working with DataRouter in React
        applications. Explore these examples to learn how to handle routing, data fetching, and UI updates effectively
        in your React projects.
      </Blankslate.Description>
      <Blankslate.PrimaryAction
        href="https://github.com/github/github/blob/master/ui/packages/react-core/future/docs/data-router/01-introduction.md"
        /* @ts-expect-error - `target` is not a valid prop on `a` elements */
        target="_blank"
      >
        DataRouter Docs <LinkExternalIcon />
      </Blankslate.PrimaryAction>
    </Blankslate>
  )
}
