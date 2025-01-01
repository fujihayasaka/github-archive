import '@primer/react-brand/lib/css/main.css'

import {BLOCKS} from '@contentful/rich-text-types'
import type {Meta, StoryObj} from '@storybook/react'

import {ContentfulTestimonial} from './ContentfulTestimonial'
import {Box, Grid, Image, ThemeProvider} from '@primer/react-brand'
import styles from './ContentfulTestimonial.stories.module.css'
import startShapeLight from './fixtures/images/testimonial-bg-1.png'
import endShapeLight from './fixtures/images/testimonial-bg-2.png'

const meta: Meta<typeof ContentfulTestimonial> = {
  title: 'Mkt/Swp/Contentful/ContentfulTestimonial',
  component: ContentfulTestimonial,
}

export default meta

type Story = StoryObj<typeof ContentfulTestimonial>

export const Default: Story = {
  args: {
    component: {
      sys: {
        contentType: {
          sys: {
            id: 'primerComponentTestimonial',
          },
        },
        id: 'primer-component-testimonial',
      },
      fields: {
        author: {
          sys: {
            contentType: {
              sys: {
                id: 'person',
              },
            },
            id: 'person',
          },
          fields: {
            fullName: 'John Doe',
            position: 'CEO',
          },
        },
        size: 'large',
        quote: {
          data: {},
          content: [
            {
              data: {},
              content: [
                {
                  data: {},
                  marks: [],
                  value: 'This is my super sweet testimonial',
                  nodeType: 'text',
                },
              ],
              nodeType: BLOCKS.PARAGRAPH,
            },
          ],
          nodeType: BLOCKS.DOCUMENT,
        },
        displayedAuthorImage: 'avatar',
      },
    },
  },
}

export const VariantDefault: Story = {
  args: {
    component: {
      sys: {
        contentType: {
          sys: {
            id: 'primerComponentTestimonial',
          },
        },
        id: 'primer-component-testimonial',
      },
      fields: {
        author: {
          sys: {
            contentType: {
              sys: {
                id: 'person',
              },
            },
            id: 'person',
          },
          fields: {
            fullName: 'John Doe',
            position: 'CEO',
          },
        },
        size: 'large',
        variant: 'default',
        quote: {
          data: {},
          content: [
            {
              data: {},
              content: [
                {
                  data: {},
                  marks: [],
                  value: 'This is my super sweet testimonial',
                  nodeType: 'text',
                },
              ],
              nodeType: BLOCKS.PARAGRAPH,
            },
          ],
          nodeType: BLOCKS.DOCUMENT,
        },
        displayedAuthorImage: 'avatar',
      },
    },
  },
}

export const VariantSubtle: Story = {
  args: {
    component: {
      sys: {
        contentType: {
          sys: {
            id: 'primerComponentTestimonial',
          },
        },
        id: 'primer-component-testimonial',
      },
      fields: {
        author: {
          sys: {
            contentType: {
              sys: {
                id: 'person',
              },
            },
            id: 'person',
          },
          fields: {
            fullName: 'John Doe',
            position: 'CEO',
          },
        },
        size: 'large',
        variant: 'subtle',
        quote: {
          data: {},
          content: [
            {
              data: {},
              content: [
                {
                  data: {},
                  marks: [],
                  value: 'This is my super sweet testimonial',
                  nodeType: 'text',
                },
              ],
              nodeType: BLOCKS.PARAGRAPH,
            },
          ],
          nodeType: BLOCKS.DOCUMENT,
        },
        displayedAuthorImage: 'avatar',
      },
    },
  },
}

export const VariantFrostedGlass: Story = {
  args: {
    component: {
      sys: {
        contentType: {
          sys: {
            id: 'primerComponentTestimonial',
          },
        },
        id: 'primer-component-testimonial',
      },
      fields: {
        author: {
          sys: {
            contentType: {
              sys: {
                id: 'person',
              },
            },
            id: 'person',
          },
          fields: {
            fullName: 'John Doe',
            position: 'CEO',
          },
        },
        size: 'large',
        variant: 'frosted-glass',
        quote: {
          data: {},
          content: [
            {
              data: {},
              content: [
                {
                  data: {},
                  marks: [],
                  value: 'This is my super sweet testimonial',
                  nodeType: 'text',
                },
              ],
              nodeType: BLOCKS.PARAGRAPH,
            },
          ],
          nodeType: BLOCKS.DOCUMENT,
        },
        displayedAuthorImage: 'avatar',
      },
    },
  },
  parameters: {
    layout: 'full',
  },
  decorators: [
    Story => (
      <ThemeProvider
        colorMode="light"
        className={styles.container}
        role="region"
        tabIndex={0}
        aria-label="Scrollable content"
      >
        <Box backgroundColor="subtle" paddingBlockStart={128} paddingBlockEnd={128} className={styles.innerContainer}>
          <Image src={startShapeLight} alt="Starting shape" className={styles.exampleShape} width={612} />
          <Image src={endShapeLight} alt="Ending shape" className={styles.exampleShape} width={612} />
          <Grid>
            <Grid.Column>
              <Story />
            </Grid.Column>
          </Grid>
        </Box>
      </ThemeProvider>
    ),
  ],
}
