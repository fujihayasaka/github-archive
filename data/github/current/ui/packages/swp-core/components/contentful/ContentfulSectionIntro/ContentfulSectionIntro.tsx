import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, MARKS} from '@contentful/rich-text-types'
import type {HeadingSizes} from '@primer/react-brand'
import {SectionIntro} from '@primer/react-brand'

import type {PrimerComponentSectionIntro} from '../../../schemas/contentful/contentTypes/primerComponentSectionIntro'
import {documentToPlainTextString, getAnalyticsEvent} from '../../../lib/utils/analytics'

export type ContentfulSectionIntroProps = {
  component: PrimerComponentSectionIntro

  fullWidth?: boolean
  className?: string
  headingSize?: (typeof HeadingSizes)[number]
}

export function ContentfulSectionIntro({component, fullWidth, headingSize, className}: ContentfulSectionIntroProps) {
  return (
    <SectionIntro
      className={className}
      align={component.fields.align}
      fullWidth={fullWidth ?? component.fields.fullWidth}
    >
      {typeof component.fields.heading === 'string' ? (
        <SectionIntro.Heading size={headingSize}>{component.fields.heading}</SectionIntro.Heading>
      ) : (
        documentToReactComponents(component.fields.heading, {
          renderMark: {
            /**
             * We use <em> to benefit from Primer Brand's special styling for <em> tags:
             * https://primer.style/brand/components/SectionIntro#emphasized-text
             */
            [MARKS.BOLD]: text => <em>{text}</em>,
          },
          renderNode: {
            [BLOCKS.PARAGRAPH]: (_, children) => (
              <SectionIntro.Heading size={headingSize}>{children}</SectionIntro.Heading>
            ),
          },
        })
      )}

      {component.fields.description !== undefined
        ? documentToReactComponents(component.fields.description, {
            renderNode: {
              [BLOCKS.PARAGRAPH]: (_, children) => <SectionIntro.Description>{children}</SectionIntro.Description>,
            },
          })
        : null}

      {component.fields.link !== undefined && (
        <SectionIntro.Link
          variant="default"
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
