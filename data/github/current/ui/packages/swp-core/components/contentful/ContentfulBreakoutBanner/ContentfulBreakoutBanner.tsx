import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import styles from './ContentfulBreakoutBanner.module.css'

import {BreakoutBanner, Link, Box} from '@primer/react-brand'
import {Logo} from './Logo'
import type {ContentfulBreakoutBannerProps} from './ContentfulBreakoutBannerTypes'
import {documentToPlainTextString, getAnalyticsEvent} from '../../../lib/utils/analytics'

export function ContentfulBreakoutBanner({
  component,
  headingProps,
  linkGroupProps,
  ...inlineProps
}: ContentfulBreakoutBannerProps) {
  // fields derived from Contentful
  const {align, backgroundColor, backgroundImage, heading, logo, ctaLink} = component.fields

  return (
    <BreakoutBanner
      className={styles.wrapper}
      align={align}
      backgroundColor={backgroundColor}
      backgroundImageSrc={backgroundImage?.fields.file.url}
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
