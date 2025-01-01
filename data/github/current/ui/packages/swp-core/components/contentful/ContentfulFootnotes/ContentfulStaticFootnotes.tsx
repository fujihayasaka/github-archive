import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {Footnotes, InlineLink} from '@primer/react-brand'
import {BLOCKS, INLINES} from '@contentful/rich-text-types'

import type {PrimerComponentStaticFootnotes} from '../../../schemas/contentful/contentTypes/primerComponentStaticFootnotes'
import {getAnalyticsEvent} from '../../../lib/utils/analytics'

type ContentfulStaticFootnotesProps = {
  component: PrimerComponentStaticFootnotes
  className?: string
}

export const ContentfulStaticFootnotes = ({component, className}: ContentfulStaticFootnotesProps) => {
  return (
    <Footnotes as="div" className={className} visuallyHiddenHeading={component.fields.visuallyHiddenHeading}>
      {documentToReactComponents(component.fields.content, {
        renderNode: {
          [BLOCKS.PARAGRAPH]: (_, children) => <Footnotes.Item>{children}</Footnotes.Item>,
          [INLINES.EMBEDDED_ENTRY]: node => {
            if (node.data.target.sys.contentType.sys.id === 'link') {
              const {text, href, openInNewTab} = node.data.target.fields
              return (
                <InlineLink
                  href={href}
                  target={openInNewTab ? '_blank' : undefined}
                  {...getAnalyticsEvent({
                    action: text,
                    tag: 'hyperlink',
                    context: 'footnotes',
                    location: 'footer',
                  })}
                >
                  {text}
                </InlineLink>
              )
            }

            return ''
          },
        },
      })}
    </Footnotes>
  )
}
