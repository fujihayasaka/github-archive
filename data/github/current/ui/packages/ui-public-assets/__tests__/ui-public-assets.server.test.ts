import path from 'path'
import postcss from 'postcss'
import {beforeAll, describe, it, expect} from '@github-ui/tests'

import {
  mapOnlyFingerprintMatches,
  mapToOriginalOrKeep,
  mergeAndDeduplicate,
  perfomAndOrganizeSearch,
} from '../process-utils'
import {getFingerprintMapping, invertFingerprintMapping} from '../fingerprinted-mapping'

describe('fingerprinted', () => {
  it('inverts fingerprinted assets as expected', () => {
    const invertedMapping = invertFingerprintMapping(
      path.resolve(__dirname, '__fixtures__/fingerprint.json'),
      path.resolve(__dirname, '__fixtures__/inverted-mapping.json'),
    )
    expect(invertedMapping).toEqual({
      '12345-a.webp': '/a.webp',
      '12345-b.webp': '/b.webp',
      '12345-c.webp': '/c.webp',
      '12345-d.webp': '/d.webp',
    })
  })
})

describe('postcss and webpack urls', () => {
  let postcssConfig: {plugins: postcss.AcceptedPlugin[] | undefined; extractedUrls: Set<string>}
  beforeAll(async () => {
    process.env.EXTRACT_POSTCSS_URLS = 'true'
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    postcssConfig = require('@github-ui/postcss/postcss.config')
    invertFingerprintMapping(
      path.resolve(__dirname, '__fixtures__/fingerprint.json'),
      path.resolve(__dirname, '__fixtures__/inverted-mapping.json'),
    )
  })

  it('should read the environment variable', () => {
    expect(process.env.EXTRACT_POSTCSS_URLS).toBe('true')
  })

  it('extracts all asset URLs from processed CSS', async () => {
    const inputCSS = `
      .foo {
        background: url('/assets/foo.png');
      }
      .bar {
        mask-image: url('/icons/bar.svg');
      }
    `
    await postcss(postcssConfig.plugins).process(inputCSS, {from: '', to: ''})
    expect(postcssConfig.extractedUrls).toEqual(new Set(['/assets/foo.png', '/icons/bar.svg']))
  })

  it('should write fingerprint webpack by only returning found fingerprinted extracted asset urls', () => {
    const fingerprintedUrls = ['12345-a.webp', '12345-b.webp', '12345-c.webp', '12345-d.webp', '98732-e.webp']
    const mappedAssets = mapOnlyFingerprintMatches(
      fingerprintedUrls,
      getFingerprintMapping('ui/packages/ui-public-assets/__tests__/__fixtures__/inverted-mapping.json'),
    )
    expect(mappedAssets).toEqual(['/a.webp', '/b.webp', '/c.webp', '/d.webp'])
  })

  it('should not map non-fingerprinted extracted asset urls and return relative path like postcss urls', () => {
    const fingerprintedUrls = ['/e.webp']
    const mappedAssets = mapToOriginalOrKeep(
      fingerprintedUrls,
      getFingerprintMapping('ui/packages/ui-public-assets/__tests__/__fixtures__/inverted-mapping.json'),
    )
    expect(mappedAssets).toEqual(['/e.webp'])
  })
})

describe('merge and dedupe urls', () => {
  it('should dedupe urls in the webpack and postcss extracted url files', () => {
    const postCssFile = path.resolve(__dirname, '__fixtures__/postcss-assets.txt')
    const webpackFile = path.resolve(__dirname, '__fixtures__/webpack-assets.txt')
    const uniqueUrls = mergeAndDeduplicate([postCssFile, webpackFile])
    expect(uniqueUrls.sort()).toEqual(['/assets/foo.png', '/images/bar.svg', '/icons/bar.svg'].sort())
  })
})

describe('perform ripgrep search', () => {
  it('find matches with symlink url', () => {
    const searchUrl = ['/images/modules/account/credit_card.gif']
    const result = perfomAndOrganizeSearch(searchUrl, ['**/ui-public-assets.server.test.ts'])
    expect(Object.keys(result.matchMap).length).toBe(1)
    expect(result.matchMap['/images/modules/account/credit_card.gif']![0]!.location).toBe(
      '/ui/packages/ui-public-assets/__tests__/__fixtures__/test-example.css',
    )
    expect(result.organizedAssets.moveAssets).toEqual(new Set(['public/static/images/modules/account/credit_card.gif']))
    expect(result.organizedAssets.duplicateAssets).toEqual(new Set())
  })

  it('find matches non symlink urls', () => {
    const searchUrl = ['/static/images/mona-bounce.gif']
    const result = perfomAndOrganizeSearch(searchUrl, ['**/ui-public-assets.server.test.ts'])
    expect(Object.keys(result.matchMap).length).toBe(1)
    expect(result.matchMap['/static/images/mona-bounce.gif']![0]!.location).toBe(
      '/ui/packages/ui-public-assets/__tests__/__fixtures__/test-example.css',
    )
    expect(result.organizedAssets.moveAssets).toEqual(new Set(['public/static/images/mona-bounce.gif']))
    expect(result.organizedAssets.duplicateAssets).toEqual(new Set())
  })
})
