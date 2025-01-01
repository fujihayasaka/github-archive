import {action} from '@storybook/addon-actions'
import type {ArgTypes, Meta} from '@storybook/react'

import {
  databaseContextDecoratorArgs,
  databaseContextDecoratorArgTypes,
  withDatabaseContext,
} from '../../../../contexts/.storybook/WithDatabaseContext'
import {DATABASE_DEFAULT} from '../../../../utilities/parse-data'
import {DataTableEntryDialog, type DataTableEntryDialogProps} from './DataTableEntryDialog'

const DataTableEntryDialogArgTypes: ArgTypes<Partial<DataTableEntryDialogProps>> = {
  readOnly: {
    control: 'boolean',
    description: 'Is the dialog in read-only mode?',
  },
  data: {
    table: {
      disable: true,
    },
  },
  allKeys: {
    table: {
      disable: true,
    },
  },
}

const DataTableEntryDialogArgs: Partial<DataTableEntryDialogProps> = {
  data: DATABASE_DEFAULT.keySimpleObject,
  allKeys: Object.keys(DATABASE_DEFAULT.keySimpleObject),
  readOnly: false,
}

export default {
  title: 'Apps/Workbench/Components/SidePanel/Panels/DataPanel/DataTableEntryDialog',
  component: DataTableEntryDialog,
  decorators: [withDatabaseContext],
  argTypes: {
    ...DataTableEntryDialogArgTypes,
    ...databaseContextDecoratorArgTypes,
  },
  args: {
    ...DataTableEntryDialogArgs,
    ...databaseContextDecoratorArgs,
  },
  render: (props, {args}) => {
    return (
      <DataTableEntryDialog
        onClose={action('onClose')}
        onUpdate={async () => {
          action('onUpdate')
        }}
        onDelete={async () => {
          action('onDelete')
        }}
        data={args.data}
        allKeys={args.allKeys}
        readOnly={args.readOnly}
      />
    )
  },
} satisfies Meta<typeof DataTableEntryDialog>

export const SimpleObject = {
  args: {
    readOnly: false,
  },
}

export const ReadOnly = {
  args: {
    readOnly: true,
  },
}

export const ComplexObject = {
  args: {
    data: DATABASE_DEFAULT.keyComplexTableArray[1],
    // some complicated logic to get all the keys, but that's because this `keyComplexTableArray`
    // intentionally has different keys in different objects (for non-uniform database cases)
    allKeys: [
      ...new Set([
        ...Object.keys(DATABASE_DEFAULT.keyComplexTableArray[0]),
        ...Object.keys(DATABASE_DEFAULT.keyComplexTableArray[1]),
      ]),
    ],
  },
}
