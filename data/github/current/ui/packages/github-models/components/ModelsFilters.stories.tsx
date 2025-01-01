import {useEffect, useState} from 'react'
import type {Meta, StoryObj} from '@storybook/react'
import ModelsFilters from './ModelsFilters'
import {type FilterContextType, FilterContext} from '@github-ui/marketplace-common/FilterContext'
import {categoryOptions, modelFamilyOptions, taskOptions} from '@github-ui/marketplace-common/model-filter-options'
import {parametersConfig} from '../utils/story-utils'

type StoryArgs = Omit<FilterContextType, 'setModelFamily' | 'setCategory' | 'setTask'>

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/ModelsFilters',
  component: ModelsFilters,
  args: {
    loading: false,
    modelFamily: modelFamilyOptions[0],
    category: categoryOptions[0]?.id,
    task: taskOptions[0],
  },
  argTypes: {
    loading: {control: {type: 'boolean'}},
    modelFamily: {control: 'select', options: modelFamilyOptions},
    category: {control: 'select', options: categoryOptions},
    task: {control: 'select', options: taskOptions},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: () => <ModelsFilters />,
  decorators: [
    (
      Story,
      {args: {category: initialCategory, modelFamily: initialModelFamily, task: initialTask, ...filterContext}},
    ) => {
      const [modelFamily, setModelFamily] = useState(initialModelFamily)
      const [category, setCategory] = useState(initialCategory)
      const [task, setTask] = useState(initialTask)

      useEffect(() => {
        setModelFamily(initialModelFamily)
      }, [initialModelFamily])

      useEffect(() => {
        setCategory(initialCategory)
      }, [initialCategory])

      useEffect(() => {
        setTask(initialTask)
      }, [initialTask])

      return (
        <FilterContext.Provider
          value={{category, setCategory, modelFamily, setModelFamily, task, setTask, ...filterContext}}
        >
          <Story />
        </FilterContext.Provider>
      )
    },
  ],
}
