import {render, screen} from '@testing-library/react'
import {BlockedSection as TestComponent} from '../BlockedSection'
import type {BlockedSectionProps} from '../BlockedSection'
import {mergeBoxMockData, mockMergeRequirementCondition} from '../../../test-utils/mocks/json-api-response.mock'
import {getFailingGenericMergeConditions, getFailingRulesConditions} from '../../../helpers/json-api-helpers'
import {BlockedSectionStatus} from '../../../helpers/merge-box-status-calculator/blocked-section-status'

const defaultProps: BlockedSectionProps = {
  failingConditionsAndRules: [],
}

describe('Blocked section', () => {
  describe('enforcing repo rules', () => {
    const MissingApprovingReview = mockMergeRequirementCondition.PULL_REQUEST_RULES({
      result: 'FAILED',
      message: 'At least one approving review is required by reviewers with write access.',
    })

    test('if the merge state status is blocked due to repo rules, it renders the reasons', async () => {
      const {pullRequest, mergeRequirements} = mergeBoxMockData({
        pullRequestKind: 'default',
        mergeRequirementsKind: 'failingRulesAndMergeConflictState',
      })
      const blockedSectionStatus = new BlockedSectionStatus(pullRequest, mergeRequirements, undefined)
      const props = {
        ...defaultProps,
        failingConditionsAndRules: blockedSectionStatus.failingConditionsAndRules,
      }
      render(<TestComponent {...props} />)

      expect(screen.getByText('Merging is blocked')).toBeInTheDocument()
      expect(screen.getByText(MissingApprovingReview.message!, {exact: false})).toBeInTheDocument()
    })
  })

  describe('enforcing sub conditiions - PULL_REQUEST_USER_STATE', () => {
    test('if the merge state status is blocked due to failing sub conditions, it renders the reasons', async () => {
      const {pullRequest, mergeRequirements} = mergeBoxMockData({
        pullRequestKind: 'default',
        mergeRequirementsKind: 'userRequiresVerifiedEmail',
      })

      const blockedSectionStatus = new BlockedSectionStatus(pullRequest, mergeRequirements, undefined)
      const props = {
        ...defaultProps,
        failingConditionsAndRules: blockedSectionStatus.failingConditionsAndRules,
      }
      render(<TestComponent {...props} />)

      expect(screen.getByText('Merging is blocked')).toBeInTheDocument()
      expect(
        screen.getByText('Your email address must be verified before merging.', {exact: false}),
      ).toBeInTheDocument()
    })
  })

  test('it does not show merge blocking reasons related to required status checks that are failing', () => {
    const {mergeRequirements} = mergeBoxMockData({mergeRequirementsKind: 'checksFailing'})
    const props = {
      ...defaultProps,
      failingRulesConditions: getFailingRulesConditions(mergeRequirements),
      failingGenericMergeConditions: getFailingGenericMergeConditions(mergeRequirements),
    }

    render(<TestComponent {...props} />)

    expect(screen.queryByText('2 of 3 required status checks are failing.')).not.toBeInTheDocument()
  })

  test('it does not show merge blocking reasons related to status checks that are still pending', () => {
    const {mergeRequirements} = mergeBoxMockData({mergeRequirementsKind: 'checksPending'})
    const props = {
      ...defaultProps,
      failingRulesConditions: getFailingRulesConditions(mergeRequirements),
      failingGenericMergeConditions: getFailingGenericMergeConditions(mergeRequirements),
    }

    render(<TestComponent {...props} />)

    expect(screen.queryByText('2 of 3 required status checks have not succeeded: 2 expected')).not.toBeInTheDocument()
  })

  test('it does not show draft mode state message when pull request is still in draft mode.', () => {
    const {mergeRequirements} = mergeBoxMockData({mergeRequirementsKind: 'nonActionableFailure'})
    const props = {
      ...defaultProps,
      failingRulesConditions: getFailingRulesConditions(mergeRequirements),
      failingGenericMergeConditions: getFailingGenericMergeConditions(mergeRequirements),
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
      failingRulesConditions: getFailingRulesConditions(mergeRequirements),
      failingGenericMergeConditions: getFailingGenericMergeConditions(mergeRequirements),
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
      failingRulesConditions: getFailingRulesConditions(mergeRequirements),
      failingGenericMergeConditions: getFailingGenericMergeConditions(mergeRequirements),
    }

    render(<TestComponent {...props} />)

    expect(screen.queryByText('Required status check "build" is expected.')).not.toBeInTheDocument()
  })

  test('it does not show that a user is unable to merge due to push access rights', () => {
    const {mergeRequirements} = mergeBoxMockData({mergeRequirementsKind: 'userRequiresPushAccessToMerge'})
    const props = {
      ...defaultProps,
      failingRulesConditions: getFailingRulesConditions(mergeRequirements),
      failingGenericMergeConditions: getFailingGenericMergeConditions(mergeRequirements),
    }

    render(<TestComponent {...props} />)

    expect(screen.queryByText('User is unable to merge this pull request.')).not.toBeInTheDocument()
  })
})
