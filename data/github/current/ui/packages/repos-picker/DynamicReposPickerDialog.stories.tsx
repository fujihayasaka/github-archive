import {noop} from '@github-ui/noop'
import {disableA11yRuleForDialog, storyWrapper} from '@github-ui/react-core/test-utils'
import {getDefaultReposProviders} from '@github-ui/repos-filter/providers'
import type {Meta, StoryObj} from '@storybook/react'

import {DynamicReposPickerDialog} from './DynamicReposPickerDialog'
import {handlers} from './test-utils/mock-data'

const meta = {
  title: 'Recipes/ReposPicker/Dialog/Dynamic',
  component: DynamicReposPickerDialog,
  decorators: [storyWrapper()],
  args: {
    providers: getDefaultReposProviders([]),
    scope: {type: 'organization', slug: 'acme'},
    onSubmit: noop,
  },
  parameters: {
    a11y: disableA11yRuleForDialog,
    msw: {
      handlers: handlers.success,
    },
  },
} satisfies Meta<typeof DynamicReposPickerDialog>

export default meta

type Story = StoryObj<typeof DynamicReposPickerDialog>

export const Default: Story = {}

export const NumerousRepos: Story = {
  parameters: {
    msw: {
      handlers: handlers.numerousRepos,
    },
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
