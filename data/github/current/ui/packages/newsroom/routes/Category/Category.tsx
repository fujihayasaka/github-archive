import resolveResponse from 'contentful-resolve-response'
import {useMemo} from 'react'

import {AnimationProvider, Box, Grid, Link, Pagination, Stack, ThemeProvider} from '@primer/react-brand'

import {BreadcrumbSeoSchema} from '@github-ui/swp-core/components/structuredData/BreadcrumbSeoSchema'
import {ContentfulCtaBanner} from '@github-ui/swp-core/components/contentful/ContentfulCtaBanner'
import {ContentfulHero} from '@github-ui/swp-core/components/contentful/ContentfulHero'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {toArticlePage, type ArticlePageContainer} from '@github-ui/resources/types'

import {
  toCategoryPage,
  toContainerPage,
  toEntryCollection,
  type CategoryPageContainer,
} from '../../lib/types/contentful'
import {toPayload} from '../../lib/types/payload'
import {replacePageNumberInUrl, appendFeatureFlagsToUrl} from '../../lib/utils'
import type {CategoryCard} from '../../lib/types/categoryCard'

import {CategoryCards} from '../../components/CategoryCards/CategoryCards'
import {GlowBackground} from './GlowBackground'
import styles from './Category.module.css'
import {Footnotes} from '../../components/Footnotes/Footnotes'

const formatPressReleaseForCard = (pressRelease: ArticlePageContainer): CategoryCard => {
  return {
    href: pressRelease.fields.path,
    heading: pressRelease.fields.title,
    publishedDate: pressRelease.fields.template.fields.publishedDate,
    ctaText: 'Read',
  }
}

export function CategoryPage() {
  const {contentfulRawJsonResponse, additionalProps} = toPayload(useRoutePayload<unknown>())

  const {cards, page} = useMemo(() => {
    const mappedCards: CategoryCard[] = []
    let mappedPage: CategoryPageContainer | undefined

    for (const entry of toEntryCollection(resolveResponse(contentfulRawJsonResponse))) {
      const containerPage = toContainerPage(entry)

      if (containerPage.fields.template.sys.contentType.sys.id === 'newsroomTemplateCategory') {
        mappedPage = toCategoryPage(containerPage)
      } else {
        mappedCards.push(formatPressReleaseForCard(toArticlePage(containerPage)))
      }
    }

    return {cards: mappedCards, page: mappedPage}
  }, [contentfulRawJsonResponse])

  if (!page) {
    // eslint-disable-next-line react-hooks/react-compiler
    ssrSafeLocation.href = '/newsroom'
    return
  }

  const {ctaBanner, hero, staticFootnotes} = page.fields.template.fields
  const pageColorMode = page.fields.settings?.fields.colorMode ?? 'light'

  const url = new URL(page.fields.path, ssrSafeLocation.origin)
  const urlParts = url.pathname.split('/')
  const queryParams = new URLSearchParams(ssrSafeLocation.search)
  const featureFlags = queryParams.get('_features') || ''

  const breadcrumbListItems = [
    {
      name: 'Newsroom',
      url: appendFeatureFlagsToUrl(`/${urlParts[1]}`, featureFlags),
    },
  ]

  return (
    <ThemeProvider dir="ltr" style={{backgroundColor: 'var(--brand-color-canvas-default)'}} colorMode={pageColorMode}>
      <GlowBackground />
      <Grid>
        <Grid.Column span={12}>
          <Box marginBlockStart={20}>
            <Link
              className={styles.breadcrumbLink}
              {...getAnalyticsEvent({
                action: breadcrumbListItems[0]?.name || 'Newsroom',
                tag: 'link',
                context: 'breadcrumb',
                location: 'header',
              })}
              href={breadcrumbListItems[0]?.url}
              arrowDirection="start"
            >
              Newsroom
            </Link>
          </Box>
          <Box className={styles['hero-wrapper']}>
            <ContentfulHero data-hpc component={hero} />
          </Box>
          <Stack direction="vertical" padding="none" gap={80}>
            {cards.length > 0 && (
              <AnimationProvider runOnce visibilityOptions={0.2}>
                <CategoryCards cards={cards} animate="scale-in-up" fullWidth />
              </AnimationProvider>
            )}
            {additionalProps?.totalPages && additionalProps?.totalPages > 1 ? (
              <Box className={styles.paginationWrapper}>
                <Pagination
                  pageCount={additionalProps?.totalPages || 1}
                  currentPage={additionalProps?.page || 1}
                  hrefBuilder={nextPageNumber =>
                    appendFeatureFlagsToUrl(
                      replacePageNumberInUrl(ssrSafeLocation.pathname, nextPageNumber),
                      featureFlags,
                    )
                  }
                  pageAttributesBuilder={nextPageNumber => {
                    return getAnalyticsEvent({
                      action: `page_${nextPageNumber}`,
                      tag: 'link',
                      context: 'pagination',
                      location: 'newsroom_category_cards',
                    })
                  }}
                  showPages
                />
              </Box>
            ) : null}
            {ctaBanner ? (
              <Box animate="scale-in-up">
                <ContentfulCtaBanner component={ctaBanner} className={styles.ctaBanner} />
              </Box>
            ) : null}
          </Stack>
        </Grid.Column>
        <Footnotes staticFootnotes={staticFootnotes} />
      </Grid>
      <BreadcrumbSeoSchema items={breadcrumbListItems} />
    </ThemeProvider>
  )
}
