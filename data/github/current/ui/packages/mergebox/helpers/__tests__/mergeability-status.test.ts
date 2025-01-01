import {
  allRequiredChecksSuccessful,
  checksSectionNoChecksState,
  checksSectionNonRequiredChecksFailingState,
  checksSectionNonRequiredChecksPassingSkippedNeutralState,
  checksSectionNonRequiredChecksPassingState,
  checksSectionPendingAndWaitingState,
  checksSectionRequiredChecksFailingState,
  checksSectionRequiredChecksPassingState,
  checksSectionRequiredChecksPassingStateNonRequiredFailing,
} from '../../test-utils/mocks/checks-section-mocks'
import {mergeBoxMockData} from '../../test-utils/mocks/json-api-response.mock'
import {mergeabilityStatus, Status} from '../mergeability-status'

describe('mergeabilityStatus', () => {
  test('it returns the MERGED status when the pull request is merged', () => {
    const data = mergeBoxMockData({pullRequestKind: 'mergedWithUserActionsAllowed'})
    const status = mergeabilityStatus(data)
    expect(status).toEqual(Status.Merged)
  })

  test('it returns the CLOSED status when the pull request is closed', () => {
    const status = mergeabilityStatus(mergeBoxMockData({pullRequestKind: 'closedWithUserActionsAllowed'}))
    expect(status).toEqual(Status.Closed)
  })

  test('it returns the NON-ACTIONABLE FAILURE status when the pull request has failures that a user cannot resolve', () => {
    const status = mergeabilityStatus(mergeBoxMockData({mergeRequirementsKind: 'nonActionableFailure'}))
    expect(status).toEqual(Status.NonactionableFailure)
  })

  test('it returns the IN MERGE QUEUE status when the pull request is in the merge queue', () => {
    const status = mergeabilityStatus(mergeBoxMockData({pullRequestKind: 'isInMergeQueue'}))
    expect(status).toEqual(Status.InMergeQueue)
  })

  test('it returns the DRAFT READY FOR REVIEW status when the pull request is ready for review', () => {
    const status = mergeabilityStatus(
      mergeBoxMockData({pullRequestKind: 'draft', mergeRequirementsKind: 'draftReadyForReview'}),
    )
    expect(status).toEqual(Status.DraftReadyForReview)
  })

  test('it returns the DRAFT status when the pull request is in draft and not ready for review', () => {
    const status = mergeabilityStatus({
      ...mergeBoxMockData({
        pullRequestKind: 'draft',
        mergeRequirementsKind: 'draftNotReadyForReview',
      }),
      statusChecksData: checksSectionRequiredChecksFailingState,
    })
    expect(status).toEqual(Status.DraftNotReadyForReview)
  })

  test('it returns the MERGEABLE status when the pull request merge requirements status is MERGEABLE', () => {
    const status = mergeabilityStatus(mergeBoxMockData({mergeRequirementsKind: 'mergeable'}))
    expect(status).toEqual(Status.Mergeable)
  })

  test('it returns the CHECKS PENDING status when the pull request merge requirements have checks pending', () => {
    const status = mergeabilityStatus({
      ...mergeBoxMockData({
        mergeRequirementsKind: 'checksPending',
      }),
      statusChecksData: checksSectionPendingAndWaitingState,
    })
    expect(status).toEqual(Status.ChecksPending)
  })

  test('it returns the CHECKS FAILING status when the pull request merge requirements have failed checks', () => {
    const status = mergeabilityStatus({
      ...mergeBoxMockData({
        mergeRequirementsKind: 'mergeableIfStatusesPass',
      }),
      statusChecksData: checksSectionRequiredChecksFailingState,
    })
    expect(status).toEqual(Status.ChecksFailing)
  })

  describe('NON-REQUIRED CHECKS UNSUCCESSFUL', () => {
    test('it returns the NON REQUIRED CHECKS UNSUCCESSFUL status when the pull request is MERGEABLE but there are non-required checks that are not successful', () => {
      const status = mergeabilityStatus({
        ...mergeBoxMockData({
          mergeRequirementsKind: 'mergeable',
        }),
        statusChecksData: checksSectionNonRequiredChecksFailingState,
      })
      expect(status).toEqual(Status.NonRequiredChecksUnsuccessful)
    })

    test('it returns the applicable failing status (not NON REQUIRED CHECKS UNSUCCESSFUL) when the pull request is UNMERGEABLE and all status checks, including non-required ones, are successful OR skipped OR neutral', () => {
      const status = mergeabilityStatus({
        ...mergeBoxMockData({
          mergeRequirementsKind: 'mergeConflicts',
        }),
        statusChecksData: checksSectionNonRequiredChecksFailingState,
      })
      expect(status).toEqual(Status.MergeConflicts)
    })

    test('it returns the NON REQUIRED CHECKS UNSUCCESSFUL status when the pull request is UNKNOWN and all status checks, including non-required ones, are successful OR skipped OR neutral', () => {
      const status = mergeabilityStatus({
        ...mergeBoxMockData({
          mergeRequirementsKind: 'unknownNoConflicts',
        }),
        statusChecksData: checksSectionNonRequiredChecksFailingState,
      })
      expect(status).toEqual(Status.NonRequiredChecksUnsuccessful)
    })

    test('it returns the MERGEABLE status when the pull request is MERGEABLE and all status checks, including non-required ones, are successful', () => {
      const status = mergeabilityStatus({
        ...mergeBoxMockData({
          mergeRequirementsKind: 'mergeable',
        }),
        statusChecksData: checksSectionNonRequiredChecksPassingState,
      })
      expect(status).toEqual(Status.Mergeable)
    })

    test('it returns the MERGEABLE status when the pull request is MERGEABLE and all status checks, including non-required ones, are successful OR skipped OR neutral', () => {
      const status = mergeabilityStatus({
        ...mergeBoxMockData({
          mergeRequirementsKind: 'mergeable',
        }),
        statusChecksData: checksSectionNonRequiredChecksPassingSkippedNeutralState,
      })
      expect(status).toEqual(Status.Mergeable)
    })
  })

  test('it returns the MERGEABLE status when the pull request is mergeableIfStatusesPass and all Required status checks  are successful OR skipped OR neutral', () => {
    const status = mergeabilityStatus({
      ...mergeBoxMockData({
        mergeRequirementsKind: 'mergeableIfStatusesPass',
      }),
      statusChecksData: checksSectionRequiredChecksPassingState,
    })
    expect(status).toEqual(Status.Mergeable)
  })

  test('it returns the NONREQUIREDCHECKUNSUCESSFUL status when the pull request is mergeableIfStatusesPass and all Required status checks are successful OR skipped OR neutral, but non required fail', () => {
    const status = mergeabilityStatus({
      ...mergeBoxMockData({
        mergeRequirementsKind: 'mergeableIfStatusesPass',
      }),
      statusChecksData: checksSectionRequiredChecksPassingStateNonRequiredFailing,
    })
    expect(status).toEqual(Status.NonRequiredChecksUnsuccessful)
  })

  test('it returns the MERGEABLE status when the pull request is mergeableIfStatusesPass and all Required and Non required status checks are successful OR skipped OR neutral', () => {
    const status = mergeabilityStatus({
      ...mergeBoxMockData({
        mergeRequirementsKind: 'mergeableIfStatusesPass',
      }),
      statusChecksData: allRequiredChecksSuccessful,
    })
    expect(status).toEqual(Status.Mergeable)
  })

  test('it returns the UNABLETOMERGE status when the pull request is mergeableIfStatusesPass and there are no checks data', () => {
    const status = mergeabilityStatus({
      ...mergeBoxMockData({
        mergeRequirementsKind: 'mergeableIfStatusesPass',
      }),
      statusChecksData: checksSectionNoChecksState,
    })
    expect(status).toEqual(Status.UnableToMerge)
  })

  test('it returns the UNABLETOMERGE status when the pull request if is no checks data', () => {
    const status = mergeabilityStatus({
      ...mergeBoxMockData({
        mergeRequirementsKind: 'mergeableIfStatusesPass',
      }),
      statusChecksData: undefined,
    })
    expect(status).toEqual(Status.UnableToMerge)
  })

  test('it returns the CHANGES REQUESTED status when the pull request merge requirements have requested changes', () => {
    const status = mergeabilityStatus(mergeBoxMockData({mergeRequirementsKind: 'changesRequested'}))
    expect(status).toEqual(Status.ChangesRequested)
  })

  test('it returns the UNKNOWN status when the pull request merge requirements have an unknown state and no conflicts', () => {
    const status = mergeabilityStatus(mergeBoxMockData({mergeRequirementsKind: 'unknownNoConflicts'}))
    expect(status).toEqual(Status.Unknown)
  })

  test('it returns the MERGE CONFLICT status when the pull request merge requirements has conflicts', () => {
    const status = mergeabilityStatus(mergeBoxMockData({mergeRequirementsKind: 'mergeConflicts'}))
    expect(status).toEqual(Status.MergeConflicts)
  })
})
