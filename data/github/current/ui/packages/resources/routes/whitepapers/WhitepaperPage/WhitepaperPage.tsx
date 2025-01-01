import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {AnimationProvider, Box, Grid, Heading, Stack, ThemeProvider} from '@primer/react-brand'
import {ArticleSeoSchema} from '@github-ui/swp-core/components/structuredData/ArticleSeoSchema'
import {BreadcrumbSeoSchema} from '@github-ui/swp-core/components/structuredData/BreadcrumbSeoSchema'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import resolveResponse from 'contentful-resolve-response'

import {toPayload} from '../../../lib/types/payload'
import {appendFeatureFlagsToUrl} from '../../../lib/utils'
import {toEntryCollection, toWhitepaperPage} from '../../../lib/types/contentful'

import {WhitepaperComponent} from './WhitepaperComponent'
import {EbookComponent} from './EbookComponent'
import {ContentfulCards} from '@github-ui/swp-core/components/contentful/ContentfulCards'
import styles from './WhitepaperPage.module.css'

export function WhitepaperPage() {
  const payload = toPayload(useRoutePayload<unknown>())
  const page = toWhitepaperPage(toEntryCollection(resolveResponse(payload.contentfulRawJsonResponse)).at(0))
  const {template, settings} = page.fields
  const colorMode = settings?.fields.colorMode ?? 'light'
  const {contentType, relatedResources, heading, featuredImage} = template.fields

  const locationUrl = new URL(page.fields.path, ssrSafeLocation.origin)
  const urlParts = locationUrl.pathname.split('/')
  const queryParams = new URLSearchParams(ssrSafeLocation.search)
  const featureFlags = queryParams.get('_features') || ''

  const breadcrumbListItems = [
    {
      name: 'Ebooks & Whitepapers',
      url: appendFeatureFlagsToUrl(
        `${locationUrl.origin}/${urlParts[1]}${urlParts[2] && `/${urlParts[2]}`}`,
        featureFlags,
      ),
    },
  ]

  return (
    <ThemeProvider
      colorMode={colorMode}
      dir="ltr"
      style={{
        backgroundColor: 'var(--brand-color-canvas-default)',
      }}
    >
      <AnimationProvider runOnce visibilityOptions={0.2}>
        <Box marginBlockEnd={64}>
          {contentType === 'Whitepaper' && (
            <WhitepaperComponent
              component={template}
              breadcrumbs={breadcrumbListItems}
              socialShareUrl={locationUrl.toString()}
            />
          )}
          {contentType === 'Ebook' && (
            <EbookComponent
              component={template}
              breadcrumbs={breadcrumbListItems}
              socialShareUrl={locationUrl.toString()}
            />
          )}
        </Box>
        {relatedResources && relatedResources.length > 0 && (
          <Box
            paddingBlockStart={{narrow: 48, regular: 80}}
            paddingBlockEnd={{narrow: 64, regular: 96}}
            backgroundColor="subtle"
          >
            <Grid>
              <Grid.Column>
                <Stack direction="vertical" padding="none" gap={{narrow: 40, regular: 64}}>
                  <Heading as="h2" size="5">
                    Explore other resources
                  </Heading>
                  <ContentfulCards
                    cards={relatedResources}
                    className={styles.whitepaperRelatedCards}
                    imageAspectRatio="16:9"
                    fullWidth
                  />
                </Stack>
              </Grid.Column>
            </Grid>
          </Box>
        )}
      </AnimationProvider>
      <ArticleSeoSchema title={heading} imageUrl={featuredImage?.fields.file.url} />
      <BreadcrumbSeoSchema items={breadcrumbListItems} />
    </ThemeProvider>
  )
}
