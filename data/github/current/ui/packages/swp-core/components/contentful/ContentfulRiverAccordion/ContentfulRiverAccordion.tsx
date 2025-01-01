import {Link, RiverAccordion, Text} from '@primer/react-brand'
import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, INLINES, MARKS} from '@contentful/rich-text-types'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import type {PrimerComponentRiverAccordion} from '../../../schemas/contentful/contentTypes/primerComponentRiverAccordion'
import {getImageSources, MAX_CONTENT_WIDTH} from '../../../lib/utils/images'
import {documentToPlainTextString, getAnalyticsEvent} from '../../../lib/utils/analytics'
import {ContentfulInlineFootnote} from '../ContentfulFootnotes/ContentfulInlineFootnote'

export type ContentfulRiverAccordionProps = {
  component: PrimerComponentRiverAccordion
  className?: string
}

export function ContentfulRiverAccordion({component, className}: ContentfulRiverAccordionProps) {
  const {align, riverAccordionItems, htmlId} = component.fields

  const footnotesEnabled = isFeatureEnabled('contentful_lp_footnotes')

  return (
    <RiverAccordion id={htmlId} align={align} className={className}>
      {riverAccordionItems.map(item => {
        const {headingLevel, heading, text, image, imageAlt, callToAction, callToActionVariant} = item.fields
        const headingString = documentToPlainTextString(heading)
        const imageSources = getImageSources(image.fields.file.url, {maxWidth: MAX_CONTENT_WIDTH})

        return (
          <RiverAccordion.Item key={item.sys.id}>
            <RiverAccordion.Heading
              as={headingLevel}
              {...getAnalyticsEvent({
                action: headingString,
                tag: 'button',
                location: headingString,
              })}
            >
              {documentToReactComponents(heading, {
                renderMark: {
                  [MARKS.BOLD]: children => <em>{children}</em>,
                },
                renderNode: {
                  [BLOCKS.PARAGRAPH]: (_, children) => children,
                },
              })}
            </RiverAccordion.Heading>
            <RiverAccordion.Content>
              <Text>
                {documentToReactComponents(text, {
                  renderMark: {
                    [MARKS.BOLD]: children => <em>{children}</em>,
                  },
                  renderNode: {
                    [BLOCKS.PARAGRAPH]: (_, children) => children,
                    [INLINES.EMBEDDED_ENTRY]: node => {
                      if (footnotesEnabled && node.data.target.sys.contentType.sys.id === 'inlineFootnote') {
                        return (
                          <ContentfulInlineFootnote
                            component={node.data.target}
                            analyticsLocation={documentToPlainTextString(text)}
                          />
                        )
                      }
                      return null
                    },
                  },
                })}
              </Text>
              {callToAction ? (
                <Link
                  variant={callToActionVariant ?? 'accent'}
                  href={callToAction.fields.href}
                  {...getAnalyticsEvent({
                    action: callToAction.fields.text,
                    tag: 'link',
                    context: 'CTAs',
                    location: headingString,
                  })}
                >
                  {callToAction.fields.text}
                </Link>
              ) : null}
            </RiverAccordion.Content>
            <RiverAccordion.Visual className="width-full">
              <picture>
                {imageSources.map(source => (
                  <source key={source.media} srcSet={source.srcset} media={source.media} />
                ))}
                <img
                  src={image.fields.file.url}
                  alt={imageAlt ?? image.fields.description ?? ''}
                  className="width-full"
                />
              </picture>
            </RiverAccordion.Visual>
          </RiverAccordion.Item>
        )
      })}
    </RiverAccordion>
  )
}
