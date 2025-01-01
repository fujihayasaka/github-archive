import type {Meta, StoryObj} from '@storybook/react'
import ModelsIndexFilters from './ModelsIndexFilters'
import {parametersConfig} from '../utils/story-utils'

const meta: Meta = {
  title: 'Apps/GitHub Models/ModelsIndexFilters',
  component: ModelsIndexFilters,
  parameters: parametersConfig,
}

export default meta

export const Example: StoryObj = {
  render: () => <ModelsIndexFilters />,
}
