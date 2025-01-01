import '@primer/react-brand/lib/css/main.css'

import type {Meta, StoryObj} from '@storybook/react'

import {ContentfulStatistics} from './ContentfulStatistics'

const meta: Meta<typeof ContentfulStatistics> = {
  title: 'Mkt/Swp/Contentful/ContentfulStatistics',
  component: ContentfulStatistics,
  parameters: {
    a11y: {
      config: {
        rules: [
          {id: 'color-contrast', enabled: false}, // Incomplete check resulting in flaky tests
        ],
      },
    },
  },
}

export default meta

type Story = StoryObj<typeof ContentfulStatistics>

export const ThreeStatistics: Story = {
  args: {
    component: {
      sys: {
        contentType: {
          sys: {
            id: 'primerStatistics',
          },
        },
        id: 'primer-statistics',
      },
      fields: {
        statistics: [
          {
            sys: {
              contentType: {
                sys: {
                  id: 'primerComponentStatistic',
                },
              },
              id: 'primer-statistic',
            },
            fields: {
              description: 'Given back to our maintainers',
              descriptionVariant: 'accent',
              heading: '$2M+',
              size: 'large',
              variant: 'boxed',
            },
          },
          {
            sys: {
              contentType: {
                sys: {
                  id: 'primerComponentStatistic',
                },
              },
              id: 'primer-statistic',
            },
            fields: {
              description: 'Sponsored maintainers and projects',
              descriptionVariant: 'accent',
              heading: '30K+',
              size: 'large',
              variant: 'boxed',
            },
          },
          {
            sys: {
              contentType: {
                sys: {
                  id: 'primerComponentStatistic',
                },
              },
              id: 'primer-statistic',
            },
            fields: {
              description: 'Companies actively sponsoring',
              descriptionVariant: 'accent',
              heading: '3.5K+',
              size: 'large',
              variant: 'boxed',
            },
          },
        ],
      },
    },
  },
}

export const FourStatistics: Story = {
  args: {
    component: {
      sys: {
        contentType: {
          sys: {
            id: 'primerStatistics',
          },
        },
        id: 'primer-statistics',
      },
      fields: {
        statistics: [
          {
            sys: {
              contentType: {
                sys: {
                  id: 'primerComponentStatistic',
                },
              },
              id: 'primer-statistic',
            },
            fields: {
              description: 'Given back to our maintainers',
              descriptionVariant: 'accent',
              heading: '$2M+',
              size: 'large',
              variant: 'boxed',
            },
          },
          {
            sys: {
              contentType: {
                sys: {
                  id: 'primerComponentStatistic',
                },
              },
              id: 'primer-statistic',
            },
            fields: {
              description: 'Sponsored maintainers and projects',
              descriptionVariant: 'accent',
              heading: '30K+',
              size: 'large',
              variant: 'boxed',
            },
          },
          {
            sys: {
              contentType: {
                sys: {
                  id: 'primerComponentStatistic',
                },
              },
              id: 'primer-statistic',
            },
            fields: {
              description: 'Companies actively sponsoring',
              descriptionVariant: 'accent',
              heading: '3.5K+',
              size: 'large',
              variant: 'boxed',
            },
          },
          {
            sys: {
              contentType: {
                sys: {
                  id: 'primerComponentStatistic',
                },
              },
              id: 'primer-statistic',
            },
            fields: {
              description: 'set-up time for largest repo with Codespaces',
              descriptionVariant: 'accent',
              heading: '1min',
              size: 'large',
              variant: 'boxed',
            },
          },
        ],
      },
    },
  },
}
