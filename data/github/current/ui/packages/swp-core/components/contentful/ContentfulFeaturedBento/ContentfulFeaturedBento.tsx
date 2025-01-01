import type {iconSizes} from '@primer/react-brand'
import {Bento, Box, Link, Icon} from '@primer/react-brand'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {BLOCKS, MARKS} from '@contentful/rich-text-types'
import {documentToReactComponents} from '@contentful/rich-text-react-renderer'

import type {FeaturedBentoType} from '../../../schemas/contentful/contentTypes/featuredBento'
import {getPrimerIcon} from '../../../lib/utils/icons'
import {documentToPlainTextString, getAnalyticsEvent} from '../../../lib/utils/analytics'
import {getImageSources} from '../../../lib/utils/images'

type BentoHeadingProps = React.ComponentProps<typeof Bento.Heading>
type BentoItemProps = React.ComponentProps<typeof Bento.Item>
type BentoContentrops = React.ComponentProps<typeof Bento.Content>
type LinkProps = React.ComponentProps<typeof Link>
type BoxProps = React.ComponentProps<typeof Box>
type ContentfulFeaturedBentoProps = {
  itemBgColor?: BentoItemProps['bgColor']
  itemFlow?: BentoItemProps['flow']
  itemRowSpan?: BentoItemProps['rowSpan']
  contentPadding?: BentoContentrops['padding']
  component: FeaturedBentoType
  linkSize?: LinkProps['size']
  boxPaddingBlockEnd?: BoxProps['paddingBlockEnd']
  boxPaddingBlockStart?: BoxProps['paddingBlockStart']
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
  const {heading, link, icon, image, iconColor} = component.fields
  const Octicon = getPrimerIcon(icon)
  const extraContentProps = Octicon
    ? {leadingVisual: <Icon icon={Octicon} color={iconColor} size={iconSize} hasBackground />}
    : {}

  const extraLinkProps = link.fields.openInNewTab
    ? {
        target: '_blank',
      }
    : {}

  const optimizeImageEnabled = isFeatureEnabled('contentful_lp_optimize_image')

  return (
    <Box className={className} paddingBlockEnd={boxPaddingBlockEnd} paddingBlockStart={boxPaddingBlockStart}>
      <Bento>
        <Bento.Item flow={itemFlow} rowSpan={itemRowSpan} bgColor={itemBgColor}>
          <Bento.Content padding={contentPadding} {...extraContentProps}>
            <Bento.Heading size={headingSize}>
              {documentToReactComponents(heading, {
                renderNode: {
                  [BLOCKS.PARAGRAPH]: (_, children) => children,
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
                context: `${documentToPlainTextString(heading).split(' ')[0] || ''}_bento`,
                location: documentToPlainTextString(heading),
              })}
            >
              {link.fields.text}
            </Link>
          </Bento.Content>
          {image ? (
            <Bento.Visual position="50% 100%" padding="normal">
              {optimizeImageEnabled ? (
                <OptimizedVisual image={image} />
              ) : (
                <img alt={image.fields.description} src={image.fields.file.url} />
              )}
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
    <picture>
      {imageSources.map(source => (
        <source key={source.media} srcSet={source.srcset} media={source.media} />
      ))}
      <img
        src={image.fields.file.url}
        alt={image.fields.description}
        // Primer Brand does not apply styles properly to images within a picture element. This is a workaround.
        // We should remove this code if/when the Primer Brand bug is fixed: https://github.com/primer/brand/issues/921
        style={{objectPosition: '50% 100%', objectFit: 'cover', height: '100%'}}
      />
    </picture>
  )
}
