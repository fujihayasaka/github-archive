import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS, INLINES} from '@contentful/rich-text-types'
import type {AccordionToggleColors} from '@primer/react-brand'
import {FAQ, InlineLink, OrderedList, Stack, Text, UnorderedList} from '@primer/react-brand'
import React from 'react'

import type {PrimerComponentFaq} from '../../../schemas/contentful/contentTypes/primerComponentFaq'
import {documentToPlainTextString, getAnalyticsEvent} from '../../../lib/utils/analytics'

export type ContentfulFaqProps = {
  component: PrimerComponentFaq
  faqGroupHeading: string
  id?: string
  plusIconColor?: (typeof AccordionToggleColors)[number]
}

export const ContentfulFaq = (props: ContentfulFaqProps) => renderContentfulFaq(props)

/**
 * This helper function renders a Primer Brand FAQ component from a given PrimerComponentFaq object.
 * It's particularly useful for rendering FAQ components within non-FAQ components, like ContentfulFaqGroup.
 * Note: Primer Brand validations restrict rendering non-Primer Brand FAQ components within FAQGroup
 * (e.g., a ContentfulFaq component inside an FAQGroup won't work).
 *
 * @param {PrimerComponentFaq} component - The PrimerComponentFaq object to be rendered.
 * @returns A Primer Brand FAQ component.
 */
export function renderContentfulFaq({component, faqGroupHeading, id, plusIconColor}: ContentfulFaqProps) {
  return (
    <FAQ id={id} className="px-4" key={component.sys.id}>
      <FAQ.Heading>{component.fields.heading}</FAQ.Heading>

      {(component.fields.blocks ?? []).map((block, blockIndex) => (
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <React.Fragment key={blockIndex}>
          {block.fields.heading !== undefined && <FAQ.Subheading>{block.fields.heading}</FAQ.Subheading>}

          {(block.fields.questions ?? []).map(question => (
            <FAQ.Item key={question.sys.id}>
              <FAQ.Question
                toggleColor={plusIconColor}
                {...getAnalyticsEvent({
                  action: question.fields.question,
                  tag: 'button',
                  location: faqGroupHeading,
                })}
              >
                {question.fields.question}
              </FAQ.Question>

              <FAQ.Answer>
                <Stack direction="vertical" gap="condensed" padding="none">
                  {documentToReactComponents(question.fields.answer, {
                    renderNode: {
                      [BLOCKS.PARAGRAPH]: (_, children) => (
                        <Text as="p" size="300">
                          {children}
                        </Text>
                      ),
                      [BLOCKS.OL_LIST]: (_, children) => <OrderedList>{children}</OrderedList>,
                      [BLOCKS.UL_LIST]: (_, children) => <UnorderedList>{children}</UnorderedList>,
                      [BLOCKS.LIST_ITEM]: (_, children) => (
                        /**
                         * We ca use either UnorderedList.Item or OrderedList.Item here.
                         */
                        <UnorderedList.Item>{children}</UnorderedList.Item>
                      ),
                      [INLINES.HYPERLINK]: (node, children) => (
                        <InlineLink
                          data-ref={`faq-link-${question.sys.id}`}
                          href={node.data.uri}
                          {...getAnalyticsEvent({
                            action: documentToPlainTextString(node, ' '),
                            tag: 'hyperlink',
                            context: question.fields.question,
                            location: faqGroupHeading,
                          })}
                        >
                          {children}
                        </InlineLink>
                      ),
                    },
                  })}
                </Stack>
              </FAQ.Answer>
            </FAQ.Item>
          ))}
        </React.Fragment>
      ))}
    </FAQ>
  )
}
