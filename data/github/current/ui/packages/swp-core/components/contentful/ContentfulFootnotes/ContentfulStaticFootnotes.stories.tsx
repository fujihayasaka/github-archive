import '@primer/react-brand/lib/css/main.css'

import type {Meta, StoryObj} from '@storybook/react'

import {ContentfulStaticFootnotes} from './ContentfulStaticFootnotes'
import {BLOCKS, INLINES} from '@contentful/rich-text-types'

const meta: Meta<typeof ContentfulStaticFootnotes> = {
  title: 'Mkt/Swp/Contentful/ContentfulStaticFootnotes',
  component: ContentfulStaticFootnotes,
}

export default meta

type Story = StoryObj<typeof ContentfulStaticFootnotes>

export const Default: Story = {
  args: {
    component: {
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
            {
              data: {},
              content: [
                {
                  data: {},
                  marks: [],
                  value:
                    'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit ',
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
                        id: '5NSGJ6rTZE10GxJYujcZHz',
                        type: 'Entry',
                        createdAt: '2025-02-28T18:32:35.547Z',
                        updatedAt: '2025-04-01T17:10:28.985Z',
                        environment: {
                          sys: {
                            id: 'sgolob-sandbox',
                            type: 'Link',
                            linkType: 'Environment',
                          },
                        },
                        publishedVersion: 10,
                        revision: 6,
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
                        text: 'Plans & pricing',
                        href: 'https://github.com/security/plans',
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
                  value:
                    ' esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.',
                  nodeType: 'text',
                },
              ],
              nodeType: BLOCKS.PARAGRAPH,
            },
          ],
        },
        visuallyHiddenHeading: 'Additional Notes',
      },
    },
  },
}
