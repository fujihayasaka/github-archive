import {BLOCKS, INLINES} from '@contentful/rich-text-types'
import {act, render, screen} from '@testing-library/react'

import {isFeatureEnabled} from '@github-ui/feature-flags'
import {beforeEach, describe, expect, it, vi} from '@github-ui/tests'

import {ContentfulInlineFootnotesList} from '../../../../components/contentful/ContentfulFootnotes/ContentfulInlineFootnotesList'
import {FootnotesProvider} from '../../../../components/contentful/ContentfulFootnotes/FootnotesContext'
import {ContentfulRiver} from '../../../../components/contentful/ContentfulRiver/ContentfulRiver'
import type {PrimerComponentRiver} from '../../../../schemas/contentful/contentTypes/primerComponentRiver'

const riverWithInlineFootnote: PrimerComponentRiver = {
  sys: {
    id: 'vvyHy7eOoGFaTTNW414F4',
    contentType: {
      sys: {
        id: 'primerComponentRiver',
      },
    },
  },
  fields: {
    align: 'end',
    imageTextRatio: '60:40',
    heading: 'Drive innovation with AI-powered developer tools',
    text: {
      nodeType: BLOCKS.DOCUMENT,
      data: {},
      content: [
        {
          nodeType: BLOCKS.PARAGRAPH,
          data: {},
          content: [
            {
              nodeType: 'text',
              value: 'AI-driven code suggestions enhances job satisfaction',
              marks: [
                {
                  type: 'bold',
                },
              ],
              data: {},
            },
            {
              nodeType: 'text',
              value: ' and focus for ',
              marks: [],
              data: {},
            },
            {
              nodeType: INLINES.HYPERLINK,
              data: {
                uri: 'https://github.blog/2022-09-07-research-quantifying-github-copilots-impact-on-developer-productivity-and-happiness/',
              },
              content: [
                {
                  nodeType: 'text',
                  value: '60-75% of developers',
                  marks: [],
                  data: {},
                },
              ],
            },
            {
              nodeType: 'text',
              value: ' ',
              marks: [],
              data: {},
            },
            {
              nodeType: INLINES.EMBEDDED_ENTRY,
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
                    id: '5iealwZbyuqZecryAbDezI',
                    type: 'Entry',
                    createdAt: '2025-04-02T17:19:19.125Z',
                    updatedAt: '2025-04-03T15:50:33.155Z',
                    environment: {
                      sys: {
                        id: 'sgolob-sandbox',
                        type: 'Link',
                        linkType: 'Environment',
                      },
                    },
                    publishedVersion: 13,
                    revision: 4,
                    contentType: {
                      sys: {
                        type: 'Link',
                        linkType: 'ContentType',
                        id: 'inlineFootnote',
                      },
                    },
                    locale: 'en-US',
                  },
                  fields: {
                    title: 'Example Footnote',
                    anchorId: 'foobar',
                    text: {
                      nodeType: BLOCKS.DOCUMENT,
                      data: {},
                      content: [
                        {
                          nodeType: BLOCKS.PARAGRAPH,
                          data: {},
                          content: [
                            {
                              nodeType: 'text',
                              value: '"Woah, this is a really cool footnote" Relative link - ',
                              marks: [],
                              data: {},
                            },
                            {
                              nodeType: INLINES.EMBEDDED_ENTRY,
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
                            },
                            {
                              nodeType: 'text',
                              value: '',
                              marks: [],
                              data: {},
                            },
                          ],
                        },
                      ],
                    },
                  },
                },
              },
              content: [],
            },
            {
              nodeType: 'text',
              value: ', reducing frustration and enabling more rewarding work.',
              marks: [],
              data: {},
            },
          ],
        },
        {
          nodeType: BLOCKS.PARAGRAPH,
          data: {},
          content: [
            {
              nodeType: 'text',
              value: '',
              marks: [],
              data: {},
            },
          ],
        },
      ],
    },
    callToAction: {
      sys: {
        id: 'cPd0frPLJEiVXo9vwV508',
        contentType: {
          sys: {
            id: 'link',
          },
        },
      },
      fields: {
        href: 'https://github.com/features/copilot',
        text: 'Explore GitHub Copilot',
        openInNewTab: false,
      },
    },
    image: {
      fields: {
        description: 'Copilot making a code suggestion',
        file: {
          url: '//images.ctfassets.net/8aevphvgewt8/eYhy9pDRGfRYNkXPU5qyP/0b0ce6489bebfebcc9948c15d141df85/AI2.webp',
        },
      },
    },
    imageAlt: 'Copilot making a code suggestion',
    hasShadow: false,
  },
}

vi.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: vi.fn(),
}))

const mockIsFeatureEnabled = vi.mocked(isFeatureEnabled)

beforeEach(() => {
  mockIsFeatureEnabled.mockReturnValue(true)
})

describe('ContentfulInlineFootnotes', () => {
  it('renders duplicate inline footnotes', () => {
    render(
      <FootnotesProvider>
        <ContentfulRiver component={riverWithInlineFootnote} />
        <ContentfulRiver component={riverWithInlineFootnote} />
        <ContentfulInlineFootnotesList />
      </FootnotesProvider>,
    )

    const inlineRefs = screen.getAllByRole('link', {name: 'Footnote 1'})
    expect(inlineRefs).toHaveLength(2)

    for (const ref of inlineRefs) {
      expect(ref).toHaveAttribute('href', '#foobar')
    }

    expect(inlineRefs[0]?.id).toBe('foobar-ref-0')
    expect(inlineRefs[1]?.id).toBe('foobar-ref-1')

    expect(screen.getAllByText(/Woah, this is a really cool footnote/i)).toHaveLength(1)

    act(() => {
      inlineRefs[1]?.click()
    })
    const backRef = screen.getByRole('link', {name: /back to content/i})
    expect(backRef).toBeInTheDocument()
    expect(backRef).toHaveAttribute('href', '#foobar-ref-1')
  })
})
