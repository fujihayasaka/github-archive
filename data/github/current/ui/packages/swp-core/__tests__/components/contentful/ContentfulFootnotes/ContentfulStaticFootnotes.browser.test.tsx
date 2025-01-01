import {BLOCKS, INLINES} from '@contentful/rich-text-types'
import {render, screen} from '@testing-library/react'

import {describe, expect, it} from '@github-ui/tests'

import {ContentfulStaticFootnotes} from '../../../../components/contentful/ContentfulFootnotes/ContentfulStaticFootnotes'
import type {PrimerComponentStaticFootnotes} from '../../../../schemas/contentful/contentTypes/primerComponentStaticFootnotes'

const component: PrimerComponentStaticFootnotes = {
  sys: {
    id: '58o4OwSC162KDUPUGAFwdo',
    contentType: {
      sys: {
        id: 'primerComponentStaticFootnotes',
      },
    },
  },
  fields: {
    content: {
      nodeType: BLOCKS.DOCUMENT,
      data: {},
      content: [
        {
          data: {},
          content: [
            {
              data: {},
              marks: [],
              value: '',
              nodeType: 'text',
            },
            {
              data: {
                target: {
                  metadata: {
                    tags: [],
                    concepts: [],
                  },
                  sys: {
                    space: {
                      sys: {
                        type: 'Link',
                        linkType: 'Space',
                        id: '8aevphvgewt8',
                      },
                    },
                    id: '1iLexwNIn1D7nxCNTG4vJq',
                    type: 'Entry',
                    createdAt: '2025-04-03T15:50:27.967Z',
                    updatedAt: '2025-04-03T15:50:27.967Z',
                    environment: {
                      sys: {
                        id: 'sgolob-sandbox',
                        type: 'Link',
                        linkType: 'Environment',
                      },
                    },
                    publishedVersion: 4,
                    revision: 1,
                    contentType: {
                      sys: {
                        type: 'Link',
                        linkType: 'ContentType',
                        id: 'link',
                      },
                    },
                    locale: 'en-US',
                  },
                  fields: {
                    text: 'Example footnote link relative',
                    href: '/features/actions',
                    openInNewTab: false,
                  },
                },
              },
              content: [],
              nodeType: INLINES.EMBEDDED_ENTRY,
            },
            {
              data: {},
              marks: [],
              value: 'Footnote 1',
              nodeType: 'text',
            },
          ],
          nodeType: BLOCKS.PARAGRAPH,
        },
        {
          data: {},
          content: [
            {
              data: {},
              marks: [],
              value: 'Footnote 2',
              nodeType: 'text',
            },
            {
              data: {
                target: {
                  metadata: {
                    tags: [],
                    concepts: [],
                  },
                  sys: {
                    space: {
                      sys: {
                        type: 'Link',
                        linkType: 'Space',
                        id: '8aevphvgewt8',
                      },
                    },
                    id: '3Sgl99sKah2iSIgXSWAKYd',
                    type: 'Entry',
                    createdAt: '2025-04-03T15:51:20.703Z',
                    updatedAt: '2025-04-03T15:51:20.703Z',
                    environment: {
                      sys: {
                        id: 'sgolob-sandbox',
                        type: 'Link',
                        linkType: 'Environment',
                      },
                    },
                    publishedVersion: 4,
                    revision: 1,
                    contentType: {
                      sys: {
                        type: 'Link',
                        linkType: 'ContentType',
                        id: 'link',
                      },
                    },
                    locale: 'en-US',
                  },
                  fields: {
                    text: 'example footnote link external',
                    href: 'https://docs.github.com/en/github-models',
                    openInNewTab: true,
                  },
                },
              },
              content: [],
              nodeType: INLINES.EMBEDDED_ENTRY,
            },
            {
              data: {},
              marks: [],
              value: '',
              nodeType: 'text',
            },
          ],
          nodeType: BLOCKS.PARAGRAPH,
        },
      ],
    },
    visuallyHiddenHeading: 'Additional Notes',
  },
}

describe('ContentfulStaticFootnotes', () => {
  it('Renders the footnotes', () => {
    render(<ContentfulStaticFootnotes component={component} />)

    expect(screen.getByText('Footnote 1')).toBeInTheDocument()
    expect(screen.getByText('Footnote 2')).toBeInTheDocument()
  })

  it('Renders the visually hidden heading', () => {
    render(<ContentfulStaticFootnotes component={component} />)

    expect(screen.getByText('Additional Notes')).toBeInTheDocument()
  })

  it('Supports links opening in new tab', () => {
    render(<ContentfulStaticFootnotes component={component} />)

    const link = screen.getByText('example footnote link external')
    expect(link).toHaveAttribute('href', 'https://docs.github.com/en/github-models')
    expect(link).toHaveAttribute('target', '_blank')
  })
})
