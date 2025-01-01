import type {Meta, StoryObj} from '@storybook/react'
import {CompareTableBox} from './CompareTableBox'
import {DataTable} from '@primer/react/experimental'

const meta = {
  title: 'Apps/GitHub Models repository/CompareTableBox',
  component: CompareTableBox,
  args: {
    children: 'Content goes here',
    heading: 'Heading',
    id: 'compare-table-box',
  },
} satisfies Meta<typeof CompareTableBox>

export default meta

type Story = StoryObj<typeof CompareTableBox>

export const Example = {} satisfies Story

export const WithDataTable = {
  render() {
    return (
      <CompareTableBox id="compare-table-box" heading="Data">
        <DataTable
          columns={[
            {header: 'Column 1', field: 'col1'},
            {header: 'Column 2', field: 'col2'},
          ]}
          data={[
            {id: 0, col1: 'Data 1', col2: 'Data 2'},
            {id: 1, col1: 'Data 3', col2: 'Data 4'},
            {id: 2, col1: 'Data 5', col2: 'Data 6'},
          ]}
        />
      </CompareTableBox>
    )
  },
} satisfies Story
