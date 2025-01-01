import type {Meta} from '@storybook/react'
import {noop} from '@github-ui/noop'
import type {PullRequestPickerBaseProps} from './TSQPullRequestAndBranchPicker'
import {PullRequestAndBranchPickerBase} from './TSQPullRequestAndBranchPicker'
import type {BranchPickerData, PullRequestPickerData} from '../types'
import {buildFoundBranch, buildFoundPullRequest} from '../test-utils/mock-data'

const pullRequests: PullRequestPickerData[] = [
  buildFoundPullRequest({
    type: 'pull_request',
    title: 'Some PR Title',
    number: 123,
    draft: false,
    merged: false,
    state: 'OPEN',
  }),
  buildFoundPullRequest({
    type: 'pull_request',
    title: 'Other PR Title',
    number: 456,
    draft: false,
    merged: false,
    state: 'CLOSED',
  }),
  buildFoundPullRequest({
    type: 'pull_request',
    title: 'Draft PR Title',
    number: 789,
    draft: true,
    merged: false,
    state: 'OPEN',
  }),
  buildFoundPullRequest({
    type: 'pull_request',
    title: 'Merged PR Title',
    number: 1011,
    draft: false,
    merged: true,
    state: 'CLOSED',
  }),
]

const branches: BranchPickerData[] = [
  buildFoundBranch({type: 'branch', name: 'branch1'}),
  buildFoundBranch({type: 'branch', name: 'branch2'}),
]

const meta = {
  title: 'CodeScanningDevelopmentSection/TSQPullRequestAndBranchPicker',
  component: PullRequestAndBranchPickerBase,
} satisfies Meta<PullRequestPickerBaseProps>

export default meta

const args = {
  pullRequestItems: pullRequests,
  branchItems: branches,
  initialSelectedBranches: [],
  initialSelectedPullRequests: [],
  onFilter: noop,
  onSelectionChange: noop,
  shortcutsEnabled: true,
  searchError: null,
  mutationError: null,
} satisfies PullRequestPickerBaseProps

function buildManyFoundBranches(count: number): BranchPickerData[] {
  return [...Array(count)].map((_, index) => {
    return buildFoundBranch({type: 'branch', name: `branch${index + 1}`})
  })
}

function buildManyFoundPullRequests(count: number): PullRequestPickerData[] {
  return [...Array(count)].map((_, index) => {
    return buildFoundPullRequest({
      type: 'pull_request',
      title: `PR Title ${index + 1}`,
      number: index + 1,
      draft: false,
      merged: false,
      state: 'OPEN',
    })
  })
}

export const Example = {args}

export const WithSelection = {
  args: {...args, initialSelectedPullRequests: [pullRequests[1]]},
}

export const WithManyResults = {
  args: {...args, pullRequestItems: buildManyFoundPullRequests(20), branchItems: buildManyFoundBranches(20)},
}

export const WithManySelected = {
  args: {
    ...args,
    pullRequestItems: [...buildManyFoundPullRequests(5)],
    branchItems: [...buildManyFoundBranches(5)],
    initialSelectedPullRequests: [...buildManyFoundPullRequests(5).slice(0, 2)],
    initialSelectedBranches: [...buildManyFoundBranches(5).slice(0, 2)],
  },
}
