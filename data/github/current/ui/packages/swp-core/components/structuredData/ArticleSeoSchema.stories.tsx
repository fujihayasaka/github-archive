import type {Meta, StoryObj} from '@storybook/react'
import {ArticleSeoSchema} from './ArticleSeoSchema'

// This doesn't render visible markup, but is required for a11y scanning.
const meta: Meta<typeof ArticleSeoSchema> = {
  title: 'Mkt/Swp/StructuredData/ArticleSeoSchema',
  component: ArticleSeoSchema,
}

export default meta

type Story = StoryObj<typeof ArticleSeoSchema>

export const Default: Story = {
  render: () => (
    <>
      <p>No visible markup rendered.</p>
      <ArticleSeoSchema title="Example Title" imageUrl="https://example.com/image.jpg" />
    </>
  ),
}
