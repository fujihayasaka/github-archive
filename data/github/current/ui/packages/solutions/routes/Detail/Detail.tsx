import resolveResponse from 'contentful-resolve-response'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ssrSafeLocation} from '@github-ui/ssr-utils'

import {toPayload} from '../../lib/types/payload'
import {toDetailPage, toEntryCollection} from '../../lib/types/contentful'
import {ThemeProvider, AnimationProvider, Box, Grid, Heading, Stack, Breadcrumbs} from '@primer/react-brand'
import {ContentfulHero} from '@github-ui/swp-core/components/contentful/ContentfulHero'
import {ContentfulLogoSuite} from '@github-ui/swp-core/components/contentful/ContentfulLogoSuite'
import {ContentfulRiver} from '@github-ui/swp-core/components/contentful/ContentfulRiver'
import {ContentfulStatistic} from '@github-ui/swp-core/components/contentful/ContentfulStatistic'
import {ContentfulBreakoutBanner} from '@github-ui/swp-core/components/contentful/ContentfulBreakoutBanner'
import {ContentfulTestimonial} from '@github-ui/swp-core/components/contentful/ContentfulTestimonial'
import {ContentfulIntroPillars} from '@github-ui/swp-core/components/contentful/ContentfulIntroPillars'
import type {IntroPillars as IntroPillarsType} from '@github-ui/swp-core/schemas/contentful/contentTypes/introPillars'
import type {IntroStackedItems as IntroStackedItemsType} from '@github-ui/swp-core/schemas/contentful/contentTypes/introStackedItems'
import {ContentfulCtaBanner} from '@github-ui/swp-core/components/contentful/ContentfulCtaBanner'
import {ArticleSeoSchema} from '@github-ui/swp-core/components/structuredData/ArticleSeoSchema'
import {BreadcrumbSeoSchema} from '@github-ui/swp-core/components/structuredData/BreadcrumbSeoSchema'

import styles from './Detail.module.css'
import {ContentfulIntroStackedItems} from '@github-ui/swp-core/components/contentful/ContentfulIntroStackedItems'
import {ContentfulCards} from '@github-ui/swp-core/components/contentful/ContentfulCards'
import {ContentfulFaqGroup} from '@github-ui/swp-core/components/contentful/ContentfulFaqGroup'
import {ContentfulFeaturedBento} from '@github-ui/swp-core/components/contentful/ContentfulFeaturedBento'
import {SolutionsBreadcrumb, CategoryBreadcrumbs, isCategory} from '../../lib/types/breadcrumbs'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import {appendFeatureFlagsToUrl} from '../../lib/utils'
import {Footnotes} from '../../components/Footnotes/Footnotes'

