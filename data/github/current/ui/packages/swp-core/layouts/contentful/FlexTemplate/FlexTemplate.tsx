import {ThemeProvider} from '@primer/react-brand'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import {FootnotesProvider} from '../../../components/contentful/ContentfulFootnotes/FootnotesContext'
import type {FlexPage} from '../../../schemas/contentful/contentTypes/flexTemplate'

import {FlexTemplateContent} from './FlexTemplateContent'

export type FlexTemplateProps = {
  page: FlexPage
}

export function FlexTemplate({page}: FlexTemplateProps) {
  const footnotesEnabled = isFeatureEnabled('contentful_lp_footnotes')

  return (
    <ThemeProvider
      colorMode={page.fields.settings?.fields.colorMode ?? 'light'}
      style={{backgroundColor: 'var(--brand-color-canvas-default)'}}
    >
      {footnotesEnabled ? (
        <FootnotesProvider>
          <FlexTemplateContent page={page} />
        </FootnotesProvider>
      ) : (
        <FlexTemplateContent page={page} />
      )}
    </ThemeProvider>
  )
}
