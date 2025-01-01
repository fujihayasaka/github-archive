import type {Meta, StoryObj} from '@storybook/react'
import {BreadcrumbSeoSchema} from './BreadcrumbSeoSchema'

// This doesn't render visible markup, but is required for a11y scanning.
const meta: Meta<typeof BreadcrumbSeoSchema> = {
  title: 'Mkt/Swp/StructuredData/BreadcrumbSeoSchema',
  component: BreadcrumbSeoSchema,
}

export default meta

type Story = StoryObj<typeof BreadcrumbSeoSchema>

const items = [
  {name: 'Resources', url: '/resources'},
  {name: 'Articles', url: '/resources/articles'},
  {name: 'Topic', url: '/resources/articles/topic'},
]

export const Default: Story = {
  render: () => (
    <>
      <p>No visible markup rendered.</p>
      <BreadcrumbSeoSchema items={items} />
    </>
  ),
}
