import type React from 'react'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {ThemeProvider} from '@primer/react-brand'
import {FootnotesProvider} from '@github-ui/swp-core/components/contentful/FootnotesContext'
import {isFeatureEnabled} from '@github-ui/feature-flags'

/**
 * The App component is used to render content which should be present on _all_ routes within this app
 */
export function App(props: {children?: React.ReactNode}) {
  const footnotesEnabled = isFeatureEnabled('contentful_lp_footnotes')

  if (footnotesEnabled) {
    return (
      <ErrorBoundary>
        <ThemeProvider dir="ltr">
          <FootnotesProvider>{props.children}</FootnotesProvider>
        </ThemeProvider>
      </ErrorBoundary>
    )
  }

  return (
    <ErrorBoundary>
      <ThemeProvider dir="ltr">{props.children}</ThemeProvider>
    </ErrorBoundary>
  )
}
