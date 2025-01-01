import {noop} from '@github-ui/noop'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {MultiSelectReposPickerDialog} from './MultiSelectReposPickerDialog'
import {handlers} from './test-utils/mock-data'
import {buildRepo} from './test-utils/test-helpers'

const meta = {
  title: 'Recipes/ReposPicker/Dialog/Multi-select',
  component: MultiSelectReposPickerDialog,
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
} satisfies Meta<typeof MultiSelectReposPickerDialog>

export default meta

export const Default = {}

export const NumerousRepos = {
  parameters: {
    msw: {
      handlers: handlers.numerousRepos,
    },
  },
}

export const NumerousSelected = {
  args: {
    selected: Array.from({length: 2345}, (_, i) => buildRepo(`repo-${i + 1}`, i + 100)),
  },
}
