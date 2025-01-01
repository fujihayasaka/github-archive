import {useMemo} from 'react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import resolveResponse from 'contentful-resolve-response'
import {toWhitepaperIndexPayload} from '../../../lib/types/payload'
import {
  toWhitepaperContainerPage,
  toEntryCollection,
  toWhitepaperIndex,
  type WhitepaperIndexContainer,
  type WhitepaperDetailTruncatedContainer,
  toTruncatedWhitepaper,
} from '../../../lib/types/contentful'
import type {LabelColors} from '@primer/react-brand'
import {AnimationProvider, Box, Grid, Hero, Pagination, ThemeProvider} from '@primer/react-brand'
import type {RichText} from '@github-ui/swp-core/schemas/contentful/richText'

import {CategoryCard} from '../../../components/CategoryCard/CategoryCard'
import {documentToReactComponents, type Options} from '@contentful/rich-text-react-renderer'
import {BLOCKS, type Document} from '@contentful/rich-text-types'
import type {Asset} from '@github-ui/swp-core/schemas/contentful/contentTypes/asset'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import styles from './WhitepaperIndex.module.css'
import {appendFeatureFlagsToUrl} from '../../../lib/utils'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {Filters} from '../../../components/Filters/Filters'
import {CheckboxFilterGroups} from '../../../lib/types/utils/filters'

type WhitepaperCardProps = {
  id: string
  title: string
  contentType: string
  featuredImage?: Asset
  excerpt: RichText
  path: string
}

const formatWhitepaperForCard = (whitepaper: WhitepaperDetailTruncatedContainer): WhitepaperCardProps => {
  const template = whitepaper.fields.template
  return {
    id: whitepaper.sys.id,
    title: template.fields.heading,
    contentType: template.fields.contentType,
    featuredImage: template.fields.featuredImage,
    excerpt: template.fields.excerpt,
    path: whitepaper.fields.path,
  }
}

type ExcerptProps = {
  content: Document
}

type LabelColorProps = (typeof LabelColors)[number]

const Excerpt = ({content}: ExcerptProps) => {
  const option: Options = {
    renderNode: {
      [BLOCKS.PARAGRAPH]: (_, children) => {
        return children
      },
    },
  }

  return <>{documentToReactComponents(content, option)}</>
}

export function WhitepaperIndex() {
  const {contentfulRawJsonResponse, additionalProps} = toWhitepaperIndexPayload(useRoutePayload<unknown>())

  const {page, cards} = useMemo(() => {
    let mappedPage: WhitepaperIndexContainer | undefined
    const mappedCards: WhitepaperCardProps[] = []
    for (const entry of toEntryCollection(resolveResponse(contentfulRawJsonResponse))) {
      const containerPage = toWhitepaperContainerPage(entry)

      if (containerPage.fields.template.sys.contentType.sys.id === 'templateWhitepaperIndex') {
        mappedPage = toWhitepaperIndex(containerPage)
      } else {
        mappedCards.push(formatWhitepaperForCard(toTruncatedWhitepaper(containerPage)))
      }
    }

    return {page: mappedPage, cards: mappedCards}
  }, [contentfulRawJsonResponse])

  const checkboxGroups = useMemo(
    () =>
      CheckboxFilterGroups.map(group => ({
        ...group,
        checkboxes: group.checkboxes.map(checkbox => {
          const checkedGroup = additionalProps?.filters?.[group.name] as string[] | undefined

          return {
            ...checkbox,
            isChecked: checkedGroup?.includes(checkbox.value) ?? false,
          }
        }),
      })),
    [additionalProps],
  )

  const getPaginationURL = (pageNumber: number, featureFlags: string): string => {
    const url = new URL(`${ssrSafeLocation.pathname}${ssrSafeLocation.search}`, ssrSafeLocation.origin)
    // remove _features from query params to query parameter order for SEO purposes.
    // this will ensure _features is always at the end of the query params
    url.searchParams.delete('_features')
    url.searchParams.set('page', pageNumber.toString())

    return appendFeatureFlagsToUrl(url.toString(), featureFlags)
  }

  const excerpt = page?.fields.template.fields.excerpt
  const pageColorMode = page?.fields.settings?.fields.colorMode ?? 'light'

  const queryParams = new URLSearchParams(ssrSafeLocation.search)
  const featureFlags = queryParams.get('_features') || ''
  const hasPages = additionalProps?.totalPages && additionalProps?.totalPages > 1

  return (
    <ThemeProvider dir="ltr" style={{backgroundColor: 'var(--brand-color-canvas-default)'}} colorMode={pageColorMode}>
      <AnimationProvider runOnce visibilityOptions={0.2}>
        <Box paddingBlockEnd={{narrow: 40, regular: 80}}>
          <Grid className={styles.layoutGrid}>
            <Grid.Column span={12}>
              <Box marginBlockStart={{narrow: 64, regular: 112}} marginBlockEnd={{regular: 64}}>
                <Hero className="pt-0 pb-0">
                  <Hero.Heading>{page?.fields.title}</Hero.Heading>
                  {excerpt && (
                    <Hero.Description>
                      <Excerpt content={excerpt} />
                    </Hero.Description>
                  )}
                </Hero>
              </Box>
            </Grid.Column>
            <Grid.Column span={{xsmall: 12, medium: 3}} className={styles.filtersColumn}>
              <Filters checkboxGroups={checkboxGroups} />
            </Grid.Column>

            <Grid.Column span={{xsmall: 12, medium: 9}}>
              <Box marginBlockEnd={{narrow: 32, regular: 48}}>
                <Grid className={styles.cardGrid}>
                  {cards.map(card => {
                    let labelColor: LabelColorProps = 'default'
                    switch (card.contentType) {
                      case 'Whitepaper':
                        labelColor = 'purple'
                        break
                      case 'Ebook':
                        labelColor = 'pink'
                        break
                      case 'Industry Report':
                        labelColor = 'blue'
                        break
                    }
                    return (
                      <Grid.Column span={{xsmall: 12, medium: 6}} key={card.id}>
                        <CategoryCard
                          imageUrl={card.featuredImage?.fields.file.url}
                          imageDescription={card.featuredImage?.fields.description}
                          title={card.title}
                          label={card.contentType}
                          labelColor={labelColor}
                          excerpt={card.excerpt}
                          analyticsEvent={getAnalyticsEvent({
                            action: 'learn_more',
                            tag: 'card',
                            context: card.title,
                            location: 'resource_whitepaper_category_cards',
                          })}
                          path={appendFeatureFlagsToUrl(card.path, featureFlags)}
                          dataRef={`whitepaper-card-${card.id}`}
                        />
                      </Grid.Column>
                    )
                  })}
                </Grid>
              </Box>
              {hasPages ? (
                <Box paddingBlockStart={28} borderBlockStartWidth="thin" borderColor="default" borderStyle="solid">
                  <Pagination
                    pageCount={additionalProps?.totalPages || 1}
                    currentPage={additionalProps?.page || 1}
                    showPages={{narrow: false, regular: true, wide: true}}
                    hrefBuilder={nextPageNumber => getPaginationURL(nextPageNumber, featureFlags)}
                    pageAttributesBuilder={nextPageNumber => {
                      return getAnalyticsEvent({
                        action: `page_${nextPageNumber}`,
                        tag: 'link',
                        context: 'pagination',
                        location: 'whitepaper_index_cards',
                      })
                    }}
                  />
                </Box>
              ) : null}
            </Grid.Column>
          </Grid>
        </Box>
      </AnimationProvider>
    </ThemeProvider>
  )
}
