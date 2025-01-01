import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import type {BreakoutBannerProps} from '@primer/react-brand'
import {BreakoutBanner, Link, Box} from '@primer/react-brand'
import {clsx} from 'clsx'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {BLOCKS, INLINES} from '@contentful/rich-text-types'

import {documentToPlainTextString, getAnalyticsEvent} from '../../../lib/utils/analytics'
import {getStructuredImageSources, MAX_CONTENT_WIDTH} from '../../../lib/utils/images'

import styles from './ContentfulBreakoutBanner.module.css'
import {Logo} from './Logo'
import type {ContentfulBreakoutBannerProps} from './ContentfulBreakoutBannerTypes'
import {ContentfulInlineFootnote} from '../ContentfulFootnotes/ContentfulInlineFootnote'

export function ContentfulBreakoutBanner({className, component, ...inlineProps}: ContentfulBreakoutBannerProps) {
  // fields derived from Contentful
  const {align, backgroundColor, backgroundImage, heading, headingLevel, logo, ctaLink} = component.fields

  const footnotesEnabled = isFeatureEnabled('contentful_lp_footnotes')
  const plainTextHeading = documentToPlainTextString(heading)

  let backgroundImageSrc: BreakoutBannerProps['backgroundImageSrc'] = backgroundImage?.fields.file.url
  if (backgroundImageSrc) {
    backgroundImageSrc = getStructuredImageSources(backgroundImageSrc, {maxWidth: MAX_CONTENT_WIDTH})
  }

  return (
    <BreakoutBanner
      className={clsx(styles.wrapper, className)}
      align={align}
      backgroundColor={backgroundColor}
      backgroundImageSrc={backgroundImageSrc}
      backgroundImagePosition={{
        narrow: 'bottom',
        regular: 'right',
        wide: 'right',
      }}
      {...(logo && {
        leadingVisual: (
          <Box className={styles.logoWrapper}>
            <Logo name={logo} />
          </Box>
        ),
      })}
      {...inlineProps}
    >
      <BreakoutBanner.Heading as={headingLevel}>
        {documentToReactComponents(heading, {
          renderNode: {
            [BLOCKS.PARAGRAPH]: (_, children) => {
              return children
            },
            [INLINES.EMBEDDED_ENTRY]: node => {
              if (footnotesEnabled && node.data.target.sys.contentType.sys.id === 'inlineFootnote') {
                return (
                  <ContentfulInlineFootnote
                    component={node.data.target}
                    analyticsLocation={plainTextHeading}
                    providedInstanceId={plainTextHeading}
                    size="large"
                  />
                )
              }

              return null
            },
          },
        })}
      </BreakoutBanner.Heading>
      <BreakoutBanner.LinkGroup>
        <Link
          key={ctaLink.sys.id}
          href={ctaLink.fields.href}
          {...getAnalyticsEvent({
            action: ctaLink.fields.text,
            tag: 'link',
            context: logo ? `${logo}_breakout_banner` : `${plainTextHeading.split(' ')[0] || ''}_breakout_banner`,
            location: plainTextHeading,
          })}
        >
          {ctaLink.fields.text}
        </Link>
      </BreakoutBanner.LinkGroup>
    </BreakoutBanner>
  )
}
