import '@primer/react-brand/lib/css/main.css'

import {BLOCKS} from '@contentful/rich-text-types'
import type {Meta, StoryObj} from '@storybook/react'

import {ContentfulSectionIntro} from './ContentfulSectionIntro'

const meta: Meta<typeof ContentfulSectionIntro> = {
  title: 'Mkt/Swp/Contentful/ContentfulSectionIntro',
  component: ContentfulSectionIntro,
}

export default meta

type Story = StoryObj<typeof ContentfulSectionIntro>

export const Default: Story = {
  args: {
    component: {
      sys: {
        contentType: {
          sys: {
            id: 'primerComponentSectionIntro',
          },
        },
        id: 'primer-section-intro',
      },
      fields: {
        align: 'start',
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
            icon: 'star',
            text: 'Github Copilot',
            size: 'medium',
            color: 'default',
          },
        },
        heading: {
          data: {},
          content: [
            {
              data: {},
              content: [
                {
                  data: {},
                  marks: [],
                  value: 'This is my super sweet SectionIntro heading',
                  nodeType: 'text',
                },
              ],
              nodeType: BLOCKS.PARAGRAPH,
            },
          ],
          nodeType: BLOCKS.DOCUMENT,
        },
        description: {
          data: {},
          content: [
            {
              data: {},
              content: [
                {
                  data: {},
                  marks: [],
                  value:
                    'Lorem ipsum dolor sit amet, consectetur adipiscing elit. In sapien sit id. Aliquam luctus sed turpis felis nam pulvinar risus elementum',
                  nodeType: 'text',
                },
              ],
              nodeType: BLOCKS.PARAGRAPH,
            },
          ],
          nodeType: BLOCKS.DOCUMENT,
        },
        htmlId: 'section-intro',
      },
    },
  },
}

export const WithLineBreaks: Story = {
  args: {
    component: {
      sys: {
        id: '4lLjjtxvL17dLxmriPpApa',
        contentType: {
          sys: {
            id: 'primerComponentSectionIntro',
          },
        },
      },
      fields: {
        align: 'center',
        fullWidth: true,
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
                  value: 'Kick off workflows on any ',
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
                  value: 'GitHub event to ',
                  marks: [],
                  data: {},
                },
                {
                  nodeType: 'text',
                  value: 'automate',
                  marks: [
                    {
                      type: 'bold',
                    },
                  ],
                  data: {},
                },
                {
                  nodeType: 'text',
                  value: ' tasks',
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
                  value: 'Foobar third line',
                  marks: [],
                  data: {},
                },
              ],
            },
          ],
        },
        htmlId: 'section-intro',
      },
    },
  },
}
