import type {Meta, StoryObj} from '@storybook/react'
import {ClosedOrMergedStateMergeBox} from './ClosedOrMergedStateMergeBox'
import {within} from '@testing-library/react'
import {expect} from '@storybook/jest'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {QueryClientProvider} from '@tanstack/react-query'
import {http, HttpResponse} from 'msw'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'

type Story = StoryObj<typeof ClosedOrMergedStateMergeBox>

const deleteHeadRefPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.deleteHeadRef}`
const restoreHeadRefPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.restoreHeadRef}`

const meta = {
  title: 'Pull Requests/mergebox/ClosedOrMergedStateMergeBox',
  component: ClosedOrMergedStateMergeBox,
  decorators: [
    Story => (
      <div style={{maxWidth: '800px'}}>
        <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
          <QueryClientProvider client={queryClient}>
            <Story />
          </QueryClientProvider>
        </PageDataContextProvider>
      </div>
    ),
  ],
} satisfies Meta<typeof ClosedOrMergedStateMergeBox>

export const Default: Story = {
  args: {
    state: 'CLOSED',
    headRefName: 'monalisa/my-branch-to-update-broken-tests',
    viewerCanDeleteHeadRef: true,
    viewerCanRestoreHeadRef: true,
  },
  argTypes: {
    state: {
      options: ['CLOSED', 'MERGED'],
      control: 'radio',
    },
    headRepository: {
      table: {disable: true},
    },
  },
  render: function Component(args) {
    return (
      <>
        <ClosedOrMergedStateMergeBox {...args} />
      </>
    )
  },
}

export const CanDeleteBranch: Story = {
  ...Default,
  args: {
    ...Default.args,
  },
  parameters: {
    msw: {
      handlers: [
        http.post(deleteHeadRefPageDataRoute, () => {
          return HttpResponse.json({}, {status: 200})
        }),
      ],
    },
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    await canvas.getByRole('button', {name: /delete branch/i}).click()

    expect(await canvas.findByRole('button', {name: /Deleting branch.../i})).toHaveAttribute('aria-disabled', 'true')
  },
}

export const CanRestoreBranch: Story = {
  ...Default,
  args: {
    ...Default.args,
    viewerCanDeleteHeadRef: false,
  },
  parameters: {
    msw: {
      handlers: [
        http.post(restoreHeadRefPageDataRoute, () => {
          return HttpResponse.json({}, {status: 200})
        }),
      ],
    },
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    await canvas.getByRole('button', {name: /restore branch/i}).click()

    expect(await canvas.findByRole('button', {name: /Restoring branch.../i})).toHaveAttribute('aria-disabled', 'true')
  },
}

export const ErrorDeletingBranch: Story = {
  ...Default,
  args: {
    ...Default.args,
  },
  parameters: {
    msw: {
      handlers: [
        http.post(deleteHeadRefPageDataRoute, () => {
          return HttpResponse.json({error: 'Unable to update branch'}, {status: 422})
        }),
      ],
    },
  },
}

export const ErrorRestoringBranch: Story = {
  ...Default,
  args: {
    ...Default.args,
    viewerCanDeleteHeadRef: false,
  },
  parameters: {
    msw: {
      handlers: [
        http.post(restoreHeadRefPageDataRoute, () => {
          return HttpResponse.json({error: 'Unable to update branch'}, {status: 422})
        }),
      ],
    },
  },
}

export default meta
