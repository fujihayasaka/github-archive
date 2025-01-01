import '@primer/react-brand/lib/css/main.css'

import type {Meta, StoryObj} from '@storybook/react'

import {ContentfulHero} from './ContentfulHero'

const meta: Meta<typeof ContentfulHero> = {
  title: 'Mkt/Swp/Contentful/ContentfulHero',
  component: ContentfulHero,
}

export default meta

type Story = StoryObj<typeof ContentfulHero>

export const Default: Story = {
  args: {
    component: {
      sys: {
        contentType: {
          sys: {
            id: 'primerComponentHero',
          },
        },
        id: 'primer-component-hero',
      },
      fields: {
        align: 'center',
        description:
          'Lorem ipsum dolor sit amet, consectetur adipiscing elit. In sapien sit ullamcorper id. Aliquam luctus sed turpis felis nam pulvinar risus elementum.',
        heading: 'Hello, world!',
        callToActionPrimary: {
          sys: {
            id: 'cta-primary',
            contentType: {
              sys: {
                id: 'link',
              },
            },
          },
          fields: {
            href: 'https://github.com',
            text: 'Primary CTA',
          },
        },
        callToActionSecondary: {
          sys: {
            id: 'cta-secondary',
            contentType: {
              sys: {
                id: 'link',
              },
            },
          },
          fields: {
            href: 'https://github.com',
            text: 'Secondary CTA',
          },
        },
      },
    },
  },
}

export const WithLabel: Story = {
  args: {
    component: {
      sys: {
        contentType: {
          sys: {
            id: 'primerComponentHero',
          },
        },
        id: 'primer-component-hero',
      },
      fields: {
        align: 'center',
        description:
          'Lorem ipsum dolor sit amet, consectetur adipiscing elit. In sapien sit ullamcorper id. Aliquam luctus sed turpis felis nam pulvinar risus elementum.',
        heading: 'Hello, world!',
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
            text: 'Github Copilot',
            size: 'large',
            color: 'purple',
            icon: 'star',
          },
        },
        callToActionPrimary: {
          sys: {
            id: 'cta-primary',
            contentType: {
              sys: {
                id: 'link',
              },
            },
          },
          fields: {
            href: 'https://github.com',
            text: 'Primary CTA',
          },
        },
        callToActionSecondary: {
          sys: {
            id: 'cta-secondary',
            contentType: {
              sys: {
                id: 'link',
              },
            },
          },
          fields: {
            href: 'https://github.com',
            text: 'Secondary CTA',
          },
        },
      },
    },
  },
}

export const HeadingSize: Story = {
  args: {
    component: {
      sys: {
        contentType: {
          sys: {
            id: 'primerComponentHero',
          },
        },
        id: 'primer-component-hero',
      },
      fields: {
        align: 'center',
        description:
          'Lorem ipsum dolor sit amet, consectetur adipiscing elit. In sapien sit ullamcorper id. Aliquam luctus sed turpis felis nam pulvinar risus elementum.',
        heading: 'Hello, world!',
        headingSize: '2',
        callToActionPrimary: {
          sys: {
            id: 'cta-primary',
            contentType: {
              sys: {
                id: 'link',
              },
            },
          },
          fields: {
            href: 'https://github.com',
            text: 'Primary CTA',
          },
        },
        callToActionSecondary: {
          sys: {
            id: 'cta-secondary',
            contentType: {
              sys: {
                id: 'link',
              },
            },
          },
          fields: {
            href: 'https://github.com',
            text: 'Secondary CTA',
          },
        },
      },
    },
  },
}
