import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, INLINES, MARKS} from '@contentful/rich-text-types'
import {Heading, InlineLink, Link, River, Text, Label, type LinkProps} from '@primer/react-brand'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import type {PrimerComponentRiver} from '../../../schemas/contentful/contentTypes/primerComponentRiver'
import {ContentfulTimeline} from '../ContentfulTimeline/ContentfulTimeline'
import {documentToPlainTextString, getAnalyticsEvent} from '../../../lib/utils/analytics'
import {getPrimerIcon} from '../../../lib/utils/icons'
import styles from './ContentfulRiver.module.css'
import {getImageSources} from '../../../lib/utils/images'

export type ContentfulRiverProps = {
  component: PrimerComponentRiver
  linkProps?: LinkProps
  className?: string
}

export function ContentfulRiver({component, linkProps, className}: ContentfulRiverProps) {
  const {
    trailingComponent,
    label,
    callToAction,
    callToActionVariant,
    align,
    imageTextRatio,
    hasShadow,
    image,
    imageAlt,
    videoSrc,
    heading,
    text,
    htmlId,
  } = component.fields

  const optimizeImageEnabled = isFeatureEnabled('contentful_lp_optimize_image')

  const Octicon = getPrimerIcon(label?.fields.icon)
  /**
   * We use an empty fragment if `props.content.cta` is not defined for compliance
   * with `River.Content` types (`River.Content` does not accept `null` as children).
   */
  const ctaLink =
    callToAction !== undefined ? (
      <Link
        variant={callToActionVariant ?? 'accent'}
        href={callToAction.fields.href}
        data-ref={`river-cta-link-${callToAction.sys.id}`}
        {...(linkProps ?? {})}
        {...getAnalyticsEvent({
          action: callToAction.fields.text,
          tag: 'link',
          context: 'CTAs',
          location: heading,
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
    <River id={htmlId} className={className} align={align} imageTextRatio={imageTextRatio}>
      <River.Visual hasShadow={hasShadow} className="width-full">
        {image !== undefined ? (
          optimizeImageEnabled ? (
            <OptimizedVisual image={image} imageAlt={imageAlt} />
          ) : (
            <img src={image.fields.file.url} alt={imageAlt ?? image.fields.description ?? ''} />
          )
        ) : videoSrc !== undefined ? (
          <div className="position-relative" style={{paddingBottom: '55%'}}>
            {/* eslint-disable-next-line @eslint-react/dom/no-missing-iframe-sandbox */}
            <iframe
              role="application"
              className="border-0 width-full height-full position-absolute top-0 left-0"
              src={videoSrc}
              title={heading}
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
              allowFullScreen
            />
          </div>
        ) : null}
      </River.Visual>

      <River.Content trailingComponent={getTrailingComponent}>
        {label && (
          <Label size={label.fields.size} color={label.fields.color} {...(Octicon ? {leadingVisual: <Octicon />} : {})}>
            {label.fields.text}
          </Label>
        )}

        {/* `h3` is the default heading level for River.Content */}
        <Heading as="h3">{heading}</Heading>

        {
          documentToReactComponents(text, {
            renderMark: {
              [MARKS.BOLD]: children => <em className={styles.emboldened}>{children}</em>,
            },
            renderNode: {
              [BLOCKS.PARAGRAPH]: (_, children) => {
                return <Text>{children}</Text>
              },
              [INLINES.HYPERLINK]: (node, children) => {
                return (
                  <InlineLink
                    data-ref={`river-inline-link-${component.sys.id}`}
                    href={node.data.uri}
                    {...getAnalyticsEvent({
                      action: documentToPlainTextString(node, ' '),
                      tag: 'hyperlink',
                      location: heading,
                    })}
                  >
                    {children}
                  </InlineLink>
                )
              },
            },
            /**
             * 2023-09-25:
             * Primer Brand's River types are very strict, and altough we're going to
             * render a fully-compliant River.Content, types from documentToReactComponents
             * are not compatible with River.Content types. We're casting to `any` so the compiler
             * doesn't complain.
             */
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
          }) as any
        }

        {ctaLink}
      </River.Content>
    </River>
  )
}

type OptimizedVisualProps = {
  image: PrimerComponentRiver['fields']['image']
  imageAlt?: string
}

function OptimizedVisual({image, imageAlt}: OptimizedVisualProps) {
  if (!image) return null

  const imageSources = getImageSources(image.fields.file.url, {maxWidth: 720})

  return (
    // Primer Brand does not apply styles properly to images within a picture element. This is a workaround.
    // We should remove this code if/when the Primer Brand bug is fixed: https://github.com/primer/brand/issues/911#issuecomment-2666851941
    <picture style={{width: '100%', height: '100%'}}>
      {imageSources.map(source => (
        <source key={source.media} srcSet={source.srcset} media={source.media} />
      ))}
      <img src={image.fields.file.url} alt={imageAlt ?? image.fields.description ?? ''} />
    </picture>
  )
}
