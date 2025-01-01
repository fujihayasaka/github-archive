import type {Meta, StoryObj} from '@storybook/react'
import {MemoryRouter} from 'react-router-dom'
import {BlockedSection, type BlockedSectionProps} from './BlockedSection'
import {getRenderWarnings} from '../../test-utils/use-render-warnings'
import {
  getFailingConditionsWithSubConditions,
  getFailingGenericMergeConditions,
  getFailingRulesConditions,
} from '../../helpers/json-api-helpers'
import {mergeBoxMockData, type MergeRequirementsKind} from '../../test-utils/mocks/json-api-response.mock'

const BlockedSectionStoryWrapper = (
  props: BlockedSectionProps & {
    failureReasons: string[]
    mergeRequirementsKind: MergeRequirementsKind
  },
) => <BlockedSection {...props} />

type Story = StoryObj<typeof BlockedSectionStoryWrapper>

const meta = {
  title: 'Pull Requests/Merge Box/BlockedSection',
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

const PRMergeStateConditions = ['PULL_REQUEST_RULES', 'PULL_REQUEST_MERGE_CONFLICT_STATE', 'PULL_REQUEST_USER_STATE']

export const Default: Story = {
  parameters: {
    a11y: {
      config: {
        rules: [
          {
            id: 'link-in-text-block',
            enabled: false,
          },
        ],
      },
    },
  },
  args: {
    failureReasons: PRMergeStateConditions,
    mergeRequirementsKind: 'failingRulesAndMergeConflictState',
  },
  argTypes: {
    mergeRequirementsKind: {
      options: ['failingRulesAndMergeConflictState', 'userRequiresVerifiedEmail', 'failingAuthRule'],
      control: {
        type: 'inline-radio',
      },
    },
  },
  render: function Component(args) {
    const {failureReasons, mergeRequirementsKind} = args
    const {RenderWarnings} = getRenderWarnings()

    const {mergeRequirements: reqs} = mergeBoxMockData({mergeRequirementsKind})

    const mergeRequirements = {
      ...reqs!,
      conditions: reqs!.conditions.filter(condition => failureReasons.includes(condition.type)),
    }

    const failingConditionsWithSubConditions = getFailingConditionsWithSubConditions(mergeRequirements)
    const failingGenericMergeConditions = getFailingGenericMergeConditions(mergeRequirements)
    const failingRulesConditions = getFailingRulesConditions(mergeRequirements)
    const failingConditionsAndRules = [
      ...failingConditionsWithSubConditions,
      ...failingGenericMergeConditions,
      ...failingRulesConditions,
    ]
    return (
      <>
        <RenderWarnings />
        <BlockedSectionStoryWrapper {...args} failingConditionsAndRules={failingConditionsAndRules} />
      </>
    )
  },
}

export default meta
