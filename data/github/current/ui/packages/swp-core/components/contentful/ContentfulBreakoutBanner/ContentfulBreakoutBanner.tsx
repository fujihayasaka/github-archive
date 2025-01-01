import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import type {BreakoutBannerProps} from '@primer/react-brand'
import {BreakoutBanner, Link, Box} from '@primer/react-brand'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {clsx} from 'clsx'

import {documentToPlainTextString, getAnalyticsEvent} from '../../../lib/utils/analytics'
import {getStructuredImageSources, MAX_CONTENT_WIDTH} from '../../../lib/utils/images'

import styles from './ContentfulBreakoutBanner.module.css'
import {Logo} from './Logo'
import type {ContentfulBreakoutBannerProps} from './ContentfulBreakoutBannerTypes'

export function ContentfulBreakoutBanner({
  className,
  component,
  headingProps,
  linkGroupProps,
  ...inlineProps
}: ContentfulBreakoutBannerProps) {
  // fields derived from Contentful
  const {align, backgroundColor, backgroundImage, heading, logo, ctaLink} = component.fields

  const optimizeImageEnabled = isFeatureEnabled('contentful_lp_optimize_image')
  let backgroundImageSrc: BreakoutBannerProps['backgroundImageSrc'] = backgroundImage?.fields.file.url
  if (backgroundImageSrc && optimizeImageEnabled) {
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
      <BreakoutBanner.Heading {...(headingProps ? headingProps : {})}>
        {documentToReactComponents(heading)}
      </BreakoutBanner.Heading>
      <BreakoutBanner.LinkGroup {...(linkGroupProps ? linkGroupProps : {})}>
        <Link
          key={ctaLink.sys.id}
          href={ctaLink.fields.href}
          {...getAnalyticsEvent({
            action: ctaLink.fields.text,
            tag: 'link',
            context: logo
              ? `${logo}_breakout_banner`
              : `${documentToPlainTextString(heading).split(' ')[0] || ''}_breakout_banner`,
            location: documentToPlainTextString(heading),
          })}
        >
          {ctaLink.fields.text}
        </Link>
      </BreakoutBanner.LinkGroup>
    </BreakoutBanner>
  )
}
