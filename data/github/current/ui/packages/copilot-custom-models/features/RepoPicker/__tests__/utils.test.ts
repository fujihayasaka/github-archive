import type {BaseRepo} from '../types'
import {formatQueryWithOrg, sortFn} from '../utils'

describe('formatQueryWithOrg', () => {
  it('removes any improperly injected query and injects correct one', () => {
    const org = 'added'
    const query = 'prefix OrG:injected my-repo'
    const formatted = formatQueryWithOrg({org, query})

    expect(formatted).toEqual('org:added prefix my-repo')
  })

  it('removes extraneous spaces', () => {
    const org = 'added  '
    const query = ' prefix   org:injected   my-repo  '
    const formatted = formatQueryWithOrg({org, query})

    expect(formatted).toEqual('org:added prefix my-repo')
  })

  it('returns org when query is empty', () => {
    const org = 'added'
    const query = '  '
    const formatted = formatQueryWithOrg({org, query})

    expect(formatted).toEqual('org:added')
  })
})

describe('sortFn', () => {
  it('sorts repos by name', () => {
    const repos = [
      {nameWithOwner: 'org/repo1'} as BaseRepo,
      {nameWithOwner: 'org/repo3'} as BaseRepo,
      {nameWithOwner: 'org/repo2'} as BaseRepo,
    ]
    const sorted = repos.sort(sortFn)
    expect(sorted).toEqual([{nameWithOwner: 'org/repo1'}, {nameWithOwner: 'org/repo2'}, {nameWithOwner: 'org/repo3'}])
  })
})
