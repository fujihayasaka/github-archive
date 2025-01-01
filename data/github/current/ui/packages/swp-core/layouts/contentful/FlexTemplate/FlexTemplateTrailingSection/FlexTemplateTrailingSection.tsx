import {Section, Grid, Box, Stack} from '@primer/react-brand'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import type {FlexPage} from '../../../../schemas/contentful/contentTypes/flexTemplate'
import {ContentfulCtaBanner} from '../../../../components/contentful/ContentfulCtaBanner/ContentfulCtaBanner'
import {ContentfulCards} from '../../../../components/contentful/ContentfulCards/ContentfulCards'
import {ContentfulFaqGroup} from '../../../../components/contentful/ContentfulFaqGroup/ContentfulFaqGroup'
import {ContentfulSectionIntro} from '../../../../components/contentful/ContentfulSectionIntro/ContentfulSectionIntro'
import {ContentfulInlineFootnotesList} from '../../../../components/contentful/ContentfulFootnotes/ContentfulInlineFootnotesList'
import {ContentfulStaticFootnotes} from '../../../../components/contentful/ContentfulFootnotes/ContentfulStaticFootnotes'

import {useFootnotes} from '../../../../components/contentful/ContentfulFootnotes/FootnotesContext'

import styles from './FlexTemplateTrailingSection.module.css'

export function FlexTemplateTrailingSection({page}: {page: FlexPage}) {
  const {template} = page.fields
  const {ctaBanner, faq, cards, sectionIntro, staticFootnotes, visualSettings} = template.fields

  const trailingSectionBackgroundColor = visualSettings?.fields.trailingSectionBackgroundColor || 'default'
  const shouldTrailingSectionHaveFade = ctaBanner?.fields.hasShadow
  const trailingSectionBackgroundFade = shouldTrailingSectionHaveFade
    ? `linear-gradient(transparent, var(--brand-color-canvas-${trailingSectionBackgroundColor}) 20%)`
    : undefined

  const footnotesEnabled = isFeatureEnabled('contentful_lp_footnotes')
  const footnotesContext = useFootnotes()
  const hasInlineFootnotes = footnotesEnabled && footnotesContext?.footnotes && footnotesContext.footnotes.length > 0
  const hasAnyFootnotes = footnotesEnabled && (hasInlineFootnotes || !!staticFootnotes)

  return (
    <Section
      backgroundColor={trailingSectionBackgroundColor}
      paddingBlockStart="spacious"
      paddingBlockEnd="spacious"
      rounded={visualSettings?.fields.trailingSectionRoundedCorners}
      style={{background: trailingSectionBackgroundFade}}
      className={styles.trailingSection}
    >
      <Grid className={styles.trailingSectionGrid}>
        {ctaBanner && (
          <Grid.Column>
            <ContentfulCtaBanner component={ctaBanner} />
            {cards?.fields.cards && (
              <Box className={styles.ctaCards}>
                {sectionIntro && <ContentfulSectionIntro component={sectionIntro} className={styles.ctaSectionIntro} />}
                <ContentfulCards cards={cards.fields.cards} fullWidth />
              </Box>
            )}
          </Grid.Column>
        )}
        {faq && (
          <Grid.Column>
            <ContentfulFaqGroup component={faq} />
          </Grid.Column>
        )}
        {hasAnyFootnotes && (
          <Grid.Column>
            <Stack gap={24} padding="none">
              {hasInlineFootnotes && <ContentfulInlineFootnotesList className="py-0" />}
              {staticFootnotes && <ContentfulStaticFootnotes component={staticFootnotes} className="py-0" />}
            </Stack>
          </Grid.Column>
        )}
      </Grid>
    </Section>
  )
}
