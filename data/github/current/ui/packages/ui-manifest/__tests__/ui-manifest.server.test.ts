import {afterEach, beforeEach, describe, expect, it} from '@github-ui/tests'
import {readFile, unlink} from 'fs/promises'
import {buildManifestFromDisk, readUIManifest} from '../ui-manifest'
import {execSync} from 'node:child_process'
import {bundlerFlags} from '../bundler-flags'
import {getClientFeatureFlags} from '../feature-flags'

const __dirname = new URL('.', import.meta.url).pathname
const fixturesPath = `${__dirname}__fixtures__`
const uiManifestPath = `${fixturesPath}/ui-manifest.json`
const gitSha = execSync('git rev-parse HEAD').toString().trim()
const uiManifestWithShaPath = `${fixturesPath}/ui-manifest-${gitSha}.json`

describe('Building the UI manifest from disk', () => {
  beforeEach(() => {
    process.env.ASSETS_BASE_PATH = fixturesPath
  })

  afterEach(async () => {
    delete process.env.ASSETS_BASE_PATH
    try {
      await unlink(uiManifestPath)
      await unlink(uiManifestWithShaPath)
    } catch {
      // ignore errors if manifest wasn't written
    }
  })

  it('should include all manifests based on the manifest file name', async () => {
    await buildManifestFromDisk()
    const manifestFromDisk = JSON.parse(await readFile(uiManifestPath, 'utf-8'))
    const manifest = await readUIManifest()
    expect(manifest).toEqual(manifestFromDisk)
    expect(manifest).toEqual({
      gitSha,
      bundlerFlags,
      featureFlags: getClientFeatureFlags(),
      css: {
        'a.css': {
          src: 'a-deadbeef.css',
        },
      },
      extra: {
        'a.js': {
          cssFiles: ['a-feedbeef.css'],
          files: ['a-feedbeef.js'],
          src: 'a-feedbeef.js',
        },
      },
      webpack: {
        'a.js': {
          cssFiles: ['a-deadbeef.css'],
          files: ['a-deadbeef.js'],
          src: 'a-deadbeef.js',
        },
      },
    })
  })

  it('should create a copy of the manifest with the current git sha', async () => {
    await buildManifestFromDisk()
    const manifestContents = await readFile(uiManifestPath, 'utf-8')
    const manifestWithShaContents = await readFile(uiManifestWithShaPath, 'utf-8')

    expect(manifestWithShaContents).toEqual(manifestContents)
  })
})
