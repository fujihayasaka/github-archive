import type {Meta, StoryObj} from '@storybook/react'
import {getMockCommitsDropDownPageData} from '../test-utils/mock-data'
import {CommitsDropdown} from './CommitsDropdown'
import {noop} from '@github-ui/noop'
import {SelectedRefContext} from '../contexts/SelectedRefContext'
import {expect, userEvent, within} from '@storybook/test'
import {shouldInteractionPlay} from '@github-ui/storybook'

const defaultMockData = getMockCommitsDropDownPageData()
const commit2Oid = defaultMockData.commits.at(1)!.oid
const commit3Oid = defaultMockData.commits.at(2)!.oid

const meta = {
  title: 'Apps/React Shared/Pull Requests/CommitsDropdown',
  component: CommitsDropdown,
  argTypes: {
    baseRefOid: {table: {disable: true}},
    commits: {table: {disable: true}},
    lastReviewOid: {table: {disable: true}},
    onRangeUpdated: {table: {disable: true}},
  },
  decorators: [
    Story => (
      <SelectedRefContext.Provider value={{endOid: undefined, isSingleCommit: false, startOid: undefined}}>
        <Story />
      </SelectedRefContext.Provider>
    ),
  ],
  parameters: {
    a11y: {
      config: {
        rules: [
          {
            // Validation errors have animation that causes false-positive results for contrast check with ActionMenu and ActionMenuOverlay
            id: 'color-contrast',
            enabled: false,
          },
        ],
      },
    },
  },
} satisfies Meta<typeof CommitsDropdown>

export default meta

type Story = StoryObj<typeof CommitsDropdown>

export const Default: Story = {
  render: () => {
    return <CommitsDropdown {...defaultMockData} onRangeUpdated={noop} />
  },
}

export const CommitSelectorShowsOptionsToPickOneOrMoreCommits: Story = {
  render: () => {
    return (
      <CommitsDropdown
        baseRefOid={defaultMockData.baseRefOid}
        commits={[defaultMockData.commits[0]!]}
        onRangeUpdated={noop}
      />
    )
  },
  play: async ({canvasElement}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await userEvent.click(canvas.getByRole('button', {name: 'All changes'}))
    await userEvent.click(canvas.getByText('Specific commit…'))

    expect(canvas.getByText('Pick one or more commits')).toBeInTheDocument()
  },
}

export const ShowsChangesSinceLastReviewWhenLastReviewOidDoesNotMatchTheHeadOid: Story = {
  render: () => {
    return <CommitsDropdown {...defaultMockData} lastReviewOid={commit2Oid} onRangeUpdated={noop} />
  },
  play: async ({canvasElement}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await userEvent.click(canvas.getByRole('button', {name: 'All changes'}))

    expect(canvas.getByText('Changes since your last review')).toBeInTheDocument()
  },
}

export const DoesNotShowChangesSinceLastReviewWhenLastReviewOidIsNotDefined: Story = {
  render: () => {
    return <CommitsDropdown {...defaultMockData} lastReviewOid={undefined} onRangeUpdated={noop} />
  },
  play: async ({canvasElement}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await userEvent.click(canvas.getByRole('button', {name: 'All changes'}))

    expect(canvas.queryByText('Changes since your last review')).not.toBeInTheDocument()
  },
}

export const DoesNotShowChangesSinceLastReviewWhenLastReviewOidMatchesTheHeadOid: Story = {
  render: () => {
    return <CommitsDropdown {...defaultMockData} lastReviewOid={commit3Oid} onRangeUpdated={noop} />
  },
  play: async ({canvasElement}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await userEvent.click(canvas.getByRole('button', {name: 'All changes'}))

    expect(canvas.queryByText('Changes since your last review')).not.toBeInTheDocument()
  },
}