export function Detail() {
  const payload = toPayload(useRoutePayload<unknown>())
  const page = toDetailPage(toEntryCollection(resolveResponse(payload.contentfulRawJsonResponse)).at(0))
  const {template, settings, path} = page.fields
  const templateColorMode = settings?.fields.colorMode ?? 'light'

  const urlParts = page.fields.path.split('/')
  const categoryName = urlParts[2] || ''
  if (!isCategory(categoryName)) {
    throw new Error(`Invalid Category: ${categoryName}`)
  }
  const category = CategoryBreadcrumbs[categoryName]
  const queryParams = new URLSearchParams(ssrSafeLocation.search)
  const featureFlags = queryParams.get('_features') || ''

  const breadcrumbs = [
    {
      name: SolutionsBreadcrumb.label,
      url: appendFeatureFlagsToUrl(SolutionsBreadcrumb.url, featureFlags),
    },
    {
      name: category.label,
      url: appendFeatureFlagsToUrl(`${SolutionsBreadcrumb.url}${category.url}`, featureFlags),
    },
  ]

  return (
    <ThemeProvider
      colorMode={templateColorMode}
      dir="ltr"
      style={{
        backgroundColor: 'var(--brand-color-canvas-default)',
      }}
    >
      <AnimationProvider runOnce visibilityOptions={0.2}>
        <section>
          <Box className={styles.hideHorizontalOverflow}>
            <Grid
              className={
                template.fields.hero.fields.videoSrc !== undefined && path.includes('industry')
                  ? `${styles.heroVideoGlow} ${styles.relative}`
                  : styles.relative
              }
            >
              <Grid.Column>
                <Box marginBlockStart={20}>
                  <Breadcrumbs>
                    {breadcrumbs.map(({name, url}, index) => (
                      <Breadcrumbs.Item
                        // eslint-disable-next-line @eslint-react/no-array-index-key
                        key={`breadcrumb-${index}`}
                        href={url}
                        {...getAnalyticsEvent({
                          action: name,
                          tag: 'link',
                          context: 'breadcrumb',
                          location: 'header',
                        })}
                      >
                        {name}
                      </Breadcrumbs.Item>
                    ))}
                  </Breadcrumbs>
                </Box>
                <ContentfulHero component={template.fields.hero} />
              </Grid.Column>
            </Grid>
          </Box>
        </section>

        <div className={styles.relative}>
          <Grid>
            <Grid.Column>
              <section>
                <Box paddingBlockEnd={template.fields.logoSuite ? 64 : undefined}>
                  {template.fields.introSectionContent.sys.contentType.sys.id === 'introPillars' && (
                    <ContentfulIntroPillars component={template.fields.introSectionContent as IntroPillarsType} />
                  )}
                  {template.fields.introSectionContent.sys.contentType.sys.id === 'introStackedItems' && (
                    <ContentfulIntroStackedItems
                      component={template.fields.introSectionContent as IntroStackedItemsType}
                    />
                  )}
                </Box>

                {template.fields.logoSuite && (
                  <Box paddingBlockEnd={36} borderBlockEndWidth={'thin'} borderColor={'muted'} borderStyle={'solid'}>
                    <ContentfulLogoSuite component={template.fields.logoSuite} shouldAnimate />
                  </Box>
                )}
              </section>
            </Grid.Column>
          </Grid>
          <Grid style={{marginBlockStart: '80px'}}>
            <Grid.Column>
              {template.fields.featuresSectionRivers && (
                <Box paddingBlockEnd={80}>
                  {template.fields.featuresSectionRivers?.map(river => (
                    <ContentfulRiver
                      key={river.sys.id}
                      component={river}
                      linkProps={{variant: categoryName === 'industry' ? 'accent' : 'default'}}
                    />
                  ))}
                </Box>
              )}
              {template.fields.statistics && (
                <Box paddingBlockEnd={128} animate="fade-in">
                  <Stack
                    direction={{narrow: 'vertical', regular: 'horizontal'}}
                    gap={48}
                    padding="none"
                    justifyContent="space-between"
                  >
                    {template.fields.statistics.map(statistic => (
                      <ContentfulStatistic key={statistic.sys.id} component={statistic} className={styles.statistic} />
                    ))}
                  </Stack>
                </Box>
              )}
              {template.fields.featuredCustomerBento && (
                <ContentfulFeaturedBento component={template.fields.featuredCustomerBento} itemBgColor="subtle" />
              )}
              {template.fields.breakoutBanner && (
                <ContentfulBreakoutBanner
                  component={template.fields.breakoutBanner}
                  backgroundImagePosition={{
                    narrow: 'bottom -167px right -70px',
                    regular: 'bottom 35% right 57%',
                    wide: 'bottom 35% right 57%',
                  }}
                  backgroundImageSize={{
                    narrow: '680px',
                    regular: '140%',
                    wide: '140%',
                  }}
                />
              )}
              {template.fields.featuredCustomerStories && (
                <Stack
                  direction="vertical"
                  padding="none"
                  gap={64}
                  alignItems="center"
                  style={{marginBlockEnd: '128px'}}
                >
                  {template.fields.customerStoriesSectionHeadline && (
                    <Heading as="h3" size="3">
                      {template.fields.customerStoriesSectionHeadline}
                    </Heading>
                  )}
                  <ContentfulCards component={template.fields.featuredCustomerStories} />
                </Stack>
              )}
            </Grid.Column>
          </Grid>
          <div>
            <ThemeProvider colorMode="dark">
              <Box
                backgroundColor="default"
                paddingBlockStart={128}
                paddingBlockEnd={112}
                className={styles.noBottomRadius}
                borderRadius={templateColorMode === 'light' ? 'xlarge' : undefined}
              >
                <Grid>
                  <Grid.Column>
                    <Stack direction="vertical" gap={{narrow: 64, regular: 112}} padding="none">
                      {template.fields.testimonial && (
                        <Grid>
                          <Grid.Column span={{medium: 10}} start={{medium: 2}}>
                            <ContentfulTestimonial component={template.fields.testimonial} quoteMarkColor="pink" />
                          </Grid.Column>
                        </Grid>
                      )}
                      {template.fields.ctaBanner && (
                        <ContentfulCtaBanner component={template.fields.ctaBanner} className={styles.ctaBanner} />
                      )}
                      {template.fields.resources && (
                        <Stack direction="vertical" padding="none" gap={64} alignItems="center">
                          {template.fields.furtherReadingSectionHeadline && (
                            <Heading as="h3" size="3">
                              {template.fields.furtherReadingSectionHeadline}
                            </Heading>
                          )}
                          <ContentfulCards component={template.fields.resources} />
                        </Stack>
                      )}
                      {template.fields.faq && <ContentfulFaqGroup component={template.fields.faq} />}
                    </Stack>
                  </Grid.Column>
                  <Footnotes staticFootnotes={template.fields.staticFootnotes} />
                </Grid>
              </Box>
            </ThemeProvider>
          </div>
        </div>
      </AnimationProvider>
      <ArticleSeoSchema title={page.fields.title} imageUrl={template.fields.hero.fields.image?.fields.file.url} />
      <BreadcrumbSeoSchema items={breadcrumbs} />
    </ThemeProvider>
  )
}
