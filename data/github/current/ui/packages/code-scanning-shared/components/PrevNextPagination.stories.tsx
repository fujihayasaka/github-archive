import type {Meta} from '@storybook/react'
import {PrevNextPagination, type PrevNextPaginationProps} from './PrevNextPagination'

const meta = {
  title: 'Recipes/PrevNextPagination',
  component: PrevNextPagination,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {
    prevCursor: {control: 'text', defaultValue: 'Foo'},
    nextCursor: {control: 'text', defaultValue: 'Bar'},
  },
} satisfies Meta<typeof PrevNextPagination>

export default meta

const defaultArgs: Partial<PrevNextPaginationProps> = {
  prevCursor: 'Foo',
  nextCursor: 'Bar',
  onCursorChange: () => {},
}

export const PrevNextPaginationExample = {
  args: {
    ...defaultArgs,
  },
  render: (args: PrevNextPaginationProps) => <PrevNextPagination {...args} />,
}
