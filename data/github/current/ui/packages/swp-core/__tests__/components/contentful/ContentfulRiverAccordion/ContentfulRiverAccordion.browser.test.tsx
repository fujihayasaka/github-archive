import {BLOCKS} from '@contentful/rich-text-types'
import {render, screen} from '@testing-library/react'

import {beforeEach, describe, expect, it, vi} from '@github-ui/tests'

import {ContentfulRiverAccordion} from '../../../../components/contentful/ContentfulRiverAccordion/ContentfulRiverAccordion'
import type {PrimerComponentRiverAccordion} from '../../../../schemas/contentful/contentTypes/primerComponentRiverAccordion'
import type {PrimerComponentRiverAccordionItem} from '../../../../schemas/contentful/contentTypes/primerComponentRiverAccordionItem'

const component: PrimerComponentRiverAccordion = {
  sys: {
    id: 'component-id',
    contentType: {sys: {id: 'primerComponentRiverAccordion'}},
  },
  fields: {
    htmlId: 'accordion-1',
    align: 'start',
    riverAccordionItems: [
      {
        sys: {id: 'item-1', contentType: {sys: {id: 'primerComponentRiverAccordionItem'}}},
        fields: {
          heading: {
            nodeType: BLOCKS.DOCUMENT,
            data: {},
            content: [
              {
                data: {},
                content: [{data: {}, marks: [], value: 'Heading 1', nodeType: 'text'}],
                nodeType: BLOCKS.PARAGRAPH,
              },
            ],
          },
          text: {
            nodeType: BLOCKS.DOCUMENT,
            data: {},
            content: [
              {
                data: {},
                content: [{data: {}, marks: [], value: 'Text content', nodeType: 'text'}],
                nodeType: BLOCKS.PARAGRAPH,
              },
            ],
          },
          image: {
            fields: {
              description: '',
              file: {url: '//example.com/image1.png'},
            },
          },
          imageAlt: 'Image alt text',
          callToAction: {
            sys: {id: 'cta-1', contentType: {sys: {id: 'link'}}},
            fields: {
              href: 'https://example.com',
              text: 'Click here',
              openInNewTab: false,
            },
          },
        },
      },
    ],
  },
}

const noCTAComponent: PrimerComponentRiverAccordion = {
  ...component,
  fields: {
    ...component.fields,
    riverAccordionItems: [
      {
        ...(component.fields.riverAccordionItems[0] as PrimerComponentRiverAccordionItem),
        fields: {
          ...(component.fields.riverAccordionItems[0]?.fields ?? {}),
          heading: component.fields.riverAccordionItems[0]?.fields.heading ?? {
            nodeType: BLOCKS.DOCUMENT,
            data: {},
            content: [],
          },
          text: component.fields.riverAccordionItems[0]?.fields.text ?? {
            nodeType: BLOCKS.DOCUMENT,
            data: {},
            content: [],
          },
          callToAction: undefined,
          image: component.fields.riverAccordionItems[0]?.fields.image ?? {
            fields: {
              file: {url: ''},
              description: '',
            },
          },
        },
      },
    ],
  },
}

describe('ContentfulRiverAccordion', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('renders all accordion items with heading, text, image, and CTA', () => {
    render(<ContentfulRiverAccordion component={component} />)

    expect(screen.getByText('Heading 1')).toBeInTheDocument()
    expect(screen.getByText('Text content')).toBeInTheDocument()
    expect(screen.getByRole('img')).toHaveAttribute('alt', 'Image alt text')
    expect(screen.getByRole('link')).toHaveAttribute('href', 'https://example.com')
    expect(screen.getByText('Click here')).toBeInTheDocument()
  })

  it('handles missing CTA gracefully', () => {
    render(<ContentfulRiverAccordion component={noCTAComponent} />)

    expect(screen.getByText('Heading 1')).toBeInTheDocument()
    expect(screen.getByText('Text content')).toBeInTheDocument()
    expect(screen.getByRole('img')).toHaveAttribute('alt', 'Image alt text')
    expect(screen.queryByRole('link')).not.toBeInTheDocument()
  })
})
