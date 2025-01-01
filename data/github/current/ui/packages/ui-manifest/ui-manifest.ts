import {readFile, unlink, writeFile} from 'fs/promises'
import {buildAssetsForTests} from './precompile-assets-for-test.ts'
import {getAllManifestsPaths, getStaticAssetManifestPath, getUIManifestPath} from './paths.ts'
import {getBaseManifest} from './base-manifest.ts'
import {validateClientFeatureFlags} from './feature-flags.ts'
import {validateManifest} from './validate-manifest.ts'

import type {StaticAssetManifest, UIManifest} from './manifest-types'

export async function buildManifestFromDisk() {
  const manifestPaths = getAllManifestsPaths()
  const uiManifest = (await getBaseManifest()) as UIManifest

  for (const manifestPath of manifestPaths) {
    const key = manifestPath.match(/manifest\.(.+)\.json/)?.[1] || 'webpack'

    if (key === 'static') {
      // Static assets (images, fonts, etc) are referenced directly from CSS and JS and do not need to be listed in the manifest
      continue
    }

    const content = JSON.parse(await readFile(manifestPath, 'utf-8'))
    uiManifest[key] = content
  }

  // Write the ui manifest to disk
  const uiManifestContents = JSON.stringify(uiManifest)
  const uiManifestPath = getUIManifestPath()
  const envSuffix = process.env.NODE_ENV === 'development' ? '-dev' : '' // Add -dev for dev builds to avoid collisions in the CDN
  const uiManifestWithShaPath = uiManifestPath.replace(
    'ui-manifest.json',
    `ui-manifest-${uiManifest.gitSha}${envSuffix}.json`,
  )
  console.log('Writing UI manifest to', uiManifestPath, 'and', uiManifestWithShaPath)
  await writeFile(uiManifestPath, uiManifestContents)
  await writeFile(uiManifestWithShaPath, uiManifestContents)
}

export async function readUIManifest() {
  const manifestPath = getUIManifestPath()
  const content = await readFile(manifestPath, 'utf-8')
  return JSON.parse(content) as UIManifest
}

export async function readStaticAssetManifest() {
  const manifestPath = getStaticAssetManifestPath()
  const content = await readFile(manifestPath, 'utf-8')
  return JSON.parse(content) as StaticAssetManifest
}

async function validateUIManifest() {
  const uiManifest = await readUIManifest()
  const staticManifest = await readStaticAssetManifest()
  await validateManifest(uiManifest, staticManifest)
  await validateClientFeatureFlags()
}

export async function cleanManifests() {
  const manifestPaths = getAllManifestsPaths()
  for (const manifestPath of manifestPaths) {
    // The static manifest is used by Rails to get fingerprinted assets in production, so we need to leave it in place
    if (manifestPath.includes('static')) {
      continue
    }

    try {
      await unlink(manifestPath)
    } catch (err) {
      console.log(`Error with deleting file: ${manifestPath}`, err)
    }
  }
}
// Check the args to determine what to do
if (process.argv.includes('--build')) {
  await buildManifestFromDisk()
}

if (process.argv.includes('--build-for-tests')) {
  // Build a fake version all the other manifests
  buildAssetsForTests()

  // Build the UI manifest from the fake manifests on disk
  await buildManifestFromDisk()
}

if (process.argv.includes('--validate')) {
  await validateUIManifest()
}

if (process.argv.includes('--clean')) {
  await cleanManifests()
}
