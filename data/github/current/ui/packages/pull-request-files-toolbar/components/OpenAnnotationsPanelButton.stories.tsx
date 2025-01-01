import type {Meta, StoryObj} from '@storybook/react'
import {expect, within, userEvent} from '@storybook/test'
import {buildAnnotation} from '@github-ui/conversations/test-utils'
import {shouldInteractionPlay} from '@github-ui/storybook'

import {OpenAnnotationsPanelButton} from './OpenAnnotationsPanelButton'

const meta: Meta<typeof OpenAnnotationsPanelButton> = {
  title: 'Pull Requests/FilesToolbar/OpenAnnotationsPanelButton',
  component: OpenAnnotationsPanelButton,
} satisfies Meta<typeof OpenAnnotationsPanelButton>

type Story = StoryObj<typeof OpenAnnotationsPanelButton>

export const WithNoAnnotations: Story = {
  render: () => <OpenAnnotationsPanelButton annotations={[]} />,
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    await step('It does not render a button', async () => {
      await expect(canvas.queryByRole('button', {name: 'Open annotations side panel'})).not.toBeInTheDocument()
    })
  },
}

export const WithOneAnnotation: Story = {
  render: () => <OpenAnnotationsPanelButton annotations={[buildAnnotation({})]} />,
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    let openPanelBtn: HTMLButtonElement
    await step('It renders a button', async () => {
      openPanelBtn = await canvas.findByRole('button', {name: 'Open annotations side panel'})
    })

    await step('Clicking the button opens the side panel and renders 1 annotation', async () => {
      await userEvent.click(openPanelBtn)
      expect(canvas.getByText('Annotations')).toBeInTheDocument()
      expect(canvas.getAllByLabelText('Jump to the annotation in the diff')).toHaveLength(1)
    })

    await step('Clicking the close button (e.g. "X" icon button) closes the side panel', async () => {
      const closeButton = await canvas.findByRole('button', {name: 'Close annotations panel'})
      await userEvent.click(closeButton)
      expect(canvas.queryByText('Annotations')).not.toBeInTheDocument()
    })
  },
}

export const WithMultipleAnnotation: Story = {
  render: () => <OpenAnnotationsPanelButton annotations={[buildAnnotation({}), buildAnnotation({})]} />,
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    let openPanelBtn: HTMLButtonElement
    await step('It renders a button', async () => {
      openPanelBtn = await canvas.findByRole('button', {name: 'Open annotations side panel'})
    })

    await step('Clicking the button opens the side panel and renders 2 annotations', async () => {
      await userEvent.click(openPanelBtn)
      expect(canvas.getByText('Annotations')).toBeInTheDocument()
      expect(canvas.getAllByLabelText('Jump to the annotation in the diff')).toHaveLength(2)
    })

    await step('Clicking the close button (e.g. "X" icon button) closes the side panel', async () => {
      const closeButton = await canvas.findByRole('button', {name: 'Close annotations panel'})
      await userEvent.click(closeButton)
      expect(canvas.queryByText('Annotations')).not.toBeInTheDocument()
    })
  },
}

export default meta
