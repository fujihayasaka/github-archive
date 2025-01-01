import {reposPickerDefinitionsPath, reposPickerRepositoriesCountPath, reposPickerRepositoriesPath} from '../paths'
import type {PickerScope} from '../types'

const sampleScopes = {
  org: {type: 'organization', slug: 'acme'} as PickerScope,
  chineseOrg: {type: 'organization', slug: '你好你'} as PickerScope,
  enterprise: {type: 'enterprise', slug: 'acme-corp'} as PickerScope,
  chineseEnterprise: {type: 'enterprise', slug: '你好你'} as PickerScope,
}

describe('reposPickerDefinitionsPath', () => {
  it('should return the correct path for an org', () => {
    expect(reposPickerDefinitionsPath(sampleScopes.org)).toEqual('/repositories/picker/definitions?owner=acme')
  })

  it('should return the correct path when enconding an org', () => {
    expect(reposPickerDefinitionsPath(sampleScopes.chineseOrg)).toEqual(
      '/repositories/picker/definitions?owner=%E4%BD%A0%E5%A5%BD%E4%BD%A0',
    )
  })

  it('should return the correct path for an enterprise', () => {
    expect(reposPickerDefinitionsPath(sampleScopes.enterprise)).toEqual(
      '/repositories/picker/definitions?enterprise=acme-corp',
    )
  })

  it('should return the correct path when enconding an enterprise', () => {
    expect(reposPickerDefinitionsPath(sampleScopes.chineseEnterprise)).toEqual(
      '/repositories/picker/definitions?enterprise=%E4%BD%A0%E5%A5%BD%E4%BD%A0',
    )
  })
})

describe('reposPickerRepositoriesPath', () => {
  it('should return the correct path for when no query', () => {
    expect(reposPickerRepositoriesPath({scope: sampleScopes.org})).toEqual('/repositories/picker/search?owner=acme')
  })

  it('should return the correct path for empty query', () => {
    expect(reposPickerRepositoriesPath({scope: sampleScopes.org, query: ''})).toEqual(
      '/repositories/picker/search?owner=acme',
    )
  })

  it('should return the correct path for a repo query', () => {
    expect(reposPickerRepositoriesPath({scope: sampleScopes.org, query: 'foo'})).toEqual(
      '/repositories/picker/search?owner=acme&q=foo',
    )
  })

  it('should return the correct path for a repo query with visibility scope', () => {
    expect(
      reposPickerRepositoriesPath({scope: {...sampleScopes.org, visibility: ['private', 'internal']}, query: 'foo'}),
    ).toEqual('/repositories/picker/search?owner=acme&visibility=private%2Cinternal&q=foo')
  })

  it('should return the correct path when enconding', () => {
    expect(reposPickerRepositoriesPath({scope: sampleScopes.chineseOrg, query: 'foo'})).toEqual(
      '/repositories/picker/search?owner=%E4%BD%A0%E5%A5%BD%E4%BD%A0&q=foo',
    )
  })
})

describe('reposPickerRepositoriesCountPath', () => {
  it('should return the correct path for a repo count query', () => {
    expect(reposPickerRepositoriesCountPath({scope: sampleScopes.org, query: 'foo'})).toEqual(
      '/repositories/picker/count?owner=acme&q=foo',
    )
  })

  it('should return the correct path for a repo query with visibility scope', () => {
    expect(
      reposPickerRepositoriesCountPath({
        scope: {...sampleScopes.org, visibility: ['private', 'internal']},
        query: 'foo',
      }),
    ).toEqual('/repositories/picker/count?owner=acme&visibility=private%2Cinternal&q=foo')
  })

  it('should return the correct path when encoding a repo count query', () => {
    expect(reposPickerRepositoriesCountPath({scope: sampleScopes.chineseOrg, query: '你好'})).toEqual(
      '/repositories/picker/count?owner=%E4%BD%A0%E5%A5%BD%E4%BD%A0&q=%E4%BD%A0%E5%A5%BD',
    )
  })

  it('should return the correct path for an enterprise repo count query', () => {
    expect(reposPickerRepositoriesCountPath({scope: sampleScopes.enterprise, query: 'bar'})).toEqual(
      '/repositories/picker/count?enterprise=acme-corp&q=bar',
    )
  })

  it('should return the correct path when encoding an enterprise repo count query', () => {
    expect(reposPickerRepositoriesCountPath({scope: sampleScopes.chineseEnterprise, query: '你好'})).toEqual(
      '/repositories/picker/count?enterprise=%E4%BD%A0%E5%A5%BD%E4%BD%A0&q=%E4%BD%A0%E5%A5%BD',
    )
  })
})
