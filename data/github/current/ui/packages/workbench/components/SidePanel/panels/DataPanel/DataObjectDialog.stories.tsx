import {action} from '@storybook/addon-actions'
import type {ArgTypes, Meta} from '@storybook/react'

import {
  databaseContextDecoratorArgs,
  databaseContextDecoratorArgTypes,
  withDatabaseContext,
} from '../../../../contexts/.storybook/WithDatabaseContext'
import {DATABASE_DEFAULT} from '../../../../utilities/parse-data'
import {DataObjectDialog, type DataObjectDialogProps} from './DataObjectDialog'

const DataObjectDialogArgs: Partial<DataObjectDialogProps> = {
  currentTable: {
    table: 'mockTable',
    data: {
      type: 'string',
      data: 'simple string data',
    },
  },
  readOnly: false,
}

const DataObjectDialogArgTypes: ArgTypes<Partial<DataObjectDialogProps>> = {
  currentTable: {
    table: {
      disable: true,
    },
  },
  readOnly: {
    control: 'boolean',
    description: 'Is the dialog in read-only mode?',
  },
}

export default {
  title: 'Apps/Workbench/Components/SidePanel/Panels/DataPanel/DataObjectDialog',
  component: DataObjectDialog,
  argTypes: {
    ...DataObjectDialogArgTypes,
    ...databaseContextDecoratorArgTypes,
  },
  args: {
    ...DataObjectDialogArgs,
    ...databaseContextDecoratorArgs,
  },
  decorators: [withDatabaseContext],
  render: (props, {args}) => {
    return <DataObjectDialog readOnly={args.readOnly} currentTable={args.currentTable} onClose={action('onClose')} />
  },
} satisfies Meta<typeof DataObjectDialog>

export const Default = {
  args: {
    readOnly: false,
  },
}

export const ReadOnly = {
  args: {
    readOnly: true,
  },
}

export const SimpleObject = {
  args: {
    currentTable: {
      table: 'mockTable',
      data: {
        type: 'object',
        data: DATABASE_DEFAULT.keySimpleObject,
      },
    },
  },
}

export const SimpleTable = {
  args: {
    currentTable: {
      table: 'mockTable',
      data: {
        type: 'table',
        data: DATABASE_DEFAULT.keySimpleTableArray,
        allKeys: Object.keys(DATABASE_DEFAULT.keySimpleTableArray[0]),
      },
    },
  },
}

export const ComplexTable = {
  args: {
    currentTable: {
      table: 'mockTable',
      data: {
        type: 'table',
        data: DATABASE_DEFAULT.keyComplexTableArray,
        allKeys: [
          ...new Set([
            ...Object.keys(DATABASE_DEFAULT.keyComplexTableArray[0]),
            ...Object.keys(DATABASE_DEFAULT.keyComplexTableArray[1]),
          ]),
        ],
      },
    },
  },
}
