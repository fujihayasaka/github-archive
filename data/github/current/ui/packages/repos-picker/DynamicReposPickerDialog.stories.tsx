import {noop} from '@github-ui/noop'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {DynamicReposPickerDialog} from './DynamicReposPickerDialog'
import {handlers} from './test-utils/mock-data'

const meta = {
  title: 'Recipes/ReposPicker/Dialog/Dynamic',
  component: DynamicReposPickerDialog,
  decorators: [storyWrapper()],
  args: {
    orgLogin: 'acme',
    onSubmit: noop,
  },
  parameters: {
    msw: {
      handlers: handlers.success,
    },
  },
} satisfies Meta<typeof DynamicReposPickerDialog>

export default meta

export const Default = {}

export const NumerousRepos = {
  parameters: {
    msw: {
      handlers: handlers.numerousRepos,
    },
  },
}
