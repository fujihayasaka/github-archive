import {ContentfulBackgroundImage} from '@github-ui/swp-core/components/contentful/ContentfulBackgroundImage'
import {ContentfulCtaBanner} from '@github-ui/swp-core/components/contentful/ContentfulCtaBanner'
import {ContentfulFaqGroup} from '@github-ui/swp-core/components/contentful/ContentfulFaqGroup'
import {ContentfulFlexSection} from '@github-ui/swp-core/components/contentful/ContentfulFlexSection'
import {ContentfulHero} from '@github-ui/swp-core/components/contentful/ContentfulHero'
import {ContentfulBreadcrumbs} from '@github-ui/swp-core/components/contentful/ContentfulBreadcrumbs'
import {ContentfulSubnav} from '@github-ui/swp-core/components/contentful/ContentfulSubnav'
import {Section, Box, Grid, ThemeProvider} from '@primer/react-brand'
import styles from './FlexTemplate.module.css'

import type {FlexPage} from '../../../schemas/contentful/contentTypes/flexTemplate'

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
        <ContentfulSubnav className={styles.subNav} component={subnav} data-color-mode={subNavColorMode} hasShadow />
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
