// eslint-disable-next-line import/no-namespace
import * as Primer from '@primer/octicons-react'

import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS} from '@contentful/rich-text-types'

import {Pillar, Box} from '@primer/react-brand'
import type {PrimerComponentPillar} from '../../../schemas/contentful/contentTypes/primerComponentPillar'
import {getAnalyticsEvent} from '../../../lib/utils/analytics'
import {getImageSources} from '../../../lib/utils/images'
import {isFeatureEnabled} from '@github-ui/feature-flags'

const toTitleCase = (str: string) => {
  return `${str
    .toLowerCase()
    .split('-')
    .map(function (word) {
      return word.charAt(0).toUpperCase() + word.slice(1)
    })
    .join('')}Icon`
}

const nameToPrimerIcon = (name: string = ''): Primer.Icon | undefined => {
  const titleCaseName = toTitleCase(name)
  const iconMap: {[key: string]: Primer.Icon} = Primer
  return iconMap[titleCaseName] ? iconMap[titleCaseName] : undefined
}

export type ContentfulPillarProps = {
  component: PrimerComponentPillar

  /**
   * The props below do not have a corresponding field in Contentful:
   */
  className?: string
  asCard?: boolean
  bgColor?: 'default' | 'subtle'
}

export const ContentfulPillarContent = ({component: {fields}, className, asCard}: ContentfulPillarProps) => {
  const {align, icon, iconColor, image, heading, description, link} = fields
  const Octicon = nameToPrimerIcon(icon)

  const optimizeImageEnabled = isFeatureEnabled('contentful_lp_optimize_image')

  return (
    <Pillar className={className} align={align}>
      {Octicon && <Pillar.Icon data-testid={`${icon}-${heading}`} color={iconColor} icon={<Octicon />} />}
      {image &&
        // Setting verticalAlign: 'bottom' on the image as a workaround for Primer Brand bug:
        // https://github.com/primer/brand/issues/911. This should be removed once the bug is fixed.
        (optimizeImageEnabled ? (
          <Pillar.Image
            style={{verticalAlign: 'bottom'}}
            as="picture"
            src={`${image.fields.file.url}?fm=webp`}
            sources={getImageSources(image.fields.file.url, {maxWidth: 640})}
            alt={image.fields.description || ''}
          />
        ) : (
          <Pillar.Image src={image.fields.file.url} alt={image.fields.description || ''} />
        ))}
      <Pillar.Heading>{heading}</Pillar.Heading>

      {documentToReactComponents(description, {
        renderNode: {
          [BLOCKS.PARAGRAPH]: (_, children: React.ReactNode) => (
            <Pillar.Description className={asCard && !link ? 'mb-0' : ''}>{children}</Pillar.Description>
          ),
        },
      })}

      {link && (
        <Pillar.Link
          href={link.fields.href}
          data-ref={`pillar-link-${link.sys.id}`}
          {...getAnalyticsEvent({
            action: link.fields.text,
            tag: 'link',
            context: heading,
          })}
        >
          {link.fields.text}
        </Pillar.Link>
      )}
    </Pillar>
  )
}

export const ContentfulPillar = ({component, className, asCard, bgColor}: ContentfulPillarProps) => {
  return asCard ? (
    <Box
      borderRadius="large"
      paddingBlockStart={32}
      paddingBlockEnd={40}
      backgroundColor="subtle"
      style={{
        height: '100%',
        paddingInlineStart: 32,
        paddingInlineEnd: 32,
        // The "asCard" prop of the pillar applies a background color, but when the page
        // background is "subtle," the pillars's background blends in, making it appear as
        // if it's not using the "asCard" prop. This explicitly sets the background color to
        // ensure the pillar as card stands out on both "default" and "subtle" backgrounds.
        backgroundColor: bgColor ? `var(--brand-color-canvas-${bgColor})` : undefined,
      }}
    >
      <ContentfulPillarContent component={component} className={className} asCard />
    </Box>
  ) : (
    <ContentfulPillarContent component={component} className={className} />
  )
}
