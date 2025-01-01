import {noop} from '@github-ui/noop'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {SingleSelectReposPickerDialog} from './SingleSelectReposPickerDialog'
import {handlers} from './test-utils/mock-data'
import {sampleRepos} from './test-utils/test-helpers'

const meta = {
  title: 'Recipes/ReposPicker/Dialog/Single-select',
  component: SingleSelectReposPickerDialog,
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
} satisfies Meta<typeof SingleSelectReposPickerDialog>

export default meta

export const Default = {}

export const NumerousRepos = {
  parameters: {
    msw: {
      handlers: handlers.numerousRepos,
    },
  },
}

export const WithInitialValue = {
  args: {
    selected: sampleRepos[1],
  },
}
