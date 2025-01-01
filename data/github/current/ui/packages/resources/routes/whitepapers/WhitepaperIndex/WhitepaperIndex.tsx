import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import resolveResponse from 'contentful-resolve-response'
import {useMemo} from 'react'
import {toPayload} from '../../../lib/types/payload'
import {
  toWhitepaperContainerPage,
  toEntryCollection,
  toWhitepaperIndex,
  type WhitepaperHomepageContainer,
  type WhitepaperDetailTruncatedContainer,
  toTruncatedWhitepaper,
} from '../../../lib/types/contentful'
import type {LabelColors} from '@primer/react-brand'
import {AnimationProvider, Box, Grid, Hero, ThemeProvider} from '@primer/react-brand'
import type {RichText} from '@github-ui/swp-core/schemas/contentful/richText'

import {CategoryCard} from '../../../components/CategoryCard/CategoryCard'
import {documentToReactComponents, type Options} from '@contentful/rich-text-react-renderer'
import {BLOCKS, type Document} from '@contentful/rich-text-types'
import type {Asset} from '@github-ui/swp-core/schemas/contentful/contentTypes/asset'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import styles from './WhitepaperIndex.module.css'

type WhitepaperCardProps = {
  id: string
  title: string
  contentType: string
  featuredImage: Asset
  excerpt: RichText
  path: string
}

const formatPressReleaseForCard = (whitepaper: WhitepaperDetailTruncatedContainer): WhitepaperCardProps => {
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
  const {contentfulRawJsonResponse} = toPayload(useRoutePayload<unknown>())

  const {page, cards} = useMemo(() => {
    let mappedPage: WhitepaperHomepageContainer | undefined
    const mappedCards: WhitepaperCardProps[] = []
    for (const entry of toEntryCollection(resolveResponse(contentfulRawJsonResponse))) {
      const containerPage = toWhitepaperContainerPage(entry)

      if (containerPage.fields.template.sys.contentType.sys.id === 'templateWhitepaperIndex') {
        mappedPage = toWhitepaperIndex(containerPage)
      } else {
        mappedCards.push(formatPressReleaseForCard(toTruncatedWhitepaper(containerPage)))
      }
    }

    return {page: mappedPage, cards: mappedCards}
  }, [contentfulRawJsonResponse])

  const excerpt = page?.fields.template.fields.excerpt
  const pageColorMode = page?.fields.settings?.fields.colorMode ?? 'light'

  return (
    <ThemeProvider dir="ltr" style={{backgroundColor: 'var(--brand-color-canvas-default)'}} colorMode={pageColorMode}>
      <AnimationProvider runOnce visibilityOptions={0.2}>
        <Grid>
          <Grid.Column span={12}>
            <Box marginBlockStart={{narrow: 64, regular: 112}} marginBlockEnd={{narrow: 32, regular: 64}}>
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
          <Grid.Column span={{xsmall: 12, large: 12}}>
            <Box
              marginBlockEnd={{narrow: 48}}
              paddingBlockEnd={{narrow: 48}}
              borderBlockEndWidth="thin"
              borderColor="default"
              borderStyle="solid"
            >
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
                    <Grid.Column span={{xsmall: 12, medium: 6}} key={card.title}>
                      <CategoryCard
                        imageUrl={card.featuredImage.fields.file.url}
                        imageDescription={card.featuredImage.fields.description}
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
                        path={card.path}
                        dataRef={`whitepaper-card-${card.id}`}
                      />
                    </Grid.Column>
                  )
                })}
              </Grid>
            </Box>
          </Grid.Column>
        </Grid>
      </AnimationProvider>
    </ThemeProvider>
  )
}
