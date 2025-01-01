import {noop} from '@github-ui/noop'
import {disableA11yRuleForDialog, storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'

import {MultiSelectReposPickerDialog} from './MultiSelectReposPickerDialog'
import {handlers} from './test-utils/mock-data'
import {buildRepo} from './test-utils/test-helpers'

const meta = {
  title: 'Recipes/ReposPicker/Dialog/Multi-select',
  component: MultiSelectReposPickerDialog,
  decorators: [storyWrapper()],
  args: {
    scope: {type: 'organization', slug: 'acme'},
    onSubmit: noop,
  },
  parameters: {
    a11y: disableA11yRuleForDialog,
    msw: {
      handlers: handlers.success,
    },
  },
} satisfies Meta<typeof MultiSelectReposPickerDialog>

export default meta

type Story = StoryObj<typeof MultiSelectReposPickerDialog>

export const Default: Story = {}

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

export const CustomRepoItem: Story = {
  args: {
    getSearchUrl: query => `/billing/repos-search?q=${query}`,
    onRenderFooterDetails: () => <div className="flex-1 text-mono">&lt;custom footer&gt;</div>,
  },
  parameters: {
    msw: {
      handlers: handlers.successForBilling,
    },
  },
}
