import resolveResponse from 'contentful-resolve-response'
import {AnimationProvider, Box, Grid, Stack, ThemeProvider, Image, Heading} from '@primer/react-brand'

import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ContentfulHero} from '@github-ui/swp-core/components/contentful/ContentfulHero'
import {ContentfulSectionIntro} from '@github-ui/swp-core/components/contentful/ContentfulSectionIntro'
import {ContentfulCards} from '@github-ui/swp-core/components/contentful/ContentfulCards'
import {ContentfulCtaBanner} from '@github-ui/swp-core/components/contentful/ContentfulCtaBanner'
import {ContentfulBackgroundImage} from '@github-ui/swp-core/components/contentful/ContentfulBackgroundImage'

import {StatisticsGroup} from '../../components/StatisticsGroup/StatisticsGroup'
import {toPayload} from '../../lib/types/payload'
import {toHomePage, toEntryCollection} from '../../lib/types/contentful'
import styles from './Newsroom.module.css'
import {Footnotes} from '../../components/Footnotes/Footnotes'

export function Newsroom() {
  const payload = toPayload(useRoutePayload<unknown>())
  const page = toHomePage(toEntryCollection(resolveResponse(payload.contentfulRawJsonResponse)).at(0))
  const template = page.fields.template

  const pageColorMode = page.fields.settings?.fields.colorMode ?? 'light'

  return (
    <ThemeProvider
      colorMode={pageColorMode}
      style={{
        backgroundColor: 'var(--brand-color-canvas-default)',
      }}
    >
      <ContentfulBackgroundImage component={template.fields.heroBackgroundImage}>
        <div className={styles.heroWrapper}>
          <ContentfulHero data-hpc component={template.fields.hero} />
        </div>
        {template.fields.heroStatistics && (
          <AnimationProvider runOnce>
            <StatisticsGroup statistics={template.fields.heroStatistics} position="hero" />
          </AnimationProvider>
        )}
      </ContentfulBackgroundImage>
      <div className={styles.articleContents}>
        <section className={styles.verticalOffset}>
          <Box
            paddingBlockStart={{narrow: 64, regular: 96}}
            paddingBlockEnd={64}
            className={styles.noBottomRadius}
            backgroundColor="default"
            borderRadius="xlarge"
          >
            <Grid>
              <Grid.Column>
                <Box marginBlockEnd={40}>
                  <ContentfulSectionIntro headingSize="3" component={template.fields.pressReleaseSectionIntro} />
                </Box>

                <Box
                  marginBlockEnd={{
                    narrow: 32,
                    regular: 32,
                    wide: 48,
                  }}
                >
                  <AnimationProvider runOnce visibilityOptions="bottom-of-screen">
                    <ContentfulCards
                      className={styles.cards}
                      fullWidth
                      animate="fade-in"
                      component={template.fields.pressReleaseSectionCards}
                    />
                  </AnimationProvider>
                </Box>
              </Grid.Column>
            </Grid>
          </Box>
        </section>
        <section>
          <Box
            backgroundColor="default"
            paddingBlockStart={{narrow: 'none', regular: 'none'}}
            paddingBlockEnd={64}
            borderRadius="xlarge"
            className={styles.noBottomRadius}
          >
            <Grid className={styles.bottomSeparator}>
              <Grid.Column>
                <Box marginBlockEnd={40} className={styles.reportsHeadingWrapper}>
                  <ContentfulSectionIntro headingSize="3" component={template.fields.reportsSectionIntro} />
                </Box>
                <Box
                  marginBlockEnd={{
                    narrow: 64,
                    regular: 64,
                    wide: 80,
                  }}
                >
                  <AnimationProvider runOnce visibilityOptions="bottom-of-screen">
                    <ContentfulCards
                      fullWidth
                      className={styles.cards}
                      spanOpts={{medium: 4}}
                      hasBorder
                      imageAspectRatio={'16:9'}
                      animate="fade-in"
                      component={template.fields.reportsSectionCards}
                    />
                  </AnimationProvider>
                </Box>
                {template.fields.reportsSectionStatistics && (
                  <AnimationProvider runOnce visibilityOptions="bottom-of-screen">
                    {template.fields.reportsStatisticsHeading && (
                      <Heading as="h3" size="6" className={styles.reportsStatisticsHeading}>
                        {template.fields.reportsStatisticsHeading}
                      </Heading>
                    )}
                    <StatisticsGroup statistics={template.fields.reportsSectionStatistics} position="body" />
                  </AnimationProvider>
                )}
              </Grid.Column>
            </Grid>
          </Box>
        </section>
        <section className={styles.verticalOffset}>
          <Box
            backgroundColor="default"
            paddingBlockStart={{narrow: 64, regular: 96}}
            paddingBlockEnd={64}
            borderRadius="xlarge"
            className={styles.noBottomRadius}
          >
            <Grid className={styles.bottomSeparator}>
              <Grid.Column>
                <Box marginBlockEnd={40}>
                  <ContentfulSectionIntro headingSize="3" component={template.fields.inTheNewsSectionIntro} />
                </Box>
                <Box
                  marginBlockEnd={{
                    narrow: 64,
                    regular: 64,
                    wide: 112,
                  }}
                >
                  <AnimationProvider runOnce visibilityOptions="bottom-of-screen">
                    <ContentfulCards
                      className={styles.cards}
                      spanOpts={{medium: 4}}
                      hasBorder
                      fullWidth
                      animate="fade-in"
                      component={template.fields.inTheNewsSectionCards}
                    />
                  </AnimationProvider>
                </Box>
                {template.fields.featuredCustomerStories && template.fields.customerStoriesSectionIntro ? (
                  <Stack direction="vertical" padding="none" alignItems="center" gap={64}>
                    <ContentfulSectionIntro headingSize="3" component={template.fields.customerStoriesSectionIntro} />
                    <Box
                      className={styles.portalCustomerCards}
                      marginBlockEnd={{
                        narrow: 64,
                        regular: 64,
                        wide: 128,
                      }}
                    >
                      <ContentfulCards
                        spanOpts={{medium: 4}}
                        component={template.fields.featuredCustomerStories}
                        imageAspectRatio="1:1"
                        fullWidth
                      />
                    </Box>
                  </Stack>
                ) : null}
              </Grid.Column>
            </Grid>
          </Box>
        </section>
        <section className={styles.verticalOffset}>
          <ThemeProvider colorMode="dark" style={{backgroundColor: 'transparent'}}>
            <Box
              backgroundColor="default"
              borderRadius="xlarge"
              className={styles.noBottomRadius}
              paddingBlockStart={{narrow: 64, regular: 96}}
              paddingBlockEnd={{narrow: 64, regular: 112}}
            >
              {(template.fields.ctaSectionHeading || template.fields.ctaSectionImage) && (
                <Grid>
                  <Grid.Column>
                    <Stack direction="vertical" className={styles.ctaSectionHero}>
                      {template.fields.ctaSectionImage && (
                        <Image
                          className={styles.ctaSectionImage}
                          src={template.fields.ctaSectionImage.fields.file.url}
                          alt={template.fields.ctaSectionImage.fields.description || 'Github section heading graphic'}
                        />
                      )}
                      {template.fields.ctaSectionHeading && (
                        <Heading as="h3" size="2" className={styles.ctaSectionHeading}>
                          {template.fields.ctaSectionHeading}
                        </Heading>
                      )}
                    </Stack>
                  </Grid.Column>
                </Grid>
              )}
              {template.fields.ctaSectionCards && (
                <Box
                  paddingBlockStart={{narrow: 64, regular: 64}}
                  paddingBlockEnd={{narrow: 64, regular: 48}}
                  className={styles.noBottomRadius}
                >
                  <AnimationProvider runOnce visibilityOptions="bottom-of-screen">
                    <ContentfulCards
                      className={styles.cards}
                      fullWidth
                      animate="fade-in"
                      component={template.fields.ctaSectionCards}
                    />
                  </AnimationProvider>
                </Box>
              )}
              <Grid>
                <Grid.Column>
                  <ContentfulCtaBanner
                    component={template.fields.ctaBanner}
                    backgroundImage={template.fields.ctaBannerBackgroundImage?.fields.file.url}
                  />
                </Grid.Column>
                <Footnotes staticFootnotes={template.fields.staticFootnotes} />
              </Grid>
            </Box>
          </ThemeProvider>
        </section>
      </div>
    </ThemeProvider>
  )
}
