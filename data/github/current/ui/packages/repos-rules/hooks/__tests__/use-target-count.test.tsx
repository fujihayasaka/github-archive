// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {act, renderHook} from '@testing-library/react'
import {useTargetCount} from '../use-target-count'
import {
  createPropertyCondition,
  createRefNameCondition,
  createRepoIdCondition,
  createRule,
  createRuleset,
} from '../../test-utils/mock-data'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, expectMockFetchCalledWith, mockFetch} from '@github-ui/mock-fetch'
import {Wrapper} from '@github-ui/react-core/test-utils'
import type React from 'react'
import type {SourceType} from '../../types/rules-types'
import type {Repository} from '@github-ui/current-repository'
import type {Organization} from '@github-ui/repos-types'

const samples = {
  repo: {
    id: 1,
    name: 'my-repo',
    ownerLogin: 'my-repo',
    defaultBranch: 'main',
    createdAt: '2021-01-01',
  },
  org: {
    id: 1,
    name: 'my-org',
    ownerLogin: 'my-org',
  },
}

const orgSource = {...samples.org, type: 'organization'}
const repoSource = {...samples.repo, type: 'repository'}

const getWrapper = ({isStafftools = false}: {isStafftools?: boolean}) => {
  const WrapperComponent: React.FC<{children: React.ReactNode}> = ({children}) => (
    <Wrapper
      appPayload={{
        ['is_stafftools']: isStafftools,
      }}
    >
      {children}
    </Wrapper>
  )
  WrapperComponent.displayName = 'CreatePreviewWrapper'
  return WrapperComponent
}

