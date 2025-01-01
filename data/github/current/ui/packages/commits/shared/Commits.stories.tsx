import {createRepository} from '@github-ui/current-repository/test-helpers'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {shouldInteractionPlay} from '@github-ui/storybook'
import type {Meta, StoryObj} from '@storybook/react'
import {expect, userEvent, within} from '@storybook/test'

import {deferredData} from '../test-utils/mock-data'
import {Commits, type CommitsProps} from './Commits'
import {generateCommitGroups} from './test-helpers'

const meta = {
  title: 'Apps/Commits/Shared/Commits',
  component: Commits,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof Commits>

export default meta

const defaultArgs: Partial<CommitsProps> = {
  repository: createRepository(),
  commitGroups: generateCommitGroups(2, 5, false),
  deferredCommitData: deferredData,
  shouldClipTimeline: true,
}
const randomizedGroupsArgs: Partial<CommitsProps> = {
  repository: createRepository(),
  commitGroups: generateCommitGroups(2, 5, true),
  deferredCommitData: deferredData,
  shouldClipTimeline: true,
}

type Story = StoryObj<typeof Commits>

export const ShiftTabAndTabBehaviorWorksAsExpected: Story = {
  args: {
    ...defaultArgs,
  },
  render: (args: CommitsProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <Commits {...args} />
    </Wrapper>
  ),
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    const commitElements = canvas.getAllByTestId('commit-row-item')

    expect(commitElements).toHaveLength(10)

    const firstCommitElement = commitElements[0]!
    const sixthCommitElement = commitElements[5]!

    await step('top level element is focusable', async () => {
      await userEvent.click(firstCommitElement)
      expect(document.activeElement).toBe(firstCommitElement)
    })

    await step('tabbing through the top level element goes to the expected elements', async () => {
      await userEvent.click(firstCommitElement)
      expect(document.activeElement).toBe(firstCommitElement)
      await userEvent.tab()
      expect(document.activeElement).toHaveAttribute('data-testid', 'commit-row-show-description-button')
      await userEvent.tab()
      expect(document.activeElement).toHaveAttribute('data-testid', 'avatar-icon-link')
      await userEvent.tab()
      expect(document.activeElement).toHaveAttribute('aria-label', 'commits by monalisa')
      await userEvent.tab()
      expect(document.activeElement).toHaveAttribute('data-testid', 'checks-status-badge-button')
      await userEvent.tab()
      expect(document.activeElement?.parentElement).toHaveAttribute('data-testid', 'list-view-item-metadata-item')
      await userEvent.tab()
      expect(document.activeElement).toHaveTextContent('052a205')
      await userEvent.tab()
      expect(document.activeElement).toHaveAccessibleName('Copy full SHA for 052a205')
      await userEvent.tab()
      expect(document.activeElement).toHaveAttribute('data-testid', 'commit-row-browse-repo')
      await userEvent.tab()
      expect(document.activeElement).toBe(sixthCommitElement)
      await userEvent.tab({shift: true})
      expect(document.activeElement).toHaveAttribute('data-testid', 'commit-row-browse-repo')
    })
  },
}

export const Default: Story = {
  args: {
    ...randomizedGroupsArgs,
  },
  render: (args: CommitsProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <Commits {...args} />
    </Wrapper>
  ),
}

export const KeyboardNavigationBetweenGroups: Story = {
  args: {
    ...defaultArgs,
  },
  render: (args: CommitsProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <Commits {...args} />
    </Wrapper>
  ),
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    const commitElements = canvas.getAllByTestId('commit-row-item')

    expect(commitElements).toHaveLength(10)

    const firstCommitElement = commitElements[0]!
    const fifthCommitElement = commitElements[4]!
    const sixthCommitElement = commitElements[5]!

    await step('top level element is focusable', async () => {
      await userEvent.click(firstCommitElement)
      expect(document.activeElement).toBe(firstCommitElement)
    })

    await step('can navigate through commits with arrow keys', async () => {
      await userEvent.keyboard('{ArrowDown}')
      await userEvent.keyboard('{ArrowDown}')
      await userEvent.keyboard('{ArrowDown}')
      await userEvent.keyboard('{ArrowDown}')
      expect(fifthCommitElement).toHaveFocus()
    })

    await step('can navigate between commit groups with arrow keys', async () => {
      expect(fifthCommitElement).toHaveFocus()
      await userEvent.keyboard('{ArrowDown}')
      expect(sixthCommitElement).toHaveFocus()
    })

    await step('can navigate between commit groups with arrow keys', async () => {
      await userEvent.keyboard('{ArrowUp}')
      expect(fifthCommitElement).toHaveFocus()
    })

    await step('can navigate between commit groups with j and k', async () => {
      await userEvent.keyboard('j')
      expect(sixthCommitElement).toHaveFocus()
      await userEvent.keyboard('k')
      expect(fifthCommitElement).toHaveFocus()
    })
  },
}
