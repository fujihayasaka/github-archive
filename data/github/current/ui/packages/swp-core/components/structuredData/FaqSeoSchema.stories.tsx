import type {Meta, StoryObj} from '@storybook/react'
import {FAQSeoSchema} from './FaqSeoSchema'
import {FaqGroupPayload} from '../../__tests__/components/structuredData/fixtures/FaqPayload'
import type {PrimerComponentFaqGroup} from '../../schemas/contentful/contentTypes/primerComponentFaqGroup'

// This doesn't render visible markup, but is required for a11y scanning.
const meta: Meta<typeof FAQSeoSchema> = {
  title: 'Mkt/Swp/StructuredData/FaqSeoSchema',
  component: FAQSeoSchema,
}

export default meta

type Story = StoryObj<typeof FAQSeoSchema>

export const Default: Story = {
  render: () => (
    <>
      <p>No visible markup rendered.</p>
      <FAQSeoSchema faqGroup={FaqGroupPayload as PrimerComponentFaqGroup} />
    </>
  ),
}
