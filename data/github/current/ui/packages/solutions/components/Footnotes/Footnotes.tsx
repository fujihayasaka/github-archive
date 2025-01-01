import {Grid, Stack} from '@primer/react-brand'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {useFootnotes} from '@github-ui/swp-core/components/contentful/FootnotesContext'
import {ContentfulInlineFootnotesList} from '@github-ui/swp-core/components/contentful/ContentfulInlineFootnotesList'
import {ContentfulStaticFootnotes} from '@github-ui/swp-core/components/contentful/ContentfulStaticFootnotes'
import type {PrimerComponentStaticFootnotes} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentStaticFootnotes'

import styles from './Footnotes.module.css'

type FootnotesProps = {
  staticFootnotes?: PrimerComponentStaticFootnotes
}

export function Footnotes({staticFootnotes}: FootnotesProps) {
  const footnotesEnabled = isFeatureEnabled('contentful_lp_footnotes')
  const footnotesContext = useFootnotes()
  const hasInlineFootnotes = footnotesEnabled && footnotesContext?.footnotes && footnotesContext.footnotes.length > 0
  const hasAnyFootnotes = footnotesEnabled && (hasInlineFootnotes || !!staticFootnotes)

  if (!hasAnyFootnotes) return null

  return (
    <Grid.Column>
      <Stack gap={24} className={styles.footnotes}>
        {hasInlineFootnotes && <ContentfulInlineFootnotesList className="py-0" />}
        {staticFootnotes && <ContentfulStaticFootnotes component={staticFootnotes} className="py-0" />}
      </Stack>
    </Grid.Column>
  )
}
