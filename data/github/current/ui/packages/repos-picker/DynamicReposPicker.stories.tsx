import {noop} from '@github-ui/noop'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {
  getCustomPropertiesProvider,
  getDefaultReposProviders,
  getRepoFilterProviders,
  LanguageStaticFilterProvider,
} from '@github-ui/repos-filter/providers'
import type {Meta, StoryObj} from '@storybook/react'
import {useState} from 'react'

import {DynamicReposPicker} from './DynamicReposPicker'
import {handlers} from './test-utils/mock-data'

const meta = {
  title: 'Recipes/ReposPicker/Dynamic',
  component: DynamicReposPicker,
  decorators: [storyWrapper()],
  args: {
    providers: getDefaultReposProviders([]),
    scope: {type: 'organization', slug: 'acme'},
    onSubmit: noop,
  },
  parameters: {
    msw: {
      handlers: handlers.success,
    },
  },
} satisfies Meta<typeof DynamicReposPicker>

type Story = StoryObj<typeof DynamicReposPicker>

export default meta

export const Default: Story = {}

export const Enterprise = {
  args: {
    scope: {type: 'enterprise', slug: 'acme-corp'},
  },
}

export const RestrictedProviders: Story = {
  args: {
    providers: [
      ...getRepoFilterProviders(['fork', 'visibility']),
      getCustomPropertiesProvider([{propertyName: 'team', valueType: 'string'}], {valueless: false, multiKey: false}),
      new LanguageStaticFilterProvider(),
    ],
    warnIfUnsupportedProvider: true,
  },
  parameters: {
    msw: {
      handlers: handlers.success,
    },
  },
}

export const NumerousRepos: Story = {
  args: {
    query: 'repo-1',
  },
  parameters: {
    msw: {
      handlers: handlers.numerousRepos,
    },
  },
}

export const Stateful = () => {
  const [q, setQ] = useState('language:Ruby')

  return (
    <DynamicReposPicker
      query={q}
      scope={{type: 'organization', slug: 'acme'}}
      onSubmit={setQ}
      providers={getDefaultReposProviders([])}
    />
  )
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
