import type {MergeBoxUserPreferences} from '../../page-data/payloads/merge-box'
import type {StatusCheck, StatusCheckState} from '../../page-data/payloads/status-checks'
import {StatusCheckGenerator} from '../../test-utils/object-generators/status-check'
import {compareChecks, countChecksByGroup, groupChecks} from '../status-check-helpers'

describe('groupChecks function', () => {
  test('groups checks with the provided mapping', () => {
    const grouping = {
      SUCCESS: ['SUCCESS', 'SKIPPED'],
      FAILURE: ['FAILURE', 'STALE', 'CANCELLED'],
    }

    const checks = ['SUCCESS', 'SUCCESS', 'SKIPPED', 'FAILURE', 'STALE', 'FAILURE', 'CANCELLED', 'STALE']
    const getState = (state: string) => state

    const groups = groupChecks(checks, grouping, getState)
    expect(Object.keys(groups).length).toBe(2)
    expect(groups['SUCCESS']?.length).toBe(3)
    expect(groups['FAILURE']?.length).toBe(5)
    expect(groups['SUCCESS']?.filter(item => item === 'SUCCESS').length).toBe(2)
    expect(groups['SUCCESS']?.filter(item => item === 'SKIPPED').length).toBe(1)
    expect(groups['FAILURE']?.filter(item => item === 'FAILURE').length).toBe(2)
    expect(groups['FAILURE']?.filter(item => item === 'CANCELLED').length).toBe(1)
    expect(groups['FAILURE']?.filter(item => item === 'STALE').length).toBe(2)
  })

  test('group order is determined by the provided mapping', () => {
    const grouping = {
      SUCCESS: ['SUCCESS', 'SKIPPED'],
      FAILURE: ['FAILURE', 'STALE', 'CANCELLED'],
    }

    const checks = ['FAILURE', 'STALE', 'FAILURE', 'CANCELLED', 'STALE', 'SUCCESS', 'SUCCESS', 'SKIPPED']
    const getState = (state: string) => state

    const groups = groupChecks(checks, grouping, getState)
    expect(Object.keys(groups).length).toBe(2)
    expect(Object.keys(groups)[0]).toBe('SUCCESS')
    expect(Object.keys(groups)[1]).toBe('FAILURE')
  })

  test('places all checks in an "ALL" group when user preference is ungrouped', () => {
    const grouping = {
      SUCCESS: ['SUCCESS', 'SKIPPED'],
      FAILURE: ['FAILURE', 'STALE', 'CANCELLED'],
    }

    const checks = ['SUCCESS', 'FAILURE', 'SKIPPED', 'STALE']
    const getState = (state: string) => state
    const mergeBoxUserPreferences: MergeBoxUserPreferences = {statusChecksGrouping: 'ungrouped'}

    const groups = groupChecks(checks, grouping, getState, mergeBoxUserPreferences)
    expect(Object.keys(groups).length).toBe(1)
    expect(Object.keys(groups)[0]).toBe('ALL')
    expect(groups['ALL']?.length).toBe(4)
    expect(groups['ALL']).toEqual(checks)
  })
})

describe('compareChecks function', () => {
  test('sorts checks by displayName naturally, not lexigraphically', () => {
    const checks = [
      StatusCheckGenerator({state: 'IN_PROGRESS', displayName: 'github-ruby-next-34 (push)'}),
      StatusCheckGenerator({state: 'IN_PROGRESS', displayName: 'github-ruby-next-4 (push)'}),
      StatusCheckGenerator({state: 'IN_PROGRESS', displayName: 'github-ruby-next-35 (push)'}),
      StatusCheckGenerator({state: 'IN_PROGRESS', displayName: 'github-ruby-next-6 (push)'}),
      StatusCheckGenerator({state: 'IN_PROGRESS', displayName: 'github-ruby-next-5 (push)'}),
    ]

    // sort and extract only the name for the test
    const sortedChecks = checks.sort(compareChecks).map((c: StatusCheck) => c.displayName)

    expect(sortedChecks.length).toBe(5)
    expect(sortedChecks[0]).toBe('github-ruby-next-4 (push)')
    expect(sortedChecks[1]).toBe('github-ruby-next-5 (push)')
    expect(sortedChecks[2]).toBe('github-ruby-next-6 (push)')
    expect(sortedChecks[3]).toBe('github-ruby-next-34 (push)')
    expect(sortedChecks[4]).toBe('github-ruby-next-35 (push)')
  })

  test('returns total count of checks when user preference is ungrouped', () => {
    const checks = [
      {state: 'SUCCESS' as StatusCheckState, count: 3},
      {state: 'FAILURE' as StatusCheckState, count: 2},
      {state: 'PENDING' as StatusCheckState, count: 5},
    ]

    const mergeBoxUserPreferences: MergeBoxUserPreferences = {statusChecksGrouping: 'ungrouped'}

    const result = countChecksByGroup(checks, {}, mergeBoxUserPreferences)

    expect(Object.keys(result).length).toBe(1)
    expect(Object.keys(result)[0]).toBe('ALL')
    expect(result['ALL']).toBe(10)
  })
})
