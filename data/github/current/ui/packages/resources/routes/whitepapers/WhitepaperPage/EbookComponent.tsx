import {useCallback} from 'react'

import {ContentfulForm} from '@github-ui/swp-core/components/contentful/ContentfulForm'
import {ContentfulProse} from '@github-ui/swp-core/components/contentful/ContentfulProse'
import {Box, Grid, Image, Stack} from '@primer/react-brand'

import {Lede} from '../../../components/Lede/Lede'
import type {WhitepaperPage} from '../../../lib/types/contentful/contentTypes/templateWhitepaper'

import {WhitepaperHeader, type BreadcrumbListItem} from './WhitepaperHeader'

import styles from './WhitepaperPage.module.css'
import {Topics} from '../../../components/Topics/Topics'
import {SocialShare} from '../../../components/SocialShare/SocialShare'
import {getImageSources} from '@github-ui/swp-core/lib/utils/images'

type EbookProps = {
  component: WhitepaperPage
  breadcrumbs: BreadcrumbListItem[]
  socialShareUrl: string
}

export function EbookComponent({component, breadcrumbs, socialShareUrl}: EbookProps) {
  const {lede, body, featuredImage} = component.fields

  const handleOnSubmitted = useCallback(() => {
    const redirectUrl = new URL(`${window.location.pathname}/confirmation`, window.location.origin)

    window.location.href = redirectUrl.href
  }, [])

  return (
    <Grid className={styles.whitepaperGrid}>
      <Grid.Column span={{xsmall: 12, large: 7}}>
        <Grid>
          <Grid.Column span={12}>
            <WhitepaperHeader component={component} breadcrumbs={breadcrumbs} />
          </Grid.Column>
          <Grid.Column span={12}>
            <Stack padding="none">
              <Box marginBlockEnd={{narrow: 24, wide: 48}}>
                <header>
                  <Lede content={lede} />
                </header>
              </Box>
              <Box
                paddingBlockEnd={{narrow: 40, wide: 64}}
                borderBlockEndWidth="thin"
                borderColor="muted"
                borderStyle="solid"
              >
                <ContentfulProse variant="editorial" component={body} />
              </Box>
            </Stack>
            <Box
              paddingBlockStart={40}
              paddingBlockEnd={40}
              borderBlockStartWidth="thin"
              borderBlockEndWidth="thin"
              borderColor="muted"
              borderStyle="solid"
            >
              <SocialShare url={socialShareUrl} />
            </Box>
            {component.fields.topics && (
              <Box
                className={styles.TopicsBox}
                paddingBlockStart={40}
                paddingBlockEnd={40}
                borderBlockEndWidth="thin"
                borderColor="muted"
                borderStyle="solid"
              >
                <Topics topics={component.fields.topics} />
              </Box>
            )}
          </Grid.Column>
        </Grid>
      </Grid.Column>
      <Grid.Column
        id="ebook-form"
        className={`${styles.formWrapper} ${!featuredImage ? styles.ebookFormWrapperNoImage : ''}`}
        span={{xsmall: 12, large: 4}}
        start={{large: 9}}
      >
        <Grid>
          <Grid.Column span={{xsmall: 12, small: 6, large: 12}} start={{small: 4}}>
            {featuredImage && (
              <Box className={styles.hiddenOnMobile} marginBlockStart={80}>
                <Image
                  as="picture"
                  src={`${featuredImage.fields.file.url}?fm=webp`}
                  sources={getImageSources(featuredImage.fields.file.url, {maxWidth: 640})}
                  alt={featuredImage.fields.description || ''}
                  borderRadius="medium"
                  aspectRatio="1:1"
                  loading="lazy"
                />
              </Box>
            )}
            <Box className={featuredImage ? styles.ebookFormBox : ''}>
              <ContentfulForm
                component={component.fields.form}
                headingProps={{as: 'h2', size: '6'}}
                onSubmitted={handleOnSubmitted}
                padding="none"
              />
            </Box>
          </Grid.Column>
        </Grid>
      </Grid.Column>
    </Grid>
  )
}
