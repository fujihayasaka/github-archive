import type {FilterProvider, SuppliedFilterProvider} from '@github-ui/filter'
import {getRepoFilterProviders} from '@github-ui/repos-filter/providers'

import type {PickerScope} from '../../types'
import {adjustProvidersToScope} from '../adjust-providers'

describe('adjustProvidersToScope', () => {
  it('should return the same providers if no visibility scope is provided', () => {
    const providers: SuppliedFilterProvider[] = getRepoFilterProviders(['visibility', 'fork'])
    const scope: PickerScope = {type: 'organization', slug: 'github'}
    const result = adjustProvidersToScope(providers, scope)

    expect(result).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          key: 'visibility',
          filterValues: [
            expect.objectContaining({value: 'public'}),
            expect.objectContaining({value: 'private'}),
            expect.objectContaining({value: 'internal'}),
          ],
        }),
        expect.objectContaining({
          key: 'fork',
        }),
      ]),
    )
  })

  it('should update visibility provider if visibility is in scope', () => {
    const providers: SuppliedFilterProvider[] = getRepoFilterProviders(['visibility', 'fork'])
    const scope: PickerScope = {type: 'organization', slug: 'github', visibility: ['public', 'private']}
    const result = adjustProvidersToScope(providers, scope)

    expect(result).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          key: 'visibility',
          filterValues: [expect.objectContaining({value: 'public'}), expect.objectContaining({value: 'private'})],
        }),
        expect.objectContaining({
          key: 'fork',
        }),
      ]),
    )
  })

  it('should remove visibility provider if only one visibility value is in scope', () => {
    const providers: SuppliedFilterProvider[] = getRepoFilterProviders(['visibility', 'fork'])
    const scope: PickerScope = {type: 'organization', slug: 'github', visibility: ['public']}
    const result = adjustProvidersToScope(providers, scope)
    expect(result).toHaveLength(1)
    expect((result[0] as FilterProvider).key).toBe('fork')
  })

  it('visibility scope has no effect on other providers', () => {
    const providers: SuppliedFilterProvider[] = getRepoFilterProviders(['fork'])
    const scope: PickerScope = {type: 'organization', slug: 'github', visibility: ['public']}
    const result = adjustProvidersToScope(providers, scope)
    expect(result).toHaveLength(1)
    expect((result[0] as FilterProvider).key).toBe('fork')
  })
})
