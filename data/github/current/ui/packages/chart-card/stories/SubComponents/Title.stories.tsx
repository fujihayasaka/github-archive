import type {Meta, StoryObj} from '@storybook/react'

import TitleComponent, {type TitleProps} from '../../ChartCard/Title'
import ChartCardContext from '../../ChartCard/context'

const meta: Meta<typeof TitleComponent> = {
  title: 'Recipes/ChartCard/SubComponents/Title',
  component: TitleComponent,
}

export default meta

export const Title: StoryObj<TitleProps> = {
  args: {
    as: 'h3',
    children: 'Title',
  },
  render: (args: TitleProps) => (
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
      <TitleComponent as={args.as}>{args.children}</TitleComponent>
    </ChartCardContext.Provider>
  ),
}
Title.storyName = 'Title'
