import type {Meta, StoryObj} from '@storybook/react'
import {createRef} from 'react'
import {expect} from '@storybook/jest'
import {within} from '@storybook/test'

import {MergeStatusButton} from './MergeStatusButton'
import {mergeBoxMockData} from '../test-utils/mocks/json-api-response.mock'

const defaultProps = {
  mergeStatusButtonRef: createRef<HTMLButtonElement>(),
  toggleMergeabilitySidesheet: () => {},
}

const disableArg = {
  table: {
    disable: true,
  },
}

const meta = {
  title: 'Pull Requests/mergebox/MergeStatusButton',
  component: MergeStatusButton,
  argTypes: {
    pullRequest: disableArg,
    mergeRequirements: disableArg,
    mergeStatusButtonRef: disableArg,
    toggleMergeabilitySidesheet: disableArg,
  },
} satisfies Meta<typeof MergeStatusButton>

export default meta

type Story = StoryObj<typeof MergeStatusButton>

export const Mergeable: Story = {
  render: () => <MergeStatusButton {...mergeBoxMockData({mergeRequirementsKind: 'mergeable'})} {...defaultProps} />,
  play: ({canvasElement, step}) => {
    step('Shows correct info"', () => {
      expect(within(canvasElement).getByText('Merge pull request')).toBeInTheDocument()
    })
  },
}

export const ChecksPending: Story = {
  render: () => <MergeStatusButton {...mergeBoxMockData({mergeRequirementsKind: 'checksPending'})} {...defaultProps} />,
  play: ({canvasElement, step}) => {
    step('Shows correct info"', () => {
      expect(within(canvasElement).getByText('Checks pending')).toBeInTheDocument()
    })
  },
}

export const ChecksFailing: Story = {
  render: () => <MergeStatusButton {...mergeBoxMockData({mergeRequirementsKind: 'checksFailing'})} {...defaultProps} />,
  play: ({canvasElement, step}) => {
    step('Shows correct info"', () => {
      expect(within(canvasElement).getByText('Checks failing')).toBeInTheDocument()
    })
  },
}

export const DraftReadyForReview: Story = {
  render: () => (
    <MergeStatusButton
      {...mergeBoxMockData({pullRequestKind: 'draft', mergeRequirementsKind: 'draftReadyForReview'})}
      {...defaultProps}
    />
  ),
  play: ({canvasElement, step}) => {
    step('Shows correct info"', () => {
      expect(within(canvasElement).getByText('Draft')).toBeInTheDocument()
    })
  },
}

export const DraftAndMergeable: Story = {
  render: () => (
    <MergeStatusButton
      {...mergeBoxMockData({pullRequestKind: 'draft', mergeRequirementsKind: 'mergeable'})}
      {...defaultProps}
    />
  ),
  play: ({canvasElement, step}) => {
    step('Shows correct info"', () => {
      expect(within(canvasElement).getByText('Draft')).toBeInTheDocument()
    })
  },
}

export const AwaitingReview: Story = {
  render: () => (
    <MergeStatusButton {...mergeBoxMockData({mergeRequirementsKind: 'draftReadyForReview'})} {...defaultProps} />
  ),
  play: ({canvasElement, step}) => {
    step('Shows correct info"', () => {
      expect(within(canvasElement).getByText('Awaiting reviews')).toBeInTheDocument()
    })
  },
}

export const ChangesRequested: Story = {
  render: () => (
    <MergeStatusButton {...mergeBoxMockData({mergeRequirementsKind: 'changesRequested'})} {...defaultProps} />
  ),
  play: ({canvasElement, step}) => {
    step('Shows correct info"', () => {
      expect(within(canvasElement).getByText('Changes requested')).toBeInTheDocument()
    })
  },
}

export const InMergeQueue: Story = {
  render: () => (
    <MergeStatusButton
      {...mergeBoxMockData({pullRequestKind: 'isInMergeQueue', mergeRequirementsKind: 'changesRequested'})}
      {...defaultProps}
    />
  ),
  play: ({canvasElement, step}) => {
    step('Shows correct info"', () => {
      expect(within(canvasElement).getByText('Queued')).toBeInTheDocument()
    })
  },
}

export const MergeConflicts: Story = {
  render: () => (
    <MergeStatusButton {...mergeBoxMockData({mergeRequirementsKind: 'mergeConflicts'})} {...defaultProps} />
  ),
  play: ({canvasElement, step}) => {
    step('Shows correct info"', () => {
      expect(within(canvasElement).getByText('Merge conflicts')).toBeInTheDocument()
    })
  },
}

export const Unknown: Story = {
  render: () => (
    <MergeStatusButton {...mergeBoxMockData({mergeRequirementsKind: 'unknownNoConflicts'})} {...defaultProps} />
  ),
  play: ({canvasElement, step}) => {
    step('Shows correct info"', () => {
      expect(within(canvasElement).getByText('Unknown')).toBeInTheDocument()
    })
  },
}

export const UnableToMerge: Story = {
  render: () => <MergeStatusButton {...mergeBoxMockData({mergeRequirementsKind: 'unableToMerge'})} {...defaultProps} />,
  play: ({canvasElement, step}) => {
    step('Shows correct info"', () => {
      expect(within(canvasElement).getByText('Unable to merge')).toBeInTheDocument()
    })
  },
}
