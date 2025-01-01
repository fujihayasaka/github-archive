import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, MARKS} from '@contentful/rich-text-types'
import {Link, RiverBreakout, Text} from '@primer/react-brand'

import type {PrimerComponentRiverBreakout} from '../../../schemas/contentful/contentTypes/primerComponentRiverBreakout'
import {ContentfulTimeline} from '../ContentfulTimeline/ContentfulTimeline'
import {getAnalyticsEvent} from '../../../lib/utils/analytics'

export type ContentfulRiverBreakoutProps = {
  component: PrimerComponentRiverBreakout
  className?: string
}

export function ContentfulRiverBreakout({component, className}: ContentfulRiverBreakoutProps) {
  const {a11yHeading, text, trailingComponent, image, imageAlt, callToAction, hasShadow} = component.fields

  /**
   * We use an empty fragment if `props.content.cta` is not defined for compliance
   * with `River.Content` types (`River.Content` does not accept `null` as children).
   */
  const ctaLink =
    callToAction !== undefined ? (
      <Link
        variant="default"
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
    <RiverBreakout className={className}>
      <RiverBreakout.A11yHeading>{a11yHeading}</RiverBreakout.A11yHeading>
      <RiverBreakout.Visual hasShadow={hasShadow}>
        {image !== undefined ? (
          <img src={image?.fields.file.url} alt={imageAlt ?? image?.fields.description ?? ''} />
        ) : null}
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
            },
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
          }) as any
        }

        {ctaLink}
      </RiverBreakout.Content>
    </RiverBreakout>
  )
}
