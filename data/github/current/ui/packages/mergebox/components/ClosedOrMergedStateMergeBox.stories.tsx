import type {Meta, StoryObj} from '@storybook/react'
import {ClosedOrMergedStateMergeBox} from './ClosedOrMergedStateMergeBox'
import {within} from '@testing-library/react'
import {shouldInteractionPlay} from '@github-ui/storybook'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {delay, http, HttpResponse} from 'msw'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {expect, userEvent} from '@storybook/test'

type Story = StoryObj<typeof ClosedOrMergedStateMergeBox>

const deleteHeadRefPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.deleteHeadRef}`
const cleanupCodespacesPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.cleanupCodespaces}`

const meta = {
  title: 'Pull Requests/Merge Box/ClosedOrMergedStateMergeBox',
  component: ClosedOrMergedStateMergeBox,
  decorators: [
    Story => (
      <div style={{maxWidth: '800px'}}>
        <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
          <Story />
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
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    const button = canvas.getByRole('button', {name: /delete branch/i})

    expect(button).not.toHaveAttribute('aria-disabled', 'true')
    expect(button).not.toHaveAccessibleDescription()

    await userEvent.click(button)

    expect(button).toHaveAttribute('aria-disabled', 'true')
    expect(button).toHaveAccessibleDescription('Deleting branch')
  },
}

export const DeletedBranch: Story = {
  args: {
    state: 'CLOSED',
    headRefName: 'monalisa/my-branch-to-update-broken-tests',
    viewerCanDeleteHeadRef: false,
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

export const canDeleteCodespace: Story = {
  args: {
    state: 'MERGED',
    headRefName: 'monalisa/my-branch-to-update-broken-tests',
    deprovisionableCodespaces: {
      count: 3,
      repositoryCodespacePath: '/repo/codespaces',
    },
    viewerCanRestoreHeadRef: true,
    viewerCanDeleteHeadRef: false,
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
  parameters: {
    msw: {
      handlers: [
        http.post(cleanupCodespacesPageDataRoute, () => {
          return HttpResponse.json({}, {status: 200})
        }),
      ],
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

export const ErrorDeletingCodespaces: Story = {
  ...Default,
  args: {
    state: 'MERGED',
    headRefName: 'monalisa/my-branch-to-update-broken-tests',
    deprovisionableCodespaces: {
      count: 3,
      repositoryCodespacePath: '/repo/codespaces',
    },
    viewerCanRestoreHeadRef: true,
    viewerCanDeleteHeadRef: false,
  },
  parameters: {
    msw: {
      handlers: [
        http.post(cleanupCodespacesPageDataRoute, () => {
          return HttpResponse.json({error: 'Some codespaces could not be deleted'}, {status: 422})
        }),
      ],
    },
  },
}

export const PendingDeleteCodespaces: Story = {
  ...Default,
  args: {
    state: 'MERGED',
    headRefName: 'monalisa/my-branch-to-update-broken-tests',
    deprovisionableCodespaces: {
      count: 3,
      repositoryCodespacePath: '/repo/codespaces',
    },
    viewerCanRestoreHeadRef: true,
    viewerCanDeleteHeadRef: false,
  },
  parameters: {
    msw: {
      handlers: [
        http.post(cleanupCodespacesPageDataRoute, async () => {
          await delay('infinite')
          return HttpResponse.json({}, {status: 202})
        }),
      ],
    },
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

export const PendingDelete: Story = {
  ...Default,
  args: {
    ...Default.args,
  },
  parameters: {
    msw: {
      handlers: [
        http.post(deleteHeadRefPageDataRoute, async () => {
          await delay('infinite')
          return HttpResponse.json({}, {status: 202})
        }),
      ],
    },
  },
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)

    await step('User clicking delete branch moves button to pending state', async () => {
      const button = await canvas.findByRole('button', {name: 'Delete branch'})

      await userEvent.click(button)
    })
  },
}

export default meta
