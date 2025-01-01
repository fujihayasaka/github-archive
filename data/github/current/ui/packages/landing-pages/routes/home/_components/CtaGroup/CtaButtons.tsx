import {Button} from '@primer/react-brand'

import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import type {GenericCTAGroup} from '../../../../brand/lib/types/contentful'

type Props = {
  contentfulContent: GenericCTAGroup
  location: string
}

export function CtaButtons(props: Props) {
  const {contentfulContent, location} = props

  const {primary, secondary} = contentfulContent.fields

  return (
    <div className={`CtaForm${location !== 'hero' ? ' CTAForm-footer' : ''}`}>
      <Button
        className={`CtaForm-primaryAction ${location === 'hero' ? 'js-hero-action' : ''}`}
        as="a"
        href={primary.fields.href}
        variant="primary"
        hasArrow={false}
        {...getAnalyticsEvent({
          action: primary.fields.text,
          tag: 'button',
          context: 'CTAs',
          location,
        })}
      >
        {primary.fields.text}
      </Button>

      {secondary ? (
        <Button
          className={`CtaForm-secondaryAction ${location === 'hero' ? 'js-hero-action' : ''}`}
          as="a"
          href={secondary.fields.href}
          hasArrow={false}
          {...getAnalyticsEvent({
            action: secondary.fields.text,
            tag: 'button',
            context: 'CTAs',
            location,
          })}
        >
          {secondary.fields.text}
        </Button>
      ) : null}
    </div>
  )
}
