import {ContentfulBackgroundImage} from '../../../components/contentful/ContentfulBackgroundImage/ContentfulBackgroundImage'
import {ContentfulCtaBanner} from '../../../components/contentful/ContentfulCtaBanner/ContentfulCtaBanner'
import {ContentfulCards} from '../../../components/contentful/ContentfulCards/ContentfulCards'
import {ContentfulFaqGroup} from '../../../components/contentful/ContentfulFaqGroup/ContentfulFaqGroup'
import {ContentfulFlexSection} from '../../../components/contentful/ContentfulFlexSection/ContentfulFlexSection'
import {ContentfulHero} from '../../../components/contentful/ContentfulHero/ContentfulHero'
import {ContentfulBreadcrumbs} from '../../../components/contentful/ContentfulBreadcrumbs/ContentfulBreadcrumbs'
import {ContentfulSubnav} from '../../../components/contentful/ContentfulSubnav/ContentfulSubnav'
import {Section, Box, Grid, ThemeProvider} from '@primer/react-brand'
import styles from './FlexTemplate.module.css'

import type {FlexPage} from '../../../schemas/contentful/contentTypes/flexTemplate'
import {ContentfulSectionIntro} from '../../../components/contentful/ContentfulSectionIntro/ContentfulSectionIntro'

export type FlexTemplateProps = {
  page: FlexPage
}

export function FlexTemplate({page}: FlexTemplateProps) {
  const {template} = page.fields

  const {
    breadcrumbs,
    hero,
    heroBackgroundImage,
    subnav,
    sections,
    ctaBanner,
    sectionIntro,
    cards,
    faq,
    trailingSectionRoundedCorners = false,
    trailingSectionBackgroundColor = 'default',
  } = template.fields

  const subNavColorMode = heroBackgroundImage?.fields.colorMode || page.fields.settings?.fields.colorMode
  const hasBackgroundImage = !!heroBackgroundImage
  const hasSubnav = !!subnav
  const hasTrailingSection = ctaBanner || faq

  const shouldTrailingSectionHaveFade = ctaBanner?.fields.hasShadow
  const trailingSectionBackgroundFade = shouldTrailingSectionHaveFade
    ? `linear-gradient(transparent, var(--brand-color-canvas-${trailingSectionBackgroundColor}) 20%)`
    : undefined

  return (
    <ThemeProvider
      colorMode={page.fields.settings?.fields.colorMode ?? 'light'}
      style={{backgroundColor: 'var(--brand-color-canvas-default)'}}
    >
      {subnav && (
        <ContentfulSubnav
          className={styles.subNav}
          component={subnav}
          data-color-mode={subNavColorMode}
          hasShadow
          linkVariant="default"
        />
      )}

      <Grid>
        <Grid.Column>
          <ContentfulBackgroundImage component={heroBackgroundImage}>
            <Box
              paddingBlockStart={hasBackgroundImage && hasSubnav ? 64 : undefined}
              paddingBlockEnd={hasBackgroundImage && hasSubnav ? 64 : undefined}
            >
              {breadcrumbs && (
                <Box paddingBlockStart={hasBackgroundImage && hasSubnav ? 16 : hasSubnav ? 80 : 32}>
                  <ContentfulBreadcrumbs breadcrumbs={breadcrumbs} />
                </Box>
              )}
              <ContentfulHero data-hpc component={hero} />
            </Box>
          </ContentfulBackgroundImage>
        </Grid.Column>
      </Grid>

      {sections.map(section => (
        <ContentfulFlexSection key={section.sys.id} component={section} className={styles.section} />
      ))}

      {hasTrailingSection && (
        <Section
          backgroundColor={trailingSectionBackgroundColor}
          paddingBlockStart="spacious"
          paddingBlockEnd="spacious"
          rounded={trailingSectionRoundedCorners}
          style={{background: trailingSectionBackgroundFade}}
          className={styles.section}
        >
          <Grid className={styles.trailingSectionGrid}>
            {ctaBanner && (
              <Grid.Column>
                <ContentfulCtaBanner component={ctaBanner} />
                {cards?.fields.cards && (
                  <Box className={styles.ctaCards}>
                    {sectionIntro && (
                      <ContentfulSectionIntro component={sectionIntro} className={styles.ctaSectionIntro} />
                    )}
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
          </Grid>
        </Section>
      )}
    </ThemeProvider>
  )
}
