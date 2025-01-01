import {Grid, Section, Stack} from '@primer/react-brand'
import {clsx} from 'clsx'

import type {FlexSection} from '../../../schemas/contentful/contentTypes/flexSection'
import {ContentfulSectionIntro} from '../ContentfulSectionIntro/ContentfulSectionIntro'
import {ContentfulPillars} from '../ContentfulPillars/ContentfulPillars'
import {ContentfulFeaturedBento} from '../ContentfulFeaturedBento/ContentfulFeaturedBento'
import {ContentfulIntroStackedItems} from '../ContentfulIntroStackedItems/ContentfulIntroStackedItems'
import styles from './ContentfulFlexSection.module.css'
import {ContentfulCards} from '../ContentfulCards/ContentfulCards'
import {ContentfulLogoSuite} from '../ContentfulLogoSuite/ContentfulLogoSuite'
import {ContentfulProse} from '../ContentfulProse/ContentfulProse'
import {isRiverBreakout} from '../../../schemas/contentful/contentTypes/primerComponentRiverBreakout'
import {ContentfulRiverBreakout} from '../ContentfulRiverBreakout/ContentfulRiverBreakout'
import {ContentfulRiver} from '../ContentfulRiver/ContentfulRiver'
import {ContentfulStatistics} from '../ContentfulStatistics/ContentfulStatistics'
import type {PrimerComponentLogoSuite} from '../../../schemas/contentful/contentTypes/primerComponentLogoSuite'
import type {IntroStackedItems} from '../../../schemas/contentful/contentTypes/introStackedItems'
import type {PrimerComponentSectionIntro} from '../../../schemas/contentful/contentTypes/primerComponentSectionIntro'
import {FlexSectionTestimonials} from './FlexSectionTestimonials/FlexSectionTestimonials'
import {ContentfulBreakoutBanner} from '../ContentfulBreakoutBanner/ContentfulBreakoutBanner'
import {ContentfulPricingOptions} from '../ContentfulPricingOptions/ContentfulPricingOptions'

export type ContentfulFlexSectionProps = {
  component: FlexSection
  className?: string
}

export function ContentfulFlexSection({component, className}: ContentfulFlexSectionProps) {
  const {
    breakoutBanner,
    cards,
    featuredBento,
    id,
    introContent,
    logoSuite,
    pillars,
    prose,
    pricingOptions,
    rivers,
    statistics,
    testimonials,
    visualSettings,
  } = component.fields

  const {
    backgroundColor = 'default',
    paddingBlockStart = 'spacious',
    colorMode = 'inherit',
    paddingBlockEnd = 'spacious',
    roundedCorners = false,
    verticalGap = 'normal',
    backgroundImage,
    backgroundImagePosition,
    backgroundImageSize,
    testimonialBackgroundImageVariant,
  } = visualSettings?.fields ?? {}

  const colorModeAttributes = colorMode === 'dark' || colorMode === 'light' ? {'data-color-mode': colorMode} : {}

  return (
    <Section
      {...colorModeAttributes}
      className={`${className ? `${className} ` : ''}${styles.section}`}
      backgroundColor={backgroundColor}
      backgroundImageSrc={backgroundImage?.fields.file.url}
      backgroundImagePosition={backgroundImagePosition}
      backgroundImageSize={backgroundImageSize}
      paddingBlockStart={paddingBlockStart}
      paddingBlockEnd={paddingBlockEnd}
      rounded={roundedCorners}
      id={id}
    >
      <Stack padding="none" gap={verticalGap} direction="vertical">
        {introContent && (
          <>
            {introContent.sys.contentType.sys.id === 'introStackedItems' && (
              <ContentfulIntroStackedItems
                className={styles.normalizeMargin}
                component={introContent as IntroStackedItems}
              />
            )}

            {introContent.sys.contentType.sys.id === 'primerComponentSectionIntro' && (
              <Grid className={styles.sectionIntro}>
                <Grid.Column>
                  <ContentfulSectionIntro
                    className={styles.normalizePadding}
                    component={introContent as PrimerComponentSectionIntro}
                    headingSize="3"
                  />
                </Grid.Column>
              </Grid>
            )}
          </>
        )}

        {pillars && (
          <ContentfulPillars
            className={styles.normalizeMargin}
            component={pillars}
            pillarBgColor={backgroundColor === 'default' ? 'subtle' : 'default'}
            asCards
          />
        )}

        {logoSuite && <FlexSectionLogoSuite component={logoSuite} />}

        {cards && <ContentfulCards className={styles.normalizeMargin} component={cards} fullWidth />}

        {featuredBento && (
          <Grid className={styles.normalizeMargin}>
            <Grid.Column>
              <ContentfulFeaturedBento
                itemBgColor={backgroundColor === 'default' ? 'subtle' : 'default'}
                className={styles.normalizePadding}
                component={featuredBento}
              />
            </Grid.Column>
          </Grid>
        )}

        {prose && (
          <Grid className={styles.normalizeMargin}>
            <Grid.Column>
              <ContentfulProse component={prose} />
            </Grid.Column>
          </Grid>
        )}

        {rivers && rivers.length > 0 && (
          <Grid
            className={styles.normalizeMargin}
            style={{rowGap: verticalGap === 'spacious' ? 'var(--base-size-128)' : 'var(--base-size-80)'}}
          >
            {rivers.map(river => (
              <Grid.Column key={river.sys.id}>
                {isRiverBreakout(river) ? (
                  <ContentfulRiverBreakout
                    className={clsx(styles.normalizeMargin, styles.normalizePadding, {
                      [styles.riverBreakoutNoCta]: !river.fields.callToAction,
                    })}
                    component={river}
                  />
                ) : (
                  <ContentfulRiver
                    className={clsx(styles.normalizeMargin, styles.normalizePadding)}
                    component={river}
                  />
                )}
              </Grid.Column>
            ))}
          </Grid>
        )}

        {testimonials && testimonials.length > 0 && (
          <FlexSectionTestimonials
            testimonials={testimonials}
            backgroundImageVariant={testimonialBackgroundImageVariant}
            className={styles.normalizeMargin}
          />
        )}

        {breakoutBanner && (
          <Grid className={clsx(styles.normalizeMargin, 'mx-0')}>
            <Grid.Column>
              <ContentfulBreakoutBanner className={styles.normalizeMargin} component={breakoutBanner} />
            </Grid.Column>
          </Grid>
        )}

        {statistics && (
          <ContentfulStatistics
            className={styles.normalizeMargin}
            component={statistics}
            statisticBgColor={backgroundColor === 'default' ? 'subtle' : 'default'}
          />
        )}

        {pricingOptions && (
          <Grid className={clsx(styles.normalizeMargin, 'mx-0')}>
            <Grid.Column>
              <ContentfulPricingOptions component={pricingOptions} />
            </Grid.Column>
          </Grid>
        )}
      </Stack>
    </Section>
  )
}

export type FlexSectionLogoSuiteProps = {
  component: PrimerComponentLogoSuite
}

const FlexSectionLogoSuite = ({component}: FlexSectionLogoSuiteProps) => {
  const {hasDivider, heading, visuallyHideHeading, description} = component.fields

  const hasVisibleHeading = heading && !visuallyHideHeading

  return (
    <Grid className={clsx(styles.normalizeMargin, 'mx-0')}>
      <Grid.Column>
        <ContentfulLogoSuite
          className={!hasDivider ? styles.normalizePadding : undefined}
          logobarClassName={!hasVisibleHeading && !description ? styles.normalizePadding : undefined}
          component={component}
        />
      </Grid.Column>
    </Grid>
  )
}
