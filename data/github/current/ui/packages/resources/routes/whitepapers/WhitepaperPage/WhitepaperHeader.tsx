import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import {ChevronDownIcon} from '@primer/octicons-react'
import {Box, Link, Hero, Button, Image} from '@primer/react-brand'
import styles from './WhitepaperPage.module.css'
import {getLocale} from '@github-ui/get-locale'
import {formatPublishedDate} from '../../../lib/utils'
import type {WhitepaperPage} from '../../../lib/types/contentful/contentTypes/templateWhitepaper'
import {getImageSources} from '@github-ui/swp-core/lib/utils/images'

export type BreadcrumbListItem = {
  name: string
  url: string
}

type WhitepaperHeaderProps = {
  component: WhitepaperPage
  breadcrumbs: BreadcrumbListItem[]
}

const EBOOK_CONTENT_TYPE = 'Ebook'

export function WhitepaperHeader({component, breadcrumbs}: WhitepaperHeaderProps) {
  const {heading, contentType, publishedDate, featuredImage} = component.fields
  const locale = getLocale()
  const formattedPublishedDate = formatPublishedDate(publishedDate, locale) ?? ''
  const mobileFormLinkButtonText = contentType === 'Ebook' ? 'Get the ebook' : 'Get the analysis'

  return (
    <header>
      <Box marginBlockStart={20}>
        <Link
          className={styles.whitepaperBreadcrumbLink}
          href={breadcrumbs[0]?.url}
          arrowDirection="start"
          {...getAnalyticsEvent({
            action: 'Ebooks & Whitepapers',
            tag: 'link',
            context: 'breadcrumb',
            location: 'header',
          })}
        >
          Ebooks & Whitepapers
        </Link>
      </Box>
      <Box
        marginBlockStart={{narrow: 48, regular: 64}}
        borderBlockEndWidth="thin"
        borderColor="muted"
        borderStyle="solid"
      >
        <Hero className={styles.whitepaperHero}>
          <Hero.Label color="pink">{contentType}</Hero.Label>
          <Hero.Heading>{heading}</Hero.Heading>
          {publishedDate && <Hero.Description>{formattedPublishedDate}</Hero.Description>}
        </Hero>
        {contentType === EBOOK_CONTENT_TYPE && featuredImage && (
          <Image
            className={styles.whitepaperHeroImage}
            as="picture"
            src={`${featuredImage.fields.file.url}?fm=webp`}
            sources={getImageSources(featuredImage.fields.file.url, {maxWidth: 1040})}
            alt={featuredImage.fields.description || ''}
            borderRadius="medium"
            loading="lazy"
          />
        )}
        <Button
          className={styles.whitepaperHeroPrimaryButton}
          as="a"
          href={contentType === EBOOK_CONTENT_TYPE ? '#ebook-form' : '#whitepaper-form'}
          variant="primary"
          trailingVisual={<ChevronDownIcon />}
          block
        >
          {mobileFormLinkButtonText}
        </Button>
      </Box>
    </header>
  )
}
