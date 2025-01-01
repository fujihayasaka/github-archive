import type {Meta, StoryObj} from '@storybook/react'
import CommandLineInstructionsDialog, {type CommandLineInstructionsDialogProps} from './CommandLineInstructionsDialog'
import {noop} from '@github-ui/noop'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {http, HttpResponse} from 'msw'
import {defaultMergeInstructionsApiResponse} from '../../../../test-utils/mocks/merge-instructions-mock'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {QueryClientProvider} from '@tanstack/react-query'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'

const mergeInstructionsPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.mergeInstructions}`

const meta: Meta = {
  title: 'Pull Requests/mergebox/MergeSection/CommandLineInstructionsDialog',
  component: CommandLineInstructionsDialog,
  decorators: [
    Story => {
      return (
        <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
          <QueryClientProvider client={queryClient}>
            <div style={{maxWidth: '600px'}}>
              <Story />
            </div>
          </QueryClientProvider>
        </PageDataContextProvider>
      )
    },
  ],
}

type Story = StoryObj<CommandLineInstructionsDialogProps>

const defaultProps: CommandLineInstructionsDialogProps = {
  baseRefName: 'main',
  conflictsCondition: {result: 'PASSED'},
  headRepository: {ownerLogin: 'wiseguy', name: 'source'},
  isCrossRepo: false,
  onClose: noop,
  returnFocusRef: {current: null},
}

export const Default: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(mergeInstructionsPageDataRoute, () => {
          return HttpResponse.json(defaultMergeInstructionsApiResponse)
        }),
      ],
    },
  },
  render: args => {
    const props = {
      ...defaultProps,
      ...args,
    }

    return <CommandLineInstructionsDialog {...props} />
  },
}

export const WithConflicts: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(mergeInstructionsPageDataRoute, () => {
          return HttpResponse.json(defaultMergeInstructionsApiResponse)
        }),
      ],
    },
  },
  render: args => {
    const props = {
      ...defaultProps,
      ...{conflictsCondition: {result: 'FAILED'}},
      ...args,
    }

    return <CommandLineInstructionsDialog {...props} />
  },
}

export const CrossRepo: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(mergeInstructionsPageDataRoute, () => {
          return HttpResponse.json(defaultMergeInstructionsApiResponse)
        }),
      ],
    },
  },
  render: args => {
    const props = {
      ...defaultProps,
      ...{isCrossRepo: true},
      ...args,
    }

    return <CommandLineInstructionsDialog {...props} />
  },
}

export const WithoutHeadRepo: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(mergeInstructionsPageDataRoute, () => {
          return HttpResponse.json(defaultMergeInstructionsApiResponse)
        }),
      ],
    },
  },
  render: args => {
    const props = {
      ...defaultProps,
      ...{headRepository: null},
      ...args,
    }

    return <CommandLineInstructionsDialog {...props} />
  },
}

export const ErrorState: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(mergeInstructionsPageDataRoute, () => {
          return HttpResponse.json({}, {status: 500})
        }),
      ],
    },
  },
  render: args => {
    const props = {
      ...defaultProps,
      ...args,
    }

    return <CommandLineInstructionsDialog {...props} />
  },
}

export default meta
