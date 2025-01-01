import '@primer/react-brand/lib/css/main.css'

import type {Meta, StoryObj} from '@storybook/react'
import {ThemeProvider} from '@primer/react-brand'
import {ContentfulBreakoutBanner} from './ContentfulBreakoutBanner'
import {BLOCKS} from '@contentful/rich-text-types'

const meta: Meta<typeof ContentfulBreakoutBanner> = {
  title: 'Mkt/Swp/Contentful/ContentfulBreakoutBanner',
  component: ContentfulBreakoutBanner,
}

export default meta

type Story = StoryObj<typeof ContentfulBreakoutBanner>

export const Default: Story = {
  args: {
    component: {
      sys: {
        id: '76fGoFiZao7ZzsMYOVJYoC',
        contentType: {
          sys: {
            id: 'primerComponentBreakoutBanner',
          },
        },
      },
      fields: {
        align: 'start',
        backgroundColor: 'subtle',
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
                  value: 'Where the most ambitious teams build great things',
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
        ctaLink: {
          sys: {
            id: '2bUcgWPqK5N4vfZw3ik20X',
            contentType: {
              sys: {
                id: 'link',
              },
            },
          },
          fields: {
            href: '#',
            text: 'Primary Action',
            openInNewTab: false,
          },
        },
        logo: 'Forrester Research',
      },
    },
  },
}

export const CustomBackgroundColors: Story = {
  args: {
    component: {
      sys: {
        id: '76fGoFiZao7ZzsMYOVJYoC',
        contentType: {
          sys: {
            id: 'primerComponentBreakoutBanner',
          },
        },
      },
      fields: {
        align: 'start',
        backgroundColor: 'subtle',
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
                  value: 'Where the most ambitious teams build great things',
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
        ctaLink: {
          sys: {
            id: '2bUcgWPqK5N4vfZw3ik20X',
            contentType: {
              sys: {
                id: 'link',
              },
            },
          },
          fields: {
            href: '#',
            text: 'Primary Action',
            openInNewTab: false,
          },
        },
      },
    },
  },
}

export const BackgroundImageLight: Story = {
  args: {
    component: {
      sys: {
        id: '76fGoFiZao7ZzsMYOVJYoC',
        contentType: {
          sys: {
            id: 'primerComponentBreakoutBanner',
          },
        },
      },
      fields: {
        align: 'start',
        backgroundColor: 'subtle',
        backgroundImage: {
          fields: {
            description: 'A horizontal background for a breakout banner',
            file: {
              url: '//images.ctfassets.net/8aevphvgewt8/6Ctm0OLVtLCjRZWwi8Cp6J/d3e5b92f18057087f55a54839680e695/light-horizontal-banner.png',
            },
          },
        },
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
                  value: 'Where the most ambitious teams build great things',
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
        ctaLink: {
          sys: {
            id: '2bUcgWPqK5N4vfZw3ik20X',
            contentType: {
              sys: {
                id: 'link',
              },
            },
          },
          fields: {
            href: '#',
            text: 'Primary Action',
            openInNewTab: false,
          },
        },
        logo: 'Forrester Research',
      },
    },
  },
}

BackgroundImageLight.decorators = [
  Story => (
    <ThemeProvider colorMode="light">
      <Story />
    </ThemeProvider>
  ),
]

export const BackgroundImageDark: Story = {
  args: {
    component: {
      sys: {
        id: '76fGoFiZao7ZzsMYOVJYoC',
        contentType: {
          sys: {
            id: 'primerComponentBreakoutBanner',
          },
        },
      },
      fields: {
        align: 'start',
        backgroundColor: 'subtle',
        backgroundImage: {
          fields: {
            description: 'A background image for a breakout banner',
            file: {
              url: '//images.ctfassets.net/8aevphvgewt8/qZAOIUgxosFxftpHMTQzj/9d85bd00cb68430615cb9acb1522acc6/dark-horizontal-banner.png',
            },
          },
        },
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
                  value: 'Where the most ambitious teams build great things',
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
        ctaLink: {
          sys: {
            id: '2bUcgWPqK5N4vfZw3ik20X',
            contentType: {
              sys: {
                id: 'link',
              },
            },
          },
          fields: {
            href: '#',
            text: 'Primary Action',
            openInNewTab: false,
          },
        },
        logo: 'Gartner',
      },
    },
  },
}

BackgroundImageDark.decorators = [
  Story => (
    <ThemeProvider colorMode="dark">
      <Story />
    </ThemeProvider>
  ),
]

export const AlignedCenter: Story = {
  args: {
    component: {
      sys: {
        id: '76fGoFiZao7ZzsMYOVJYoC',
        contentType: {
          sys: {
            id: 'primerComponentBreakoutBanner',
          },
        },
      },
      fields: {
        align: 'center',
        backgroundColor: 'default',
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
                  value: 'Where the most ambitious teams build great things',
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
        ctaLink: {
          sys: {
            id: '2bUcgWPqK5N4vfZw3ik20X',
            contentType: {
              sys: {
                id: 'link',
              },
            },
          },
          fields: {
            href: '#',
            text: 'Primary Action',
            openInNewTab: false,
          },
        },
        logo: 'Gartner',
      },
    },
  },
}
