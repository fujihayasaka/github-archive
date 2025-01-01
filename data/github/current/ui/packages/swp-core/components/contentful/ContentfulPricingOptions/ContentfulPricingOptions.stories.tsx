import '@primer/react-brand/lib/css/main.css'

import type {Meta, StoryObj} from '@storybook/react'

import {ContentfulPricingOptions} from './ContentfulPricingOptions'
import {BLOCKS} from '@contentful/rich-text-types'
import type {PrimerComponentPricingOptions} from '../../../schemas/contentful/contentTypes/primerComponentPricingOptions'

const meta: Meta<typeof ContentfulPricingOptions> = {
  title: 'Mkt/Swp/Contentful/ContentfulPricingOptions',
  component: ContentfulPricingOptions,
}

export default meta

type Story = StoryObj<typeof ContentfulPricingOptions>

const getPayload = (): PrimerComponentPricingOptions => ({
  sys: {
    id: '3PaSnM0rBpUcduNeQ69ltT',
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
          id: '6yDRQ2dDieROl3oWzIHnKl',
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
                    value: 'Copilot',
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
                    value: 'Copilot in the coding environment.',
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
                    value: 'Footnote',
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
              id: '5bCcRveguCZtWsnHU6FRcB',
              contentType: {
                sys: {
                  id: 'primerComponentLabel',
                },
              },
            },
            fields: {
              text: 'GitHub Roadmap',
              size: 'medium',
              color: 'purple',
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
          originalPrice: '12',
          priceTrailingText: 'per month / $100 per year',
          callToActionPrimary: {
            sys: {
              id: '7EtL05x9ety4n7XJbVWM0B',
              contentType: {
                sys: {
                  id: 'link',
                },
              },
            },
            fields: {
              href: 'https://www.linkedin.com/pulse/how-thomson-reuters-successfully-adopted-ai-your-organization-can-3krpf/',
              text: 'Learn more',
              openInNewTab: true,
            },
          },
          callToActionSecondary: {
            sys: {
              id: '7EtL05x9ety4n7XJbVWM0B',
              contentType: {
                sys: {
                  id: 'link',
                },
              },
            },
            fields: {
              href: 'https://www.linkedin.com/pulse/how-thomson-reuters-successfully-adopted-ai-your-organization-can-3krpf/',
              text: 'Learn more',
              openInNewTab: true,
            },
          },
        },
      },
      {
        sys: {
          id: '7deCeb9JKb055TdTUd2uwz',
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
                    value: 'Copilot Business',
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
                    value: '\n',
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
                    value: '33',
                    nodeType: 'text',
                  },
                ],
                nodeType: BLOCKS.PARAGRAPH,
              },
            ],
          },
          priceTrailingText: 'qqqq',
        },
      },
      {
        sys: {
          id: '2CRX979cHv7NnP5EWgD1Yl',
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
                    value: 'Pricing Option 3 kitchen sink',
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
                    value: 'Kitchen sink description',
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
                    value: 'Kitchen sink footnote',
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
                id: '4luBTVsv09HxmUlximbBK7',
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
                          value: 'Feature list heading 1',
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
                id: 'We7QquENKl8omtSP4zwxS',
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
                          value: 'item 1',
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
                id: '6XVKx19DOo2A4IyjGGDbg8',
                contentType: {
                  sys: {
                    id: 'primerComponentPricingOptionsListItem',
                  },
                },
              },
              fields: {
                variant: 'excluded',
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
                          value: 'foobar',
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
                id: '4luBTVsv09HxmUlximbBK7',
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
                          value: 'Feature list heading 1',
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
                id: '6XVKx19DOo2A4IyjGGDbg8',
                contentType: {
                  sys: {
                    id: 'primerComponentPricingOptionsListItem',
                  },
                },
              },
              fields: {
                variant: 'excluded',
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
                          value: 'foobar',
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
                id: 'We7QquENKl8omtSP4zwxS',
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
                          value: 'item 1',
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
              id: '5bCcRveguCZtWsnHU6FRcB',
              contentType: {
                sys: {
                  id: 'primerComponentLabel',
                },
              },
            },
            fields: {
              text: 'GitHub Roadmap',
              size: 'medium',
              color: 'purple',
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
          originalPrice: '12',
          priceTrailingText: 'per month / $100 per year',
          callToActionPrimary: {
            sys: {
              id: '7EtL05x9ety4n7XJbVWM0B',
              contentType: {
                sys: {
                  id: 'link',
                },
              },
            },
            fields: {
              href: 'https://www.linkedin.com/pulse/how-thomson-reuters-successfully-adopted-ai-your-organization-can-3krpf/',
              text: 'Learn more',
              openInNewTab: true,
            },
          },
          callToActionSecondary: {
            sys: {
              id: '7EtL05x9ety4n7XJbVWM0B',
              contentType: {
                sys: {
                  id: 'link',
                },
              },
            },
            fields: {
              href: 'https://www.linkedin.com/pulse/how-thomson-reuters-successfully-adopted-ai-your-organization-can-3krpf/',
              text: 'Learn more',
              openInNewTab: true,
            },
          },
        },
      },
    ],
  },
})

export const Default: Story = {
  args: {
    component: getPayload(),
  },
}

const asCardsPayload = getPayload()
asCardsPayload.fields.variant = 'cards'
export const AsCards: Story = {
  args: {
    component: asCardsPayload,
  },
}

const singleOptionPayload = getPayload()
// @ts-expect-error - TS doesn't like operation below
singleOptionPayload.fields.items = [singleOptionPayload.fields.items[0]]
export const SingleOption: Story = {
  args: {
    component: singleOptionPayload,
  },
}
