import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, MARKS} from '@contentful/rich-text-types'
import type {HeadingSizes} from '@primer/react-brand'
import {SectionIntro, Image} from '@primer/react-brand'

import type {PrimerComponentSectionIntro} from '../../../schemas/contentful/contentTypes/primerComponentSectionIntro'
import {documentToPlainTextString, getAnalyticsEvent} from '../../../lib/utils/analytics'
import {getPrimerIcon} from '../../../lib/utils/icons'
import {getImageSources} from '../../../lib/utils/images'

export type ContentfulSectionIntroProps = {
  component: PrimerComponentSectionIntro

  fullWidth?: boolean
  className?: string
  headingSize?: (typeof HeadingSizes)[number]
}

export function ContentfulSectionIntro({component, fullWidth, headingSize, className}: ContentfulSectionIntroProps) {
  const {label, leadingComponent, leadingComponentSize} = component.fields
  const Octicon = getPrimerIcon(label?.fields.icon)

  return (
    <SectionIntro
      className={className}
      align={component.fields.align}
      fullWidth={fullWidth ?? component.fields.fullWidth}
      id={component.fields.htmlId}
      leadingComponent={
        leadingComponent
          ? () => (
              <Image
                as="picture"
                src={`${leadingComponent.fields.file.url}?fm=webp`}
                sources={getImageSources(leadingComponent.fields.file.url, {maxWidth: 64})}
                alt={leadingComponent.fields.description || ''}
                loading="lazy"
                width={leadingComponentSize && leadingComponentSize === 'large' ? 64 : 40}
                height={leadingComponentSize && leadingComponentSize === 'large' ? 64 : 40}
                className="d-block"
                style={{display: 'block'}}
              />
            )
          : undefined
      }
    >
      {label && (
        <SectionIntro.Label
          size={label.fields.size}
          color={label.fields.color}
          {...(Octicon ? {leadingVisual: <Octicon />} : {})}
        >
          {label.fields.text}
        </SectionIntro.Label>
      )}
      <SectionIntro.Heading size={headingSize}>
        {typeof component.fields.heading === 'string'
          ? component.fields.heading
          : documentToReactComponents(component.fields.heading, {
              renderMark: {
                /**
                 * We use <em> to benefit from Primer Brand's special styling for <em> tags:
                 * https://primer.style/brand/components/SectionIntro#emphasized-text
                 */
                [MARKS.BOLD]: text => <em>{text}</em>,
              },
              renderNode: {
                [BLOCKS.PARAGRAPH]: (_, children) => [children, <br key="line-break" />],
              },
            })}
      </SectionIntro.Heading>
      {component.fields.description !== undefined
        ? documentToReactComponents(component.fields.description, {
            renderNode: {
              [BLOCKS.PARAGRAPH]: (_, children) => <SectionIntro.Description>{children}</SectionIntro.Description>,
            },
          })
        : null}

      {component.fields.link !== undefined && (
        <SectionIntro.Link
          variant={component.fields.linkVariant ?? 'accent'}
          href={component.fields.link.fields.href}
          data-ref={`section-intro-link-${component.fields.link.sys.id}`}
          {...getAnalyticsEvent({
            action: component.fields.link?.fields.text,
            tag: 'link',
            context: 'section_intro',
            location:
              typeof component.fields.heading === 'string'
                ? component.fields.heading
                : documentToPlainTextString(component.fields.heading),
          })}
        >
          {component.fields.link.fields.text}
        </SectionIntro.Link>
      )}
    </SectionIntro>
  )
}
