import type {Meta, StoryObj} from '@storybook/react'
import {LanguagesSection} from './LanguagesSection'
import {parametersConfig} from '../../utils/story-utils'

type StoryArgs = typeof LanguagesSection

const meta = {
  title: 'Apps/GitHub Models/LanguagesSection',
  component: LanguagesSection,
  args: {
    headingLevel: 'h2',
  },
  argTypes: {
    languages: {control: 'object'},
    headingLevel: {control: 'radio', options: ['h2', 'h3']},
  },
  parameters: parametersConfig,
} satisfies Meta<StoryArgs>

export default meta

type Story = StoryObj<StoryArgs>

export const OneLanguage: Story = {
  render: args => <LanguagesSection {...args} />,
  args: {languages: ['nl']},
}

export const TwoLanguages: Story = {
  render: args => <LanguagesSection {...args} />,
  args: {languages: ['ar', 'pa']},
}

export const SeveralLanguages: Story = {
  render: args => <LanguagesSection {...args} />,
  args: {languages: ['fr', 'de', 'es', 'it', 'en']},
}

export const ManyLanguages: Story = {
  render: args => <LanguagesSection {...args} />,
  args: {languages: ['fr', 'it', 'pt', 'en', 'pl', 'pa', 'hr', 'zh-tw', 'da', 'ar-kw', 'ga', 'ko', 'es-ec', 'zu']},
}
