import {Statistic, type AnimateProps} from '@primer/react-brand'
import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, INLINES} from '@contentful/rich-text-types'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import type {PrimerComponentStatistic} from '../../../schemas/contentful/contentTypes/primerComponentStatistic'
import type {RichText} from '../../../schemas/contentful/richText'
import {ContentfulInlineFootnote} from '../ContentfulFootnotes/ContentfulInlineFootnote'
import {documentToPlainTextString} from '../../../lib/utils/analytics'

export type ContentfulStatisticProps = {
  animate?: AnimateProps
  component: PrimerComponentStatistic
  className?: string
  bgColor?: 'default' | 'subtle'
}

function renderRichText(content: string | RichText, footnotesEnabled: boolean, size?: 'large' | 'small') {
  if (typeof content === 'string') {
    return content
  }

  const analyticsLocation = documentToPlainTextString(content)

  return documentToReactComponents(content, {
    renderNode: {
      [BLOCKS.PARAGRAPH]: (_, children) => children,
      [INLINES.EMBEDDED_ENTRY]: node => {
        if (footnotesEnabled && node.data.target.sys.contentType.sys.id === 'inlineFootnote') {
          return (
            <ContentfulInlineFootnote
              component={node.data.target}
              analyticsLocation={analyticsLocation}
              providedInstanceId={analyticsLocation}
              size={size}
            />
          )
        }

        return null
      },
    },
  })
}

export function ContentfulStatistic({component, animate, className, bgColor}: ContentfulStatisticProps) {
  const {heading, size, variant, description, descriptionVariant} = component.fields
  const footnotesEnabled = isFeatureEnabled('contentful_lp_footnotes')

  return (
    <Statistic
      className={className}
      variant={variant}
      size={size}
      animate={animate}
      // The "boxed" variant of the statistic applies a background color, but when the page
      // background is "subtle," the statistic's background blends in, making it appear as
      // if it's not using the boxed variant. This explicitly sets the background color to
      // ensure the boxed variant stands out on both "default" and "subtle" backgrounds.
      style={{backgroundColor: bgColor && variant === 'boxed' ? `var(--brand-color-canvas-${bgColor})` : undefined}}
    >
      <Statistic.Heading as="p">{renderRichText(heading, footnotesEnabled, 'large')}</Statistic.Heading>
      {description && (
        <Statistic.Description variant={descriptionVariant}>
          {renderRichText(description, footnotesEnabled)}
        </Statistic.Description>
      )}
    </Statistic>
  )
}
