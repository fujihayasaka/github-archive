import {noop} from '@github-ui/noop'
import {disableA11yRuleForDialog, storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'

import {SingleSelectReposPickerDialog} from './SingleSelectReposPickerDialog'
import {handlers} from './test-utils/mock-data'
import {sampleRepos} from './test-utils/test-helpers'

const meta = {
  title: 'Recipes/ReposPicker/Dialog/Single-select',
  component: SingleSelectReposPickerDialog,
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
} satisfies Meta<typeof SingleSelectReposPickerDialog>

export default meta

type Story = StoryObj<typeof SingleSelectReposPickerDialog>

export const Default: Story = {}

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
