import type React from 'react'
import {FootnotesProvider} from '@github-ui/swp-core/components/contentful/FootnotesContext'
import {isFeatureEnabled} from '@github-ui/feature-flags'

/**
 * The App component is used to render content which should be present on _all_ routes within this app
 */
export function App(props: {children?: React.ReactNode}) {
  const footnotesEnabled = isFeatureEnabled('contentful_lp_footnotes')
  if (footnotesEnabled) {
    return <FootnotesProvider>{props.children}</FootnotesProvider>
  }

  return <>{props.children}</>
}
