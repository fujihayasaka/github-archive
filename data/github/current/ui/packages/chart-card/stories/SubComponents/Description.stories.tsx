import type {Meta, StoryObj} from '@storybook/react'

import DescriptionComponent, {type DescriptionProps} from '../../ChartCard/Description'
import ChartCardContext from '../../ChartCard/context'

const meta: Meta<typeof DescriptionComponent> = {
  title: 'Recipes/ChartCard/SubComponents/Description',
  component: DescriptionComponent,
}

export default meta

export const Description: StoryObj<DescriptionProps> = {
  args: {
    children: 'Description',
  },
  render: (args: DescriptionProps) => (
    <ChartCardContext.Provider
      value={{
        title: '',
        setTitle: () => {},
        description: '',
        setDescription: () => {},
        size: 'medium',
        chartRef: {current: null},
      }}
    >
      <DescriptionComponent>{args.children}</DescriptionComponent>
    </ChartCardContext.Provider>
  ),
}
Description.storyName = 'Description'
