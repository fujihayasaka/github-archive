import type {Meta, StoryObj} from '@storybook/react'
import {VariablesDialog} from './VariablesDialog'
import {mockModel} from '../../../test-utils/mock-data'

const meta = {
  title: 'Apps/GitHub Models repository/VariablesDialog',
  component: VariablesDialog,
  args: {
    primaryTitle: 'Save',
    variables: {foo: 'bar', baz: 'qux'},
    availableVariables: new Set(['foo', 'baz']),
    model: mockModel(),
  },
} satisfies Meta<typeof VariablesDialog>

export default meta

type Story = StoryObj<typeof VariablesDialog>

export const Example = {} satisfies Story
