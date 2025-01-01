import '@primer/react-brand/lib/css/main.css'

import type {Meta, StoryObj} from '@storybook/react'

import {ContentfulRiverAccordion} from './ContentfulRiverAccordion'
import {BLOCKS} from '@contentful/rich-text-types'

const meta: Meta<typeof ContentfulRiverAccordion> = {
  title: 'Mkt/Swp/Contentful/ContentfulRiverAccordion',
  component: ContentfulRiverAccordion,
}

export default meta

type Story = StoryObj<typeof ContentfulRiverAccordion>

export const Default: Story = {
  args: {
    component: {
      sys: {
        id: '1NkVm8Yv1k0b7blAxZsKu3',
        contentType: {
          sys: {
            id: 'primerComponentRiverAccordion',
          },
        },
      },
      fields: {
        align: 'start',
        riverAccordionItems: [
          {
            sys: {
              id: '1ApsVOgmoqsbhw6kvXUAAa',
              contentType: {
                sys: {
                  id: 'primerComponentRiverAccordionItem',
                },
              },
            },
            fields: {
              heading: {
                nodeType: BLOCKS.DOCUMENT,
                data: {},
                content: [
                  {
                    data: {},
                    content: [
                      {
                        data: {},
                        marks: [],
                        value: 'Heading 1',
                        nodeType: 'text',
                      },
                    ],
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
                    content: [
                      {
                        data: {},
                        marks: [],
                        value:
                          'Lorem ipsum dolor sit amet, consectetur adipiscing elit. In sapien sit ullamcorper id. Aliquam luctus sed turpis felis nam pulvinar risus elementum.',
                        nodeType: 'text',
                      },
                    ],
                    nodeType: BLOCKS.PARAGRAPH,
                  },
                ],
              },
              callToAction: {
                sys: {
                  id: '6rrDNnDvRPJynkIPXBHs5W',
                  contentType: {
                    sys: {
                      id: 'link',
                    },
                  },
                },
                fields: {
                  href: 'github.com',
                  text: 'Call to action 1',
                  openInNewTab: false,
                },
              },
              image: {
                fields: {
                  description: '',
                  file: {
                    url: '//images.ctfassets.net/8aevphvgewt8/6ahiNNYjYgr8AL4TL8K76M/524018e72f357fd6f07de0be3ea72ddf/Accordion_1.png',
                  },
                },
              },
              imageAlt: 'Alt description of the image.',
            },
          },
          {
            sys: {
              id: '3gAwjfcsujAEQM3wI4ld22',
              contentType: {
                sys: {
                  id: 'primerComponentRiverAccordionItem',
                },
              },
            },
            fields: {
              heading: {
                nodeType: BLOCKS.DOCUMENT,
                data: {},
                content: [
                  {
                    data: {},
                    content: [
                      {
                        data: {},
                        marks: [],
                        value: 'Heading 2',
                        nodeType: 'text',
                      },
                    ],
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
                    content: [
                      {
                        data: {},
                        marks: [],
                        value:
                          'Lorem ipsum dolor sit amet, consectetur adipiscing elit. In sapien sit ullamcorper id. Aliquam luctus sed turpis felis nam pulvinar risus elementum.',
                        nodeType: 'text',
                      },
                    ],
                    nodeType: BLOCKS.PARAGRAPH,
                  },
                ],
              },
              image: {
                fields: {
                  description: '',
                  file: {
                    url: '//images.ctfassets.net/8aevphvgewt8/343aOBO22uAas8RB5LWCnu/b85670c5b7160d06ed80c76f27a4d284/Accordion_2.png',
                  },
                },
              },
              imageAlt: 'Alt heading for image 2',
            },
          },
          {
            sys: {
              id: 'S7qsxoIiJ8HUQTBMSO21b',
              contentType: {
                sys: {
                  id: 'primerComponentRiverAccordionItem',
                },
              },
            },
            fields: {
              heading: {
                nodeType: BLOCKS.DOCUMENT,
                data: {},
                content: [
                  {
                    data: {},
                    content: [
                      {
                        data: {},
                        marks: [],
                        value: 'Heading 3',
                        nodeType: 'text',
                      },
                    ],
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
                    content: [
                      {
                        data: {},
                        marks: [],
                        value:
                          'Lorem ipsum dolor sit amet, consectetur adipiscing elit. In sapien sit ullamcorper id. Aliquam luctus sed turpis felis nam pulvinar risus elementum.',
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
                              id: '4sfmv9jaORCNWAh3dincIW',
                              type: 'Entry',
                              createdAt: '2025-04-30T16:04:58.764Z',
                              updatedAt: '2025-04-30T16:04:58.764Z',
                              environment: {
                                sys: {
                                  id: 'joshvogel-sandbox',
                                  type: 'Link',
                                  linkType: 'Environment',
                                },
                              },
                              publishedVersion: 6,
                              revision: 1,
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
                              title:
                                '#footnote-1 Option to purchase additional premium requests not available to users that subscribe or have subscribed to Pro or Pro+ through GitHub Mobile on iOS or Android.',
                              anchorId: 'footnote-1',
                              text: {
                                data: {},
                                content: [
                                  {
                                    data: {},
                                    content: [
                                      {
                                        data: {},
                                        marks: [],
                                        value:
                                          'Option to purchase additional premium requests not available to users that subscribe or have subscribed to Pro or Pro+ through GitHub Mobile on iOS or Android.',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                                nodeType: BLOCKS.DOCUMENT,
                              },
                            },
                          },
                        },
                        content: [],
                        nodeType: BLOCKS.EMBEDDED_ENTRY,
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
              callToAction: {
                sys: {
                  id: 'UeJbLH6ijCQXBHUv45Rh6',
                  contentType: {
                    sys: {
                      id: 'link',
                    },
                  },
                },
                fields: {
                  href: 'https://github.com/github-copilot/pro-plus?cft=copilot_li.features_copilot.cpp',
                  text: 'Get started',
                  openInNewTab: false,
                },
              },
              callToActionVariant: 'accent',
              image: {
                fields: {
                  description: '',
                  file: {
                    url: '//images.ctfassets.net/8aevphvgewt8/5xj4KsAYIRfaMFh5TjoY3J/0349343eca612d305eabf1bfcf47a336/Accordion_3.png',
                  },
                },
              },
            },
          },
        ],
      },
    },
  },
}
