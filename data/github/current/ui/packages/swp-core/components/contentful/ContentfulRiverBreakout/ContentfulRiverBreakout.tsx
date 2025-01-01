import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, INLINES, MARKS} from '@contentful/rich-text-types'
import {Link, RiverBreakout, Text} from '@primer/react-brand'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import type {PrimerComponentRiverBreakout} from '../../../schemas/contentful/contentTypes/primerComponentRiverBreakout'
import {ContentfulTimeline} from '../ContentfulTimeline/ContentfulTimeline'
import {documentToPlainTextString, getAnalyticsEvent} from '../../../lib/utils/analytics'
import {getImageSources, MAX_CONTENT_WIDTH} from '../../../lib/utils/images'
import {ContentfulInlineFootnote} from '../ContentfulFootnotes/ContentfulInlineFootnote'
import {ContentfulAnimatedVideo} from '../ContentfulAnimatedVideo/ContentfulAnimatedVideo'

export type ContentfulRiverBreakoutProps = {
  component: PrimerComponentRiverBreakout
  className?: string
}

export function ContentfulRiverBreakout({component, className}: ContentfulRiverBreakoutProps) {
  const {
    a11yHeading,
    headingLevel,
    text,
    trailingComponent,
    image,
    imageAlt,
    callToAction,
    callToActionVariant,
    hasShadow,
    htmlId,
    animatedVideo,
  } = component.fields

  const footnotesEnabled = isFeatureEnabled('contentful_lp_footnotes')
  /**
   * We use an empty fragment if `props.content.cta` is not defined for compliance
   * with `River.Content` types (`River.Content` does not accept `null` as children).
   */
  const ctaLink =
    callToAction !== undefined ? (
      <Link
        variant={callToActionVariant ?? 'accent'}
        data-ref={`river-breakout-cta-link-${callToAction.sys.id}`}
        href={callToAction.fields.href}
        {...getAnalyticsEvent({
          action: callToAction.fields.text,
          tag: 'link',
          context: 'CTAs',
          location: a11yHeading,
        })}
      >
        {callToAction.fields.text}
      </Link>
    ) : (
      <></>
    )

  const getTrailingComponent = trailingComponent
    ? () => <ContentfulTimeline component={trailingComponent} />
    : undefined

  return (
    <RiverBreakout id={htmlId} className={className}>
      <RiverBreakout.A11yHeading as={headingLevel}>{a11yHeading}</RiverBreakout.A11yHeading>
      <RiverBreakout.Visual hasShadow={hasShadow}>
        {image !== undefined ? <OptimizedVisual image={image} imageAlt={imageAlt} /> : null}
        {animatedVideo && !image && (
          <ContentfulAnimatedVideo component={animatedVideo} analyticsLocation="river_breakout" />
        )}
      </RiverBreakout.Visual>
      <RiverBreakout.Content trailingComponent={getTrailingComponent}>
        {
          documentToReactComponents(text, {
            renderMark: {
              [MARKS.BOLD]: children => <em>{children}</em>,
            },
            renderNode: {
              [BLOCKS.PARAGRAPH]: (_, children) => {
                return <Text>{children}</Text>
              },
              [INLINES.EMBEDDED_ENTRY]: node => {
                if (footnotesEnabled && node.data.target.sys.contentType.sys.id === 'inlineFootnote') {
                  return (
                    <ContentfulInlineFootnote
                      component={node.data.target}
                      analyticsLocation={documentToPlainTextString(text)}
                      size="large"
                    />
                  )
                }
                return null
              },
            },
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
          }) as any
        }

        {ctaLink}
      </RiverBreakout.Content>
    </RiverBreakout>
  )
}

type OptimizedVisualProps = {
  image: PrimerComponentRiverBreakout['fields']['image']
  imageAlt?: string
}

function OptimizedVisual({image, imageAlt}: OptimizedVisualProps) {
  if (!image) return null

  const imageSources = getImageSources(image.fields.file.url, {maxWidth: MAX_CONTENT_WIDTH})

  return (
    <picture>
      {imageSources.map(source => (
        <source key={source.media} srcSet={source.srcset} media={source.media} />
      ))}
      <img src={image.fields.file.url} alt={imageAlt ?? image.fields.description ?? ''} />
    </picture>
  )
}
