import {render, screen} from '@testing-library/react'
import {BlockedSection as TestComponent} from '../BlockedSection'
import type {BlockedSectionProps} from '../BlockedSection'
import {mergeBoxMockData, mockMergeRequirementCondition} from '../../../test-utils/mocks/json-api-response.mock'
import {
  getFailingMergeConditionsWithoutRulesCondition,
  getFailingRulesConditions,
} from '../../../helpers/json-api-helpers'
import type {PullRequestMergeRequirementsPayload} from '../../../page-data/payloads/merge-box'

const defaultProps: BlockedSectionProps = {
  isDraft: false,
  mergeRequirementsState: 'MERGEABLE',
  failingMergeConditionsWithoutRulesCondition: [],
  failingRulesConditions: [],
}

describe('Blocked section', () => {
  test('it does not render if the merge state status is mergeable', async () => {
    const {container} = render(<TestComponent {...defaultProps} />)

    expect(container).toBeEmptyDOMElement()
  })

  describe('enforcing repo rules', () => {
    const MissingApprovingReview = mockMergeRequirementCondition.PULL_REQUEST_RULES({
      result: 'FAILED',
      message: 'At least one approving review is required by reviewers with write access.',
    })

    const mergeRequirements = {
      state: 'UNMERGEABLE' as PullRequestMergeRequirementsPayload['state'],
      conditions: [
        mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({
          result: 'FAILED',
          message: 'Pull request cannot be merged because repository is not in a writable state.',
        }),
        mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({
          result: 'FAILED',
          message: 'Pull request cannot be merged because it has a merge conflict.',
        }),
      ],
    }

    test('if the merge state status is blocked due to repo rules, it renders the reasons', async () => {
      const props: BlockedSectionProps = {
        ...defaultProps,
        mergeRequirementsState: mergeRequirements.state,
        failingRulesConditions: [
          mockMergeRequirementCondition.PULL_REQUEST_RULES({
            result: 'FAILED',
            ruleRollups: [
              {
                ruleType: 'PULL_REQUEST',
                displayName: 'Require a pull request before merging',
                message: `${MissingApprovingReview.message}`,
                result: 'FAILED',
                bypassable: false,
                metadata: {
                  requiredReviewers: 0,
                  requiresCodeowners: false,
                  failureReasons: [],
                },
              },
            ],
          }),
        ],
        failingMergeConditionsWithoutRulesCondition: [],
      }
      render(<TestComponent {...props} />)

      expect(screen.getByText('Merging is blocked')).toBeInTheDocument()
      expect(screen.getByText(MissingApprovingReview.message!)).toBeInTheDocument()
    })
  })

  test('it does not show merge blocking reasons related to required status checks that are failing', () => {
    const {mergeRequirements} = mergeBoxMockData({mergeRequirementsKind: 'checksFailing'})
    const props = {
      ...defaultProps,
      mergeRequirementsState: mergeRequirements!.state,
      failingRulesConditions: getFailingRulesConditions(mergeRequirements),
      failingMergeConditionsWithoutRulesConditions: getFailingMergeConditionsWithoutRulesCondition(mergeRequirements),
    }

    render(<TestComponent {...props} />)

    expect(screen.queryByText('2 of 3 required status checks are failing.')).not.toBeInTheDocument()
  })

  test('it does not show merge blocking reasons related to status checks that are still pending', () => {
    const {mergeRequirements} = mergeBoxMockData({mergeRequirementsKind: 'checksPending'})
    const props = {
      ...defaultProps,
      mergeRequirementsState: mergeRequirements!.state,
      failingRulesConditions: getFailingRulesConditions(mergeRequirements),
      failingMergeConditionsWithoutRulesConditions: getFailingMergeConditionsWithoutRulesCondition(mergeRequirements),
    }

    render(<TestComponent {...props} />)

    expect(screen.queryByText('2 of 3 required status checks have not succeeded: 2 expected')).not.toBeInTheDocument()
  })

  test('it does not show draft mode state message when pull request is still in draft mode.', () => {
    const {mergeRequirements} = mergeBoxMockData({mergeRequirementsKind: 'nonActionableFailure'})
    const props = {
      ...defaultProps,
      mergeRequirementsState: mergeRequirements!.state,
      failingRulesConditions: getFailingRulesConditions(mergeRequirements),
      failingMergeConditionsWithoutRulesConditions: getFailingMergeConditionsWithoutRulesCondition(mergeRequirements),
    }

    render(<TestComponent {...props} />)

    expect(
      screen.queryByText('Pull request must be open and not in draft mode in order to be merged'),
    ).not.toBeInTheDocument()
  })

  test('it does not show unwritable state message when repository is not in a writable state.', () => {
    const {mergeRequirements} = mergeBoxMockData({mergeRequirementsKind: 'repoUnwritableState'})
    const props = {
      ...defaultProps,
      mergeRequirementsState: mergeRequirements!.state,
      failingRulesConditions: getFailingRulesConditions(mergeRequirements),
      failingMergeConditionsWithoutRulesConditions: getFailingMergeConditionsWithoutRulesCondition(mergeRequirements),
    }

    render(<TestComponent {...props} />)

    expect(
      screen.queryByText('Pull request cannot be merged because repository is not in a writable state.'),
    ).not.toBeInTheDocument()
  })

  test('it does not show expected required status checks if there are any', () => {
    const {mergeRequirements} = mergeBoxMockData({mergeRequirementsKind: 'requiredStatusChecksExpected'})
    const props = {
      ...defaultProps,
      mergeRequirementsState: mergeRequirements!.state,
      failingRulesConditions: getFailingRulesConditions(mergeRequirements),
      failingMergeConditionsWithoutRulesConditions: getFailingMergeConditionsWithoutRulesCondition(mergeRequirements),
    }

    render(<TestComponent {...props} />)

    expect(screen.queryByText('Required status check "build" is expected.')).not.toBeInTheDocument()
  })

  test('it does not show that a user is unable to merge due to push access rights', () => {
    const {mergeRequirements} = mergeBoxMockData({mergeRequirementsKind: 'userRequiresPushAccessToMerge'})
    const props = {
      ...defaultProps,
      mergeRequirementsState: mergeRequirements!.state,
      failingRulesConditions: getFailingRulesConditions(mergeRequirements),
      failingMergeConditionsWithoutRulesConditions: getFailingMergeConditionsWithoutRulesCondition(mergeRequirements),
    }

    render(<TestComponent {...props} />)

    expect(screen.queryByText('User is unable to merge this pull request.')).not.toBeInTheDocument()
  })
})
