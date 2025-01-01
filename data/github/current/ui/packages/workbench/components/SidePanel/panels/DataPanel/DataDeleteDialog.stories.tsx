import {action} from '@storybook/addon-actions'
import type {ArgTypes, Meta} from '@storybook/react'

import {DataDeleteDialog, type DataDeleteDialogProps} from './DataDeleteDialog'

const generateRows = (count: number) =>
  new Set(
    Array(count)
      .fill(0)
      .map((_, i) => `row-${i}`),
  )

const DataDeleteDialogArgTypes: ArgTypes<Partial<DataDeleteDialogProps>> = {
  readOnly: {
    control: 'boolean',
    description: 'Is the dialog in read-only mode?',
  },
  deleteTarget: {
    control: 'select',
    options: ['selected', 'single', 'all'],
    description: 'What is the target for deletion?',
  },
  selectedRows: {
    table: {
      disable: true,
    },
  },
}

const DataDeleteDialogArgs: Partial<DataDeleteDialogProps> = {
  readOnly: false,
  deleteTarget: 'single',
  selectedRows: undefined,
}

export default {
  title: 'Apps/Workbench/Components/SidePanel/Panels/DataPanel/DataDeleteDialog',
  component: DataDeleteDialog,
  argTypes: {
    ...DataDeleteDialogArgTypes,
  },
  args: {
    ...DataDeleteDialogArgs,
  },
  render: (props, {args}) => {
    return (
      <DataDeleteDialog
        readOnly={args.readOnly}
        deleteTarget={args.deleteTarget}
        selectedRows={args.selectedRows}
        onConfirm={async () => {
          action('onConfirm')
        }}
        onCancel={async () => {
          action('onCancel')
        }}
      />
    )
  },
} satisfies Meta<typeof DataDeleteDialog>

export const Single = {
  args: {
    deleteTarget: 'single',
  },
}

export const Selected = {
  args: {
    deleteTarget: 'selected',
    selectedRows: generateRows(5),
  },
}

export const SelectedForty = {
  args: {
    deleteTarget: 'selected',
    selectedRows: generateRows(40),
  },
}

export const All = {
  args: {
    deleteTarget: 'all',
  },
}

export const ReadOnly = {
  args: {
    readOnly: true,
  },
}
