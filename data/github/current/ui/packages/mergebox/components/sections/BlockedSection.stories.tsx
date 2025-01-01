import type {Meta, StoryObj} from '@storybook/react'
import {MemoryRouter} from 'react-router-dom'
import {BlockedSection, type BlockedSectionProps} from './BlockedSection'
import {getRenderWarnings} from '../../test-utils/use-render-warnings'
import {getFailingMergeConditionsWithoutRulesCondition, getFailingRulesConditions} from '../../helpers/json-api-helpers'
import {mergeBoxMockData} from '../../test-utils/mocks/json-api-response.mock'

const BlockedSectionStoryWrapper = (
  props: BlockedSectionProps & {mergeabilityState: PullRequestMergeRequirementsState; failureReasons: string[]},
) => <BlockedSection {...props} />

type PullRequestMergeRequirementsState = 'UNMERGEABLE' | 'MERGEABLE' | 'UNKNOWN'

type Story = StoryObj<typeof BlockedSectionStoryWrapper>

const meta = {
  title: 'Pull Requests/mergebox/BlockedSection',
  parameters: {
    controls: {expanded: false},
  },
  decorators: [
    Story => (
      <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
        <div style={{maxWidth: '935px'}}>
          <Story />
        </div>
      </MemoryRouter>
    ),
  ],
} satisfies Meta<typeof BlockedSection>

const PRMergeStateConditions = ['PULL_REQUEST_RULES', 'PULL_REQUEST_MERGE_CONFLICT_STATE']

export const Default: Story = {
  args: {
    isDraft: false,
    mergeRequirementsState: 'UNMERGEABLE',
    failureReasons: PRMergeStateConditions,
  },
  argTypes: {
    mergeRequirementsState: {
      options: ['UNMERGEABLE', 'MERGEABLE', 'UNKNOWN'],
      control: {
        type: 'inline-radio',
      },
    },
    failureReasons: {
      options: PRMergeStateConditions,
      control: {
        type: 'check',
      },
    },
  },
  render: function Component(args) {
    const {failureReasons, mergeRequirementsState, isDraft} = args
    const {warnIf, RenderWarnings} = getRenderWarnings()

    warnIf(isDraft, 'BlockedSection does not render for draft PRs')
    warnIf(mergeRequirementsState !== 'UNMERGEABLE', `BlockedSection does not render for ${mergeRequirementsState} PRs`)

    const {mergeRequirements: reqs} = mergeBoxMockData({
      mergeRequirementsKind: 'failingRulesAndMergeConflictState',
    })

    const mergeRequirements = {
      ...reqs!,
      conditions: reqs!.conditions.filter(condition => failureReasons.includes(condition.type)),
    }

    const failingMergeConditionsWithoutRulesCondition =
      getFailingMergeConditionsWithoutRulesCondition(mergeRequirements)

    const failingRulesConditions = getFailingRulesConditions(mergeRequirements)

    return (
      <>
        <RenderWarnings />
        <BlockedSectionStoryWrapper
          {...args}
          isDraft={isDraft}
          mergeRequirementsState={mergeRequirementsState}
          failingMergeConditionsWithoutRulesCondition={failingMergeConditionsWithoutRulesCondition}
          failingRulesConditions={failingRulesConditions}
        />
      </>
    )
  },
}

export default meta
