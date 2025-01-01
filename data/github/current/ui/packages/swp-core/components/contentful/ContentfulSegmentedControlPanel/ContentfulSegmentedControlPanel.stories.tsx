import '@primer/react-brand/lib/css/main.css'

import type {Meta, StoryObj} from '@storybook/react'
import {ContentfulSegmentedControlPanel} from './ContentfulSegmentedControlPanel'
import {BLOCKS} from '@contentful/rich-text-types'

const meta: Meta<typeof ContentfulSegmentedControlPanel> = {
  title: 'Mkt/Swp/Contentful/ContentfulSegmentedControlPanel',
  component: ContentfulSegmentedControlPanel,
}

export default meta

type Story = StoryObj<typeof ContentfulSegmentedControlPanel>

export const Default: Story = {
  args: {
    component: {
      sys: {
        id: '2sYfGLWb5vCAQ7XrD7Nrl9',
        contentType: {
          sys: {
            id: 'segmentedControlPanel',
          },
        },
      },
      fields: {
        ariaLabel: 'Pricing Options and More',
        panelItems: [
          {
            sys: {
              id: '7on7RJT4Mirsq5owee6N5l',
              contentType: {
                sys: {
                  id: 'segmentedControlPanelItem',
                },
              },
            },
            fields: {
              label: 'For individuals',
              flexSections: [
                {
                  sys: {
                    id: '49NeLmqfdJcodYT0NcQht8',
                    contentType: {
                      sys: {
                        id: 'flexSection',
                      },
                    },
                  },
                  fields: {
                    pricingOptions: {
                      sys: {
                        id: 'pbDRtAmPGg9UZmziIdq40',
                        contentType: {
                          sys: {
                            id: 'primerComponentPricingOptions',
                          },
                        },
                      },
                      fields: {
                        variant: 'default',
                        items: [
                          {
                            sys: {
                              id: '3DPSEmMWJpyuA01fVV5VTA',
                              contentType: {
                                sys: {
                                  id: 'primerComponentPricingOptionsItem',
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
                                        value: 'Free',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              description: {
                                nodeType: BLOCKS.DOCUMENT,
                                data: {},
                                content: [
                                  {
                                    data: {},
                                    content: [
                                      {
                                        data: {},
                                        marks: [],
                                        value: 'A fast way to get started with GitHub Copilot.',
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
                                        value: '',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              featureList: [
                                {
                                  sys: {
                                    id: '6ll0gJLJ6xzzBTAmr3EzDf',
                                    contentType: {
                                      sys: {
                                        id: 'primerComponentPricingOptionsListHeading',
                                      },
                                    },
                                  },
                                  fields: {
                                    heading: {
                                      nodeType: BLOCKS.DOCUMENT,
                                      data: {},
                                      content: [
                                        {
                                          nodeType: BLOCKS.PARAGRAPH,
                                          data: {},
                                          content: [
                                            {
                                              nodeType: 'text',
                                              value: "What's included",
                                              marks: [],
                                              data: {},
                                            },
                                          ],
                                        },
                                      ],
                                    },
                                  },
                                },
                                {
                                  sys: {
                                    id: '5gsAiShMaL9bcbRlfhu0XF',
                                    contentType: {
                                      sys: {
                                        id: 'primerComponentPricingOptionsListItem',
                                      },
                                    },
                                  },
                                  fields: {
                                    variant: 'included',
                                    description: {
                                      nodeType: BLOCKS.DOCUMENT,
                                      data: {},
                                      content: [
                                        {
                                          nodeType: BLOCKS.PARAGRAPH,
                                          data: {},
                                          content: [
                                            {
                                              nodeType: 'text',
                                              value: '50 agent mode or chat requests per month',
                                              marks: [],
                                              data: {},
                                            },
                                          ],
                                        },
                                      ],
                                    },
                                  },
                                },
                                {
                                  sys: {
                                    id: '1cFtPOYKDK758t62hIPRmE',
                                    contentType: {
                                      sys: {
                                        id: 'primerComponentPricingOptionsListItem',
                                      },
                                    },
                                  },
                                  fields: {
                                    variant: 'included',
                                    description: {
                                      nodeType: BLOCKS.DOCUMENT,
                                      data: {},
                                      content: [
                                        {
                                          nodeType: BLOCKS.PARAGRAPH,
                                          data: {},
                                          content: [
                                            {
                                              nodeType: 'text',
                                              value: '2,000 completions per month',
                                              marks: [],
                                              data: {},
                                            },
                                          ],
                                        },
                                      ],
                                    },
                                  },
                                },
                                {
                                  sys: {
                                    id: '4BzgsTnfxzPiaQ9awe57iy',
                                    contentType: {
                                      sys: {
                                        id: 'primerComponentPricingOptionsListItem',
                                      },
                                    },
                                  },
                                  fields: {
                                    variant: 'included',
                                    description: {
                                      nodeType: BLOCKS.DOCUMENT,
                                      data: {},
                                      content: [
                                        {
                                          nodeType: BLOCKS.PARAGRAPH,
                                          data: {},
                                          content: [
                                            {
                                              nodeType: 'text',
                                              value: 'Access to Claude 3.5 Sonnet, GPT-4o, and more',
                                              marks: [],
                                              data: {},
                                            },
                                          ],
                                        },
                                      ],
                                    },
                                  },
                                },
                              ],
                              featureListExpanded: false,
                              featureListHasDivider: true,
                              currentPrice: {
                                nodeType: BLOCKS.DOCUMENT,
                                data: {},
                                content: [
                                  {
                                    data: {},
                                    content: [
                                      {
                                        data: {},
                                        marks: [],
                                        value: '0',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              currencyCode: 'USD',
                              currencySymbol: '$',
                              callToActionPrimary: {
                                sys: {
                                  id: '68oKxvh9Zri3QnlLcvEyDF',
                                  contentType: {
                                    sys: {
                                      id: 'link',
                                    },
                                  },
                                },
                                fields: {
                                  href: 'https://github.com/copilot',
                                  text: 'Get started',
                                  openInNewTab: false,
                                },
                              },
                              callToActionSecondary: {
                                sys: {
                                  id: '2WZjZARYNVMXCcjTOsX5o2',
                                  contentType: {
                                    sys: {
                                      id: 'link',
                                    },
                                  },
                                },
                                fields: {
                                  href: 'vscode://github.copilot-chat',
                                  text: 'Open in VS Code',
                                  openInNewTab: false,
                                },
                              },
                            },
                          },
                          {
                            sys: {
                              id: 'R91Y43NYtBk6qs1DlCdvn',
                              contentType: {
                                sys: {
                                  id: 'primerComponentPricingOptionsItem',
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
                                        value: 'Pro',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              description: {
                                nodeType: BLOCKS.DOCUMENT,
                                data: {},
                                content: [
                                  {
                                    data: {},
                                    content: [
                                      {
                                        data: {},
                                        marks: [],
                                        value: 'Unlimited completions and chats with access to more models.',
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
                                        value: '',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              footnote: {
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
                                          'Free for verified students, teachers, and maintainers of popular open source projects.',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              featureList: [
                                {
                                  sys: {
                                    id: '2P9010hBsmD7zcKGc53el4',
                                    contentType: {
                                      sys: {
                                        id: 'primerComponentPricingOptionsListHeading',
                                      },
                                    },
                                  },
                                  fields: {
                                    heading: {
                                      nodeType: BLOCKS.DOCUMENT,
                                      data: {},
                                      content: [
                                        {
                                          nodeType: BLOCKS.PARAGRAPH,
                                          data: {},
                                          content: [
                                            {
                                              nodeType: 'text',
                                              value: 'Everything in Free and:',
                                              marks: [],
                                              data: {},
                                            },
                                          ],
                                        },
                                      ],
                                    },
                                  },
                                },
                                {
                                  sys: {
                                    id: '6mb1irNWFGkK6umuRSkg9j',
                                    contentType: {
                                      sys: {
                                        id: 'primerComponentPricingOptionsListItem',
                                      },
                                    },
                                  },
                                  fields: {
                                    variant: 'included',
                                    description: {
                                      nodeType: BLOCKS.DOCUMENT,
                                      data: {},
                                      content: [
                                        {
                                          nodeType: BLOCKS.PARAGRAPH,
                                          data: {},
                                          content: [
                                            {
                                              nodeType: 'text',
                                              value: 'Unlimited agent mode and chats with GPT-4o\n',
                                              marks: [],
                                              data: {},
                                            },
                                          ],
                                        },
                                      ],
                                    },
                                  },
                                },
                                {
                                  sys: {
                                    id: '3bQmPeUKxneJZzM4Iy4VOd',
                                    contentType: {
                                      sys: {
                                        id: 'primerComponentPricingOptionsListItem',
                                      },
                                    },
                                  },
                                  fields: {
                                    variant: 'included',
                                    description: {
                                      nodeType: BLOCKS.DOCUMENT,
                                      data: {},
                                      content: [
                                        {
                                          nodeType: BLOCKS.PARAGRAPH,
                                          data: {},
                                          content: [
                                            {
                                              nodeType: 'text',
                                              value: 'Unlimited code completions\n',
                                              marks: [],
                                              data: {},
                                            },
                                          ],
                                        },
                                      ],
                                    },
                                  },
                                },
                                {
                                  sys: {
                                    id: '3NTCEo9ftkZ1L1GVwyj7vP',
                                    contentType: {
                                      sys: {
                                        id: 'primerComponentPricingOptionsListItem',
                                      },
                                    },
                                  },
                                  fields: {
                                    variant: 'included',
                                    description: {
                                      nodeType: BLOCKS.DOCUMENT,
                                      data: {},
                                      content: [
                                        {
                                          nodeType: BLOCKS.PARAGRAPH,
                                          data: {},
                                          content: [
                                            {
                                              nodeType: 'text',
                                              value: 'Access to code review, Claude 3.7 Sonnet, o1, and more\n',
                                              marks: [],
                                              data: {},
                                            },
                                          ],
                                        },
                                      ],
                                    },
                                  },
                                },
                                {
                                  sys: {
                                    id: '7cR71JWfSYEGNjrUNuffOK',
                                    contentType: {
                                      sys: {
                                        id: 'primerComponentPricingOptionsListItem',
                                      },
                                    },
                                  },
                                  fields: {
                                    variant: 'included',
                                    description: {
                                      nodeType: BLOCKS.DOCUMENT,
                                      data: {},
                                      content: [
                                        {
                                          nodeType: BLOCKS.PARAGRAPH,
                                          data: {},
                                          content: [
                                            {
                                              nodeType: 'text',
                                              value:
                                                '6x more premium requests to use latest models than Free, with the option to buy more',
                                              marks: [],
                                              data: {},
                                            },
                                            {
                                              nodeType: BLOCKS.EMBEDDED_ENTRY,
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
                              ],
                              featureListExpanded: false,
                              featureListHasDivider: true,
                              label: {
                                sys: {
                                  id: '2U3e3oNSuW17P3JfoaZhGI',
                                  contentType: {
                                    sys: {
                                      id: 'primerComponentLabel',
                                    },
                                  },
                                },
                                fields: {
                                  text: 'Most popular',
                                  size: 'medium',
                                  color: 'green',
                                },
                              },
                              currentPrice: {
                                nodeType: BLOCKS.DOCUMENT,
                                data: {},
                                content: [
                                  {
                                    data: {},
                                    content: [
                                      {
                                        data: {},
                                        marks: [],
                                        value: '10',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              currencyCode: 'USD',
                              currencySymbol: '$',
                              originalPrice: '19',
                              priceTrailingText: 'per month or $100 per year',
                              callToActionPrimary: {
                                sys: {
                                  id: '66DX5HPhef13SOlTFofIfu',
                                  contentType: {
                                    sys: {
                                      id: 'link',
                                    },
                                  },
                                },
                                fields: {
                                  href: 'https://github.com/github-copilot/pro?cft=copilot_li.features_copilot.cfi',
                                  text: 'Try for 30 days free',
                                  openInNewTab: false,
                                },
                              },
                            },
                          },
                          {
                            sys: {
                              id: '38vqYasY9nTPKIZ2Y1NPKQ',
                              contentType: {
                                sys: {
                                  id: 'primerComponentPricingOptionsItem',
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
                                        value: 'Pro+',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              description: {
                                nodeType: BLOCKS.DOCUMENT,
                                data: {},
                                content: [
                                  {
                                    data: {},
                                    content: [
                                      {
                                        data: {},
                                        marks: [],
                                        value: 'Maximum flexibility and model choice.',
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
                                        value: '',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              featureList: [
                                {
                                  sys: {
                                    id: 'o2I7rYtDhiSN7ubH6Bg5G',
                                    contentType: {
                                      sys: {
                                        id: 'primerComponentPricingOptionsListHeading',
                                      },
                                    },
                                  },
                                  fields: {
                                    heading: {
                                      nodeType: BLOCKS.DOCUMENT,
                                      data: {},
                                      content: [
                                        {
                                          nodeType: BLOCKS.PARAGRAPH,
                                          data: {},
                                          content: [
                                            {
                                              nodeType: 'text',
                                              value: 'Everything in Pro and:\n',
                                              marks: [],
                                              data: {},
                                            },
                                          ],
                                        },
                                      ],
                                    },
                                  },
                                },
                                {
                                  sys: {
                                    id: '15qQobDy1xoOfo1PzNaLbn',
                                    contentType: {
                                      sys: {
                                        id: 'primerComponentPricingOptionsListItem',
                                      },
                                    },
                                  },
                                  fields: {
                                    variant: 'included',
                                    description: {
                                      nodeType: BLOCKS.DOCUMENT,
                                      data: {},
                                      content: [
                                        {
                                          nodeType: BLOCKS.PARAGRAPH,
                                          data: {},
                                          content: [
                                            {
                                              nodeType: 'text',
                                              value: 'Access to all models, including GPT-4.5\n',
                                              marks: [],
                                              data: {},
                                            },
                                          ],
                                        },
                                      ],
                                    },
                                  },
                                },
                                {
                                  sys: {
                                    id: '6YD9IG2Hm2S6VTjyndy30y',
                                    contentType: {
                                      sys: {
                                        id: 'primerComponentPricingOptionsListItem',
                                      },
                                    },
                                  },
                                  fields: {
                                    variant: 'included',
                                    description: {
                                      nodeType: BLOCKS.DOCUMENT,
                                      data: {},
                                      content: [
                                        {
                                          nodeType: BLOCKS.PARAGRAPH,
                                          data: {},
                                          content: [
                                            {
                                              nodeType: 'text',
                                              value:
                                                '30x more premium requests to use latest models than Free, with the option to buy more',
                                              marks: [],
                                              data: {},
                                            },
                                            {
                                              nodeType: BLOCKS.EMBEDDED_ENTRY,
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
                                            },
                                            {
                                              nodeType: 'text',
                                              value: '\n',
                                              marks: [],
                                              data: {},
                                            },
                                          ],
                                        },
                                      ],
                                    },
                                  },
                                },
                              ],
                              featureListExpanded: false,
                              featureListHasDivider: true,
                              currentPrice: {
                                nodeType: BLOCKS.DOCUMENT,
                                data: {},
                                content: [
                                  {
                                    data: {},
                                    content: [
                                      {
                                        data: {},
                                        marks: [],
                                        value: '39',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              currencyCode: 'USD',
                              currencySymbol: '$',
                              priceTrailingText: 'per month or $390 per year',
                              callToActionPrimary: {
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
                            },
                          },
                        ],
                      },
                    },
                    visualSettings: {
                      sys: {
                        id: '0q9M7VecanKtdWEVKJtoH',
                        contentType: {
                          sys: {
                            id: 'flexSectionVisualSettings',
                          },
                        },
                      },
                      fields: {
                        paddingBlockStart: 'none',
                        paddingBlockEnd: 'none',
                        backgroundColor: 'default',
                        roundedCorners: false,
                        verticalGap: 'normal',
                        enableRiverStoryScroll: false,
                        colorMode: 'inherit',
                      },
                    },
                  },
                },
              ],
            },
          },
          {
            sys: {
              id: '6Xzl5ig0XV2TbaMTKXMTQR',
              contentType: {
                sys: {
                  id: 'segmentedControlPanelItem',
                },
              },
            },
            fields: {
              label: 'For businesses',
              flexSections: [
                {
                  sys: {
                    id: '4KJbDnHTlDPxlZTjHg63VD',
                    contentType: {
                      sys: {
                        id: 'flexSection',
                      },
                    },
                  },
                  fields: {
                    pricingOptions: {
                      sys: {
                        id: '61FkKKfxTYM0TNmzyrkpb8',
                        contentType: {
                          sys: {
                            id: 'primerComponentPricingOptions',
                          },
                        },
                      },
                      fields: {
                        variant: 'cards',
                        items: [
                          {
                            sys: {
                              id: '13TpM9eXKZewIHsseK3agJ',
                              contentType: {
                                sys: {
                                  id: 'primerComponentPricingOptionsItem',
                                },
                              },
                            },
                            fields: {
                              heading: {
                                nodeType: BLOCKS.DOCUMENT,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value: 'For teams and organizations ready to protect against secret leaks.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              description: {
                                nodeType: BLOCKS.DOCUMENT,
                                data: {},
                                content: [
                                  {
                                    data: {},
                                    content: [
                                      {
                                        data: {},
                                        marks: [],
                                        value: 'Secret Protection',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              footnote: {
                                nodeType: BLOCKS.DOCUMENT,
                                data: {},
                                content: [
                                  {
                                    data: {},
                                    content: [
                                      {
                                        data: {},
                                        marks: [],
                                        value: 'Requires Teams or Enterprise plan',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              featureListExpanded: false,
                              featureListHasDivider: true,
                              label: {
                                sys: {
                                  id: '2ow9dmXFMdblpboamOCmmh',
                                  contentType: {
                                    sys: {
                                      id: 'primerComponentLabel',
                                    },
                                  },
                                },
                                fields: {
                                  text: 'Add-on',
                                  size: 'medium',
                                  color: 'green',
                                },
                              },
                              currentPrice: {
                                nodeType: BLOCKS.DOCUMENT,
                                data: {},
                                content: [
                                  {
                                    data: {},
                                    content: [
                                      {
                                        data: {},
                                        marks: [],
                                        value: '19',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              currencyCode: 'USD',
                              currencySymbol: '$',
                              priceTrailingText: 'per active committer/month',
                              callToActionPrimary: {
                                sys: {
                                  id: '11E5StJyv42yzIlaGOOeJZ',
                                  contentType: {
                                    sys: {
                                      id: 'link',
                                    },
                                  },
                                },
                                fields: {
                                  href: 'https://resources.github.com/demo/advanced-security/',
                                  text: 'Request a demo',
                                  openInNewTab: false,
                                },
                              },
                              callToActionSecondary: {
                                sys: {
                                  id: '3HCZcpBju6raMRKFqDmlKJ',
                                  contentType: {
                                    sys: {
                                      id: 'link',
                                    },
                                  },
                                },
                                fields: {
                                  href: 'https://enterprise.github.com/contact',
                                  text: 'Contact sales',
                                  openInNewTab: false,
                                },
                              },
                            },
                          },
                          {
                            sys: {
                              id: '4BFAvKssjluyAGqc9GJIHh',
                              contentType: {
                                sys: {
                                  id: 'primerComponentPricingOptionsItem',
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
                                        value: 'Code Security',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              description: {
                                nodeType: BLOCKS.DOCUMENT,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          'For teams and organizations aiming to fix code vulnerabilities before production.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              footnote: {
                                nodeType: BLOCKS.DOCUMENT,
                                data: {},
                                content: [
                                  {
                                    data: {},
                                    content: [
                                      {
                                        data: {},
                                        marks: [],
                                        value: 'Requires Teams or Enterprise plan',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              featureListExpanded: false,
                              featureListHasDivider: true,
                              label: {
                                sys: {
                                  id: '2ow9dmXFMdblpboamOCmmh',
                                  contentType: {
                                    sys: {
                                      id: 'primerComponentLabel',
                                    },
                                  },
                                },
                                fields: {
                                  text: 'Add-on',
                                  size: 'medium',
                                  color: 'green',
                                },
                              },
                              currentPrice: {
                                nodeType: BLOCKS.DOCUMENT,
                                data: {},
                                content: [
                                  {
                                    data: {},
                                    content: [
                                      {
                                        data: {},
                                        marks: [],
                                        value: '30',
                                        nodeType: 'text',
                                      },
                                    ],
                                    nodeType: BLOCKS.PARAGRAPH,
                                  },
                                ],
                              },
                              currencyCode: 'USD',
                              currencySymbol: '$',
                              priceTrailingText: 'per active committer/month',
                              callToActionPrimary: {
                                sys: {
                                  id: '11E5StJyv42yzIlaGOOeJZ',
                                  contentType: {
                                    sys: {
                                      id: 'link',
                                    },
                                  },
                                },
                                fields: {
                                  href: 'https://resources.github.com/demo/advanced-security/',
                                  text: 'Request a demo',
                                  openInNewTab: false,
                                },
                              },
                              callToActionSecondary: {
                                sys: {
                                  id: '1W9H0j19lP2xDRUfWv398c',
                                  contentType: {
                                    sys: {
                                      id: 'link',
                                    },
                                  },
                                },
                                fields: {
                                  href: 'https://github.com/enterprise/contact',
                                  text: 'Contact sales',
                                  openInNewTab: false,
                                },
                              },
                            },
                          },
                        ],
                      },
                    },
                    visualSettings: {
                      sys: {
                        id: '4M6nsdhiqB8hCio432TLOI',
                        contentType: {
                          sys: {
                            id: 'flexSectionVisualSettings',
                          },
                        },
                      },
                      fields: {
                        paddingBlockStart: 'none',
                        paddingBlockEnd: 'none',
                        backgroundColor: 'default',
                        roundedCorners: false,
                        verticalGap: 'normal',
                        enableRiverStoryScroll: false,
                        colorMode: 'inherit',
                      },
                    },
                  },
                },
              ],
            },
          },
        ],
      },
    },
  },
}
