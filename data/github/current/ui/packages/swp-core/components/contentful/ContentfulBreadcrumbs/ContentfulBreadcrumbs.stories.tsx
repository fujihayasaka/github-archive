import '@primer/react-brand/lib/css/main.css'

import type {Meta, StoryObj} from '@storybook/react'

import {ContentfulBreadcrumbs} from './ContentfulBreadcrumbs'

const meta: Meta<typeof ContentfulBreadcrumbs> = {
  title: 'Mkt/Swp/Contentful/ContentfulBreadcrumbs',
  component: ContentfulBreadcrumbs,
}

export default meta

type Story = StoryObj<typeof ContentfulBreadcrumbs>

export const Default: Story = {
  args: {
    breadcrumbs: [
      {
        sys: {
          id: '3sKZC4xN2iI7ZQNe67u7Qc',
          contentType: {
            sys: {
              id: 'primerComponentBreadcrumb',
            },
          },
        },
        fields: {
          pageName: 'Github',
          path: '/',
          selected: false,
        },
      },
      {
        sys: {
          id: '2K1uZ0LfldssUOdNSEwPY',
          contentType: {
            sys: {
              id: 'primerComponentBreadcrumb',
            },
          },
        },
        fields: {
          pageName: 'Contentful LP Test',
          path: '/contentful-lp-test',
          selected: false,
        },
      },
      {
        sys: {
          id: '3aKzjXZN9SMfEgldSel7sM',
          contentType: {
            sys: {
              id: 'primerComponentBreadcrumb',
            },
          },
        },
        fields: {
          pageName: 'Flex Template',
          path: '/contentful-lp-tests/template-flex',
          selected: true,
        },
      },
    ],
  },
}