describe('useTargetCount', () => {
  it.each`
    level             | rulesetSource | condition                    | expectedUrl
    ${'organization'} | ${orgSource}  | ${createRefNameCondition()}  | ${'/organizations/my-org'}
    ${'organization'} | ${orgSource}  | ${createPropertyCondition()} | ${'/organizations/my-org'}
    ${'organization'} | ${orgSource}  | ${createRepoIdCondition()}   | ${'/organizations/my-org'}
    ${'repository'}   | ${repoSource} | ${createRefNameCondition()}  | ${'/my-repo/my-repo'}
    ${'repository'}   | ${repoSource} | ${createPropertyCondition()} | ${'/my-repo/my-repo'}
    ${'repository'}   | ${repoSource} | ${createRepoIdCondition()}   | ${'/my-repo/my-repo'}
    ${'repository'}   | ${orgSource}  | ${createRefNameCondition()}  | ${'/my-repo/my-repo'}
    ${'repository'}   | ${orgSource}  | ${createPropertyCondition()} | ${'/my-repo/my-repo'}
    ${'repository'}   | ${orgSource}  | ${createRepoIdCondition()}   | ${'/my-repo/my-repo'}
  `(
    'fetch a preview for a $condition.target $rulesetSource.type ruleset at $level',
    async ({level, rulesetSource, condition, expectedUrl}) => {
      const rulesets = [
        createRuleset({
          id: 1,
          rules: [createRule()],
          conditions: [condition],
          source: rulesetSource,
        }),
      ]

      const hookSource: Repository | Organization = level === 'organization' ? samples.org : samples.repo
      const {result} = renderHook(() => useTargetCount(hookSource, level as SourceType, rulesets), {
        wrapper: getWrapper({}),
      })

      await act(() =>
        mockFetch.resolvePendingRequest(`${expectedUrl}/settings/rules/deferred_target_counts`, {
          preview: [{rulesetId: 1, count: 15}],
        }),
      )

      expectMockFetchCalledTimes(`${expectedUrl}/settings/rules/deferred_target_counts`, 1)
      expectMockFetchCalledWith(`${expectedUrl}/settings/rules/deferred_target_counts`, {ruleset_ids: [1]}, 'equal')

      expect(result.current.rulesetPreviewCounts).toEqual({'1': 15})
      expect(result.current.rulesetPreviewSamples).toEqual({})
      expect(result.current.rulesetPreviewErrors).toEqual({})
    },
  )

  it('fetch preview for multiple repo name rulesets', async () => {
    const rulesets = [
      createRuleset({
        id: 1,
        rules: [createRule()],
        conditions: [createRefNameCondition(['m.+'], [])],
        source: orgSource,
      }),
      createRuleset({
        id: 2,
        rules: [createRule()],
        conditions: [createRefNameCondition(['n.+'], [])],
        source: orgSource,
      }),
      createRuleset({
        id: 3,
        rules: [createRule()],
        conditions: [createRefNameCondition(['n.+'], [])],
        source: orgSource,
      }),
    ]

    const {result} = renderHook(() => useTargetCount(samples.org, 'organization', rulesets, 3), {
      wrapper: getWrapper({}),
    })

    await act(() => {
      mockFetch.resolvePendingRequest('/organizations/my-org/settings/rules/deferred_target_counts', {
        preview: [
          {rulesetId: 1, count: 15, sampleTargetNames: ['smile-1', 'smile-2', 'smile-3']},
          {rulesetId: 2, count: 0, sampleTargetNames: []},
          {
            rulesetId: 3,
            errorMessage:
              'Unable to display affected targets due to a large number of repositories in this organization.',
          },
        ],
      })
    })

    expect(result.current.rulesetPreviewCounts).toEqual({
      '1': 15,
      '2': 0,
    })
    expect(result.current.rulesetPreviewSamples).toEqual({
      '1': ['smile-1', 'smile-2', 'smile-3'],
      '2': [],
    })
  })

  it('fetch multiple previews when number of property rulesets is bigger than the batch size', async () => {
    const rulesets = Array.from({length: 5}, (_, i) =>
      createRuleset({
        id: i + 1,
        rules: [createRule()],
        conditions: [createPropertyCondition()],
        source: orgSource,
      }),
    )

    const {result} = renderHook(() => useTargetCount(samples.org, 'organization', rulesets, 3), {
      wrapper: getWrapper({}),
    })

    await act(() => {
      mockFetch.resolvePendingRequest('/organizations/my-org/settings/rules/deferred_target_counts', {
        preview: [
          {rulesetId: 1, count: 10},
          {rulesetId: 2, count: 2},
          {rulesetId: 3, count: 30},
        ],
      })
    })
    await act(() => {
      mockFetch.resolvePendingRequest('/organizations/my-org/settings/rules/deferred_target_counts', {
        preview: [
          {rulesetId: 4, count: 0},
          {rulesetId: 5, count: 5},
        ],
      })
    })

    expect(result.current.rulesetPreviewCounts).toEqual({
      '1': 10,
      '2': 2,
      '3': 30,
      '4': 0,
      '5': 5,
    })
    expect(result.current.rulesetPreviewSamples).toEqual({})
  })

  it('fetch separate previews for property and repo name rulesets', async () => {
    const rulesets = [
      createRuleset({
        id: 1,
        rules: [createRule()],
        conditions: [createRefNameCondition(['m.+'], [])],
        source: orgSource,
      }),
      createRuleset({
        id: 2,
        rules: [createRule()],
        conditions: [createRefNameCondition(['n.+'], [])],
        source: orgSource,
      }),
      createRuleset({
        id: 3,
        rules: [createRule()],
        conditions: [createPropertyCondition()],
        source: orgSource,
      }),
    ]

    const {result} = renderHook(() => useTargetCount(samples.org, 'organization', rulesets), {
      wrapper: getWrapper({}),
    })

    expectMockFetchCalledWith(
      '/organizations/my-org/settings/rules/deferred_target_counts',
      {ruleset_ids: [1, 2]},
      'equal',
    )

    await act(() => {
      mockFetch.resolvePendingRequest('/organizations/my-org/settings/rules/deferred_target_counts', {
        preview: [
          {rulesetId: 1, count: 2, sampleTargetNames: ['smile-1', 'smile-2']},
          {rulesetId: 2, count: 0, sampleTargetNames: []},
        ],
      })
    })
    expectMockFetchCalledWith(
      '/organizations/my-org/settings/rules/deferred_target_counts',
      {ruleset_ids: [3]},
      'equal',
    )

    await act(() => {
      mockFetch.resolvePendingRequest('/organizations/my-org/settings/rules/deferred_target_counts', {
        preview: [{rulesetId: 3, count: 13}],
      })
    })

    expect(result.current.rulesetPreviewCounts).toEqual({
      '1': 2,
      '2': 0,
      '3': 13,
    })

    expect(result.current.rulesetPreviewSamples).toEqual({
      '1': ['smile-1', 'smile-2'],
      '2': [],
    })
  })

  it.each`
    level             | rulesetSource | expectedUrl
    ${'organization'} | ${orgSource}  | ${'/organizations/my-org'}
    ${'repository'}   | ${repoSource} | ${'/my-repo/my-repo'}
  `('does not update the preview when the fetch fails at $level level', async ({level, rulesetSource, expectedUrl}) => {
    const rulesets = [
      createRuleset({
        id: 3,
        rules: [createRule()],
        conditions: [createRefNameCondition()],
        source: rulesetSource,
      }),
    ]

    const hookSource: Repository | Organization = level === 'organization' ? samples.org : samples.repo
    const {result} = renderHook(() => useTargetCount(hookSource, level as SourceType, rulesets), {
      wrapper: getWrapper({}),
    })

    await act(() =>
      mockFetch.resolvePendingRequest(`${expectedUrl}/settings/rules/deferred_target_counts`, undefined, {
        ok: false,
      }),
    )

    expect(result.current.rulesetPreviewCounts).toEqual({})
    expect(result.current.rulesetPreviewSamples).toEqual({})
  })

  it.each`
    level             | rulesetSource | expectedUrl
    ${'organization'} | ${orgSource}  | ${'/organizations/my-org'}
    ${'repository'}   | ${repoSource} | ${'/my-repo/my-repo'}
  `('does not update the preview when the fetch fails at $level level', async ({level, rulesetSource, expectedUrl}) => {
    const rulesets = [
      createRuleset({
        id: 3,
        rules: [createRule()],
        conditions: [createPropertyCondition()],
        source: rulesetSource,
      }),
    ]

    const hookSource: Repository | Organization = level === 'organization' ? samples.org : samples.repo
    const {result} = renderHook(() => useTargetCount(hookSource, level as SourceType, rulesets), {
      wrapper: getWrapper({}),
    })

    await act(() =>
      mockFetch.rejectPendingRequest(`${expectedUrl}/settings/rules/deferred_target_counts`, 'Something went wrong'),
    )

    expect(result.current.rulesetPreviewCounts).toEqual({})
    expect(result.current.rulesetPreviewSamples).toEqual({})
  })

  it('fetch the target count for multiple ref_name ruleset at repo level', async () => {
    const rulesets = [
      createRuleset({
        id: 1,
        rules: [createRule()],
      }),
      createRuleset({
        id: 2,
        rules: [createRule()],
      }),
    ]

    const {result} = renderHook(() => useTargetCount(samples.repo, 'repository', rulesets), {
      wrapper: getWrapper({}),
    })

    await act(() =>
      mockFetch.resolvePendingRequest('/my-repo/my-repo/settings/rules/deferred_target_counts', {
        preview: [
          {rulesetId: 1, count: 3},
          {rulesetId: 2, count: 5},
        ],
      }),
    )

    expectMockFetchCalledTimes('/my-repo/my-repo/settings/rules/deferred_target_counts', 1)
    expectMockFetchCalledWith('/my-repo/my-repo/settings/rules/deferred_target_counts', {ruleset_ids: [1, 2]}, 'equal')

    expect(result.current.rulesetPreviewCounts).toEqual({'1': 3, '2': 5})
    expect(result.current.rulesetPreviewSamples).toEqual({})
    expect(result.current.rulesetPreviewErrors).toEqual({})
  })

  it('fetch the target count for a repo and org rulesets at repo level', async () => {
    const rulesets = [
      createRuleset({
        id: 1,
        rules: [createRule()],
        conditions: [createRefNameCondition(['n.+'], [])],
        source: orgSource,
      }),
      createRuleset({
        id: 2,
        rules: [createRule()],
      }),
    ]

    const {result} = renderHook(() => useTargetCount(samples.repo, 'repository', rulesets), {
      wrapper: getWrapper({}),
    })

    await act(() =>
      mockFetch.resolvePendingRequest('/my-repo/my-repo/settings/rules/deferred_target_counts', {
        preview: [
          {rulesetId: 1, count: 3},
          {rulesetId: 2, count: 1},
        ],
      }),
    )

    expectMockFetchCalledTimes('/my-repo/my-repo/settings/rules/deferred_target_counts', 1)
    expectMockFetchCalledWith('/my-repo/my-repo/settings/rules/deferred_target_counts', {ruleset_ids: [1, 2]}, 'equal')

    expect(result.current.rulesetPreviewCounts).toEqual({'1': 3, '2': 1})
    expect(result.current.rulesetPreviewSamples).toEqual({})
    expect(result.current.rulesetPreviewErrors).toEqual({})
  })

  it.each`
    level             | rulesetSource | isStafftools | expectedUrl
    ${'organization'} | ${orgSource}  | ${false}     | ${'/organizations/my-org/settings/rules/deferred_target_counts'}
    ${'repository'}   | ${repoSource} | ${false}     | ${'/my-repo/my-repo/settings/rules/deferred_target_counts'}
    ${'organization'} | ${orgSource}  | ${true}      | ${'/stafftools/users/my-org/organization_rules/deferred_target_counts'}
    ${'repository'}   | ${repoSource} | ${true}      | ${'/stafftools/repositories/my-repo/my-repo/repository_rules/deferred_target_counts'}
  `(
    'fetches the target count for a $rulesetSource.type ruleset at $level level when stafftools is $isStafftools',
    async ({level, rulesetSource, isStafftools, expectedUrl}) => {
      const rulesets = [
        createRuleset({
          id: 1,
          rules: [createRule()],
          conditions: [createPropertyCondition()],
          source: rulesetSource,
        }),
      ]

      const hookSource: Repository | Organization = level === 'organization' ? samples.org : samples.repo

      renderHook(() => useTargetCount(hookSource, level as SourceType, rulesets), {
        wrapper: getWrapper({isStafftools}),
      })

      expectMockFetchCalledTimes(expectedUrl, 1)
    },
  )
})
