import type {iconSizes} from '@primer/react-brand'
import {Bento, Box, Link, Icon} from '@primer/react-brand'
import {BLOCKS, INLINES, MARKS} from '@contentful/rich-text-types'
import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import type {FeaturedBentoType} from '../../../schemas/contentful/contentTypes/featuredBento'
import {getPrimerIcon} from '../../../lib/utils/icons'
import {documentToPlainTextString, getAnalyticsEvent} from '../../../lib/utils/analytics'
import {getImageSources} from '../../../lib/utils/images'
import styles from './ContentfulFeaturedBento.module.css'
import {ContentfulInlineFootnote} from '../ContentfulFootnotes/ContentfulInlineFootnote'

type BentoHeadingProps = React.ComponentProps<typeof Bento.Heading>
type BentoItemProps = React.ComponentProps<typeof Bento.Item>
type BentoContentrops = React.ComponentProps<typeof Bento.Content>
type LinkProps = React.ComponentProps<typeof Link>
type PrimerBoxProps = React.ComponentProps<typeof Box>
type ContentfulFeaturedBentoProps = {
  itemBgColor?: BentoItemProps['bgColor']
  itemFlow?: BentoItemProps['flow']
  itemRowSpan?: BentoItemProps['rowSpan']
  contentPadding?: BentoContentrops['padding']
  component: FeaturedBentoType
  linkSize?: LinkProps['size']
  boxPaddingBlockEnd?: PrimerBoxProps['paddingBlockEnd']
  boxPaddingBlockStart?: PrimerBoxProps['paddingBlockStart']
  headingSize?: BentoHeadingProps['size']
  className?: string
  iconSize?: (typeof iconSizes)[number]
}

export function ContentfulFeaturedBento({
  component,
  itemBgColor = 'default',
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  itemFlow = {
    xsmall: 'row',
    small: 'row',
    medium: 'column',
    large: 'column',
    xlarge: 'column',
    xxlarge: 'column',
  },
  itemRowSpan = 5,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  contentPadding = {
    xsmall: 'normal',
    small: 'spacious',
  },
  linkSize = 'medium',
  boxPaddingBlockEnd = 128,
  boxPaddingBlockStart = 64,
  headingSize = '4',
  className,
  iconSize = 'medium',
}: ContentfulFeaturedBentoProps) {
  const {heading, headingLevel, link, icon, image, iconColor} = component.fields
  const Octicon = getPrimerIcon(icon)
  const footnotesEnabled = isFeatureEnabled('contentful_lp_footnotes')

  const extraContentProps = Octicon
    ? {leadingVisual: <Icon icon={Octicon} color={iconColor} size={iconSize} hasBackground />}
    : {}

  const extraLinkProps = link.fields.openInNewTab
    ? {
        target: '_blank',
      }
    : {}

  const plainTextHeading = documentToPlainTextString(heading)

  return (
    <Box className={className} paddingBlockEnd={boxPaddingBlockEnd} paddingBlockStart={boxPaddingBlockStart}>
      <Bento>
        <Bento.Item className={styles.featuredBentoItem} flow={itemFlow} rowSpan={itemRowSpan} bgColor={itemBgColor}>
          <Bento.Content className={styles.featuredBentoContent} padding={contentPadding} {...extraContentProps}>
            <Bento.Heading as={headingLevel} size={headingSize}>
              {documentToReactComponents(heading, {
                renderNode: {
                  [BLOCKS.PARAGRAPH]: (_, children) => children,
                  [INLINES.EMBEDDED_ENTRY]: node => {
                    if (footnotesEnabled && node.data.target.sys.contentType.sys.id === 'inlineFootnote') {
                      return (
                        <ContentfulInlineFootnote
                          component={node.data.target}
                          providedInstanceId={plainTextHeading}
                          analyticsLocation={plainTextHeading}
                          size="large"
                        />
                      )
                    }

                    return null
                  },
                },
                renderMark: {
                  [MARKS.ITALIC]: (text: React.ReactNode) => <em>{text}</em>,
                },
              })}
            </Bento.Heading>
            <Link
              size={linkSize}
              href={link.fields.href}
              variant="accent"
              {...extraLinkProps}
              {...getAnalyticsEvent({
                action: link.fields.text,
                tag: 'link',
                context: `${plainTextHeading.split(' ')[0] || ''}_bento`,
                location: plainTextHeading,
              })}
            >
              {link.fields.text}
            </Link>
          </Bento.Content>
          {image ? (
            <Bento.Visual className={styles.featuredBentoVisual} position="50% 100%" padding="normal">
              <OptimizedVisual image={image} />
            </Bento.Visual>
          ) : null}
        </Bento.Item>
      </Bento>
    </Box>
  )
}

type OptimizedVisualProps = {
  image: FeaturedBentoType['fields']['image']
}

export function OptimizedVisual({image}: OptimizedVisualProps) {
  if (!image) return null

  const imageSources = getImageSources(image.fields.file.url, {maxWidth: 600})

  return (
    // Primer Brand does not apply styles properly to images within a picture element. This is a workaround.
    // We should remove this style class if/when the Primer Brand bug is fixed: https://github.com/primer/brand/issues/921
    <picture className={styles.imageFillMedia}>
      {imageSources.map(source => (
        <source key={source.media} srcSet={source.srcset} media={source.media} />
      ))}
      <img className={styles.imageFillMedia} src={image.fields.file.url} alt={image.fields.description} />
    </picture>
  )
}
