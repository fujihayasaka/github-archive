import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {useFootnotes} from './FootnotesContext'
import {Footnotes, InlineLink} from '@primer/react-brand'
import {BLOCKS, INLINES} from '@contentful/rich-text-types'
import {getAnalyticsEvent} from '../../../lib/utils/analytics'

export type ContentfulInlineFootnotesListProps = {
  className?: string
}

export const ContentfulInlineFootnotesList = ({className}: ContentfulInlineFootnotesListProps) => {
  const context = useFootnotes()
  if (!context || context.footnotes.length === 0) {
    return null
  }

  return (
    <Footnotes className={className}>
      {context.footnotes.map(footnote => {
        const targetId =
          context.lastClickedReferenceIds[footnote.fields.anchorId] ?? `${footnote.fields.anchorId}-ref-0`

        return (
          <Footnotes.Item key={footnote.sys.id} id={footnote.fields.anchorId} href={`#${targetId}`}>
            {documentToReactComponents(footnote.fields.text, {
              renderNode: {
                [BLOCKS.PARAGRAPH]: (_, children) => children,
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
          </Footnotes.Item>
        )
      })}
    </Footnotes>
  )
}
