import type {Document} from '@contentful/rich-text-types'
import {render, screen} from '@testing-library/react'

import {describe, expect, it} from '@github-ui/tests'

import {ContentfulCard} from '../../../../components/contentful/ContentfulCard/ContentfulCard'

describe('ContentfulCard', () => {
  it('Renders the correct Octicon', () => {
    render(
      <ContentfulCard
        component={{
          sys: {
            id: 'foo',
            contentType: {
              sys: {
                id: 'primerComponentCard',
              },
            },
          },
          fields: {
            href: '#',
            heading: 'Example heading',
            icon: 'logo-github',
            label: {
              sys: {
                contentType: {
                  sys: {
                    id: 'primerComponentLabel',
                  },
                },
                id: 'primer-label',
              },
              fields: {
                text: 'Card Label',
                size: 'medium',
                color: 'purple',
              },
            },
          },
        }}
      />,
    )

    expect(screen.getByTestId('logo-github-#')).toBeInTheDocument()
    expect(screen.getByText('Card Label')).toBeInTheDocument()
    expect(screen.getByText('Example heading')).toBeInTheDocument()
  })
  it('Renders an image', () => {
    render(
      <ContentfulCard
        component={{
          sys: {
            id: 'foo',
            contentType: {
              sys: {
                id: 'primerComponentCard',
              },
            },
          },
          fields: {
            href: '#',
            heading: 'Example heading',
            icon: 'logo-github',
            image: {
              fields: {
                description: 'A description',
                file: {
                  url: 'https://example.com/image.jpg',
                },
              },
            },
          },
        }}
      />,
    )

    expect(screen.getByAltText('A description')).toBeInTheDocument()
  })

  it('Renders the correct RichText', () => {
    const description = {
      nodeType: 'document',
      data: {},
      content: [
        {
          nodeType: 'paragraph',
          data: {},
          content: [
            {
              nodeType: 'text',
              value: 'Hello, world',
              marks: [],
              data: {},
            },
          ],
        },
      ],
    } as Document

    render(
      <ContentfulCard
        component={{
          sys: {
            id: 'foo',
            contentType: {
              sys: {
                id: 'primerComponentCard',
              },
            },
          },
          fields: {href: '#', heading: 'Example heading', description},
        }}
      />,
    )

    expect(screen.getByText('Hello, world')).toBeInTheDocument()
    expect(screen.queryByRole('img')).toBeNull()
  })
})
