import type {Meta, StoryObj} from '@storybook/react'
import {expect, within, userEvent} from '@storybook/test'
import {shouldInteractionPlay} from '@github-ui/storybook'

import {OpenAlertsPanelButton} from './OpenAlertsPanelButton'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {buildAnnotation} from '@github-ui/conversations/test-utils'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {getFilesRoutePayload} from '../../test-utils/files-changed/files-mock-data'

const meta: Meta<typeof OpenAlertsPanelButton> = {
  title: 'Pull Requests/FilesToolbar/OpenAlertsPanelButton',
  component: OpenAlertsPanelButton,
} satisfies Meta<typeof OpenAlertsPanelButton>

type Story = StoryObj<typeof OpenAlertsPanelButton>

export const WithNoAnnotations: Story = {
  render: () => {
    // We don't have an endpoint set up for markers yet, so just directly set the data instead of using msw
    const queryClient = getQueryClient()
    queryClient.setQueryData([PageData.markers, ''], {
      threads: {},
      annotations: {},
    })
    return <OpenAlertsPanelButton basePath="" pageLimits={getFilesRoutePayload().pageLimits} />
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    await step('It does not render a button', async () => {
      await expect(canvas.queryByRole('button', {name: 'Open alerts side panel'})).not.toBeInTheDocument()
    })
  },
}

export const WithOneAnnotation: Story = {
  render: () => {
    // We don't have an endpoint set up for markers yet, so just directly set the data instead of using msw
    const queryClient = getQueryClient()
    queryClient.setQueryData([PageData.markers, ''], {
      threads: {},
      annotations: {15: buildAnnotation({databaseId: 15})},
    })

    return <OpenAlertsPanelButton basePath="" pageLimits={getFilesRoutePayload().pageLimits} />
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    let openPanelBtn: HTMLButtonElement
    await step('It renders a button', async () => {
      openPanelBtn = await canvas.findByRole('button', {name: 'Open alerts side panel'})
    })

    await step('Clicking the button opens the side panel and renders 1 annotation', async () => {
      await userEvent.click(openPanelBtn)
      expect(canvas.getByRole('heading', {name: 'Alerts'})).toBeInTheDocument()
      expect(canvas.getAllByLabelText('Jump to the alert in the diff')).toHaveLength(1)
    })

    await step('Clicking the close button (e.g. "X" icon button) closes the side panel', async () => {
      const closeButton = await canvas.findByRole('button', {name: 'Close alerts panel'})
      await userEvent.click(closeButton)
      expect(canvas.queryByRole('heading', {name: 'Alerts'})).not.toBeInTheDocument()
    })
  },
}

export const WithMultipleAnnotation: Story = {
  render: () => {
    // We don't have an endpoint set up for markers yet, so just directly set the data instead of using msw
    const queryClient = getQueryClient()
    queryClient.setQueryData([PageData.markers, ''], {
      threads: {},
      annotations: {
        15: buildAnnotation({databaseId: 15}),
        16: buildAnnotation({databaseId: 16}),
      },
    })

    return <OpenAlertsPanelButton basePath="" pageLimits={getFilesRoutePayload().pageLimits} />
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    let openPanelBtn: HTMLButtonElement
    await step('It renders a button', async () => {
      openPanelBtn = await canvas.findByRole('button', {name: 'Open alerts side panel'})
    })

    await step('Clicking the button opens the side panel and renders 2 annotations', async () => {
      await userEvent.click(openPanelBtn)
      expect(canvas.getByRole('heading', {name: 'Alerts'})).toBeInTheDocument()
      expect(canvas.getAllByLabelText('Jump to the alert in the diff')).toHaveLength(2)
    })

    await step('Clicking the close button (e.g. "X" icon button) closes the side panel', async () => {
      const closeButton = await canvas.findByRole('button', {name: 'Close alerts panel'})
      await userEvent.click(closeButton)
      expect(canvas.queryByRole('heading', {name: 'Alerts'})).not.toBeInTheDocument()
    })
  },
}

export const WarningLimitBanner: Story = {
  parameters: {
    a11y: {
      test: 'todo',
    },
  },
  render: () => {
    // We don't have an endpoint set up for markers yet, so just directly set the data instead of using msw
    const queryClient = getQueryClient()
    queryClient.setQueryData([PageData.markers, ''], {
      threads: {},
      annotations: {
        15: buildAnnotation({databaseId: 15}),
        16: buildAnnotation({databaseId: 16}),
      },
    })

    return (
      <OpenAlertsPanelButton
        basePath=""
        pageLimits={{
          annotationsLimit: 20,
          annotationsLimitExceeded: true,
          filesLimit: 300,
          filesLimitExceeded: false,
          reviewThreadsLimit: 20,
          reviewThreadsLimitExceeded: false,
        }}
      />
    )
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    let openPanelBtn: HTMLButtonElement
    await step('It renders a button', async () => {
      openPanelBtn = await canvas.findByRole('button', {name: 'Open alerts side panel'})
    })

    await step('Clicking the button opens the side panel', async () => {
      await userEvent.click(openPanelBtn)
      expect(canvas.getByRole('heading', {name: 'Alerts'})).toBeInTheDocument()
      expect(canvas.getAllByLabelText('Jump to the alert in the diff')).toHaveLength(2)
    })

    await step('renders warning banner', async () => {
      canvas.getByText('Only the first 20 alerts are currently being shown.')
    })
  },
}

export default meta
