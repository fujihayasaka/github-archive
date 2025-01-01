import '@primer/react-brand/lib/css/main.css'

import {BLOCKS} from '@contentful/rich-text-types'
import type {Meta, StoryObj} from '@storybook/react'

import {ContentfulCtaBanner} from './ContentfulCtaBanner'

const meta: Meta<typeof ContentfulCtaBanner> = {
  title: 'Mkt/Swp/Contentful/ContentfulCtaBanner',
  component: ContentfulCtaBanner,
}

export default meta

type Story = StoryObj<typeof ContentfulCtaBanner>

export const Default: Story = {
  args: {
    component: {
      sys: {
        contentType: {
          sys: {
            id: 'primerComponentCtaBanner',
          },
        },
        id: 'primer-component-cta-banner',
      },
      fields: {
        align: 'center',
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
                    'Lorem ipsum dolor sit amet, consectetur adipiscing elit. In sapien sit ullamcorper id. Aliquam luctus sed turpis felis nam pulvinar risus elementum.',
                  nodeType: 'text',
                },
              ],
              nodeType: BLOCKS.PARAGRAPH,
            },
          ],
          nodeType: BLOCKS.DOCUMENT,
        },
        hasBorder: true,
        hasBackground: true,
        heading: 'Where the most ambitious teams build great things',
        callToActionPrimary: {
          sys: {
            contentType: {
              sys: {
                id: 'link',
              },
            },
            id: 'cta-primary',
          },
          fields: {
            href: 'https://primer.style/brand',
            text: 'Primary CTA',
          },
        },
        callToActionSecondary: {
          sys: {
            contentType: {
              sys: {
                id: 'link',
              },
            },
            id: 'cta-primary',
          },
          fields: {
            href: 'https://primer.style/brand',
            text: 'Secondary CTA',
          },
        },
      },
    },
  },
}

export const WithImage: Story = {
  args: {
    component: {
      sys: {
        id: 'j9cLWHIqQ7b5leFoB8hjZ',
        contentType: {
          sys: {
            id: 'primerComponentCtaBanner',
          },
        },
      },
      fields: {
        align: 'center',
        heading: 'Maximize your investment in AI',
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
                  value:
                    'Our recent study with Accenture shows that AI-driven tools like GitHub Copilot, when integrated into daily workflows, can significantly boost productivity, job satisfaction, and overall code quality without adding complexity.',
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
                  value:
                    'Discover how to seamlessly integrate AI into your development processes with GitHub Copilot and see measurable impact across your organization.',
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
          ],
        },
        hasBorder: true,
        hasShadow: true,
        backgroundImage: {
          sys: {
            id: '22Wfu01rB6ZJuKsz07b3UC',
            contentType: {
              sys: {
                id: 'backgroundImage',
              },
            },
          },
          fields: {
            image: {
              fields: {
                description: 'A group of people working on laptops with abstract shapes and calendars',
                file: {
                  url: '//images.ctfassets.net/8aevphvgewt8/131JffhVIrbXCclE3QUlYn/9e51844548d4dd7b1780d8ef651e9a47/partners.webp',
                },
              },
            },
            focus: 'left',
            colorMode: 'dark',
          },
        },
        hasBackground: true,
        callToActionPrimary: {
          sys: {
            id: '2hS1p3E1NVBZu0TFyxoAXQ',
            contentType: {
              sys: {
                id: 'link',
              },
            },
          },
          fields: {
            href: 'https://github.blog/news-insights/research/research-quantifying-github-copilots-impact-in-the-enterprise-with-accenture/',
            text: 'Learn more',
            openInNewTab: false,
          },
        },
        callToActionSecondary: {
          sys: {
            id: 'OEGOmi1BUJq0RosB33bNc',
            contentType: {
              sys: {
                id: 'link',
              },
            },
          },
          fields: {
            href: 'https://github.com/enterprise/contact?ref_cta=Contact+sales&ref_loc=footer&ref_page=%2Fsolutions_executive_insights',
            text: 'Contact sales',
            openInNewTab: false,
          },
        },
      },
    },
  },
}
