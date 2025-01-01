import resolveResponse from 'contentful-resolve-response'
import {Grid, Box, CTABanner, Heading, Text, Link, Stack, Button} from '@primer/react-brand'
import {CheckIcon} from '@primer/octicons-react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ContentfulCards} from '@github-ui/swp-core/components/contentful/ContentfulCards'
import {toWhitepaperPage, toEntryCollection} from '../../../lib/types/contentful'
import {toPayload} from '../../../lib/types/payload'
import styles from './WhitepaperConfirmation.module.css'

const ConfirmationIcon = () => (
  <div className={`${styles.confirmIconOuter} mb-2`}>
    <div className={styles.confirmIconInner}>
      <CheckIcon size={24} />
    </div>
  </div>
)

export function WhitepapersConfirmation() {
  const {contentfulRawJsonResponse} = toPayload(useRoutePayload<unknown>())
  const page = toWhitepaperPage(toEntryCollection(resolveResponse(contentfulRawJsonResponse)).at(0))
  const {
    heading,
    relatedResources,
    downloadableAsset,
    downloadableAssetUrl,
    downloadableAssetCta,
    confirmationCtaDescription,
  } = page.fields.template.fields

  // It was determined in conversation here: https://github.com/github/marketing-platform-services/issues/3964 that
  // we need to support both assets in Contentful and links to external assets. A content creator should never include
  // both, but in the event that they do, it was determined the external link should take precedence.
  const assetUrl = downloadableAssetUrl || downloadableAsset?.fields.file.url
  const assetCta = downloadableAssetCta || 'Download PDF'

  return (
    <>
      <Grid>
        <Grid.Column>
          <Box marginBlockStart={24} marginBlockEnd={24} className="d-flex flex-items-center">
            <Link href="/resources/whitepapers" arrowDirection="start">
              <Text>Ebooks &amp; Whitepapers</Text>
            </Link>
          </Box>

          <CTABanner backgroundColor="subtle" hasShadow={false} align="center" className={styles.ctaContainer}>
            <ConfirmationIcon />

            <CTABanner.Heading as="h1" size="2">
              {heading}
            </CTABanner.Heading>

            {confirmationCtaDescription && (
              <CTABanner.Description className="pt-3 mb-0">{confirmationCtaDescription}</CTABanner.Description>
            )}
            {assetUrl && (
              <CTABanner.ButtonGroup buttonsAs="a">
                <Button href={assetUrl}>{assetCta}</Button>
              </CTABanner.ButtonGroup>
            )}
          </CTABanner>
        </Grid.Column>
      </Grid>

      {relatedResources && relatedResources.length > 0 && (
        <Grid className="mt-5 mt-lg-9 mb-5 mb-lg-10">
          <Grid.Column>
            <Stack direction="vertical" padding="none" gap={{narrow: 40, regular: 64}}>
              <Heading as="h2" size="5">
                Explore other resources
              </Heading>

              <ContentfulCards
                className={styles.relatedResources}
                cards={relatedResources}
                imageAspectRatio="16:9"
                fullWidth
              />
            </Stack>
          </Grid.Column>
        </Grid>
      )}
    </>
  )
}
