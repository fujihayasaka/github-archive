import {existsSync, writeFileSync, mkdirSync} from 'fs'
import {join} from 'path'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'
import {getJSEntryPoints, getCSSEntryPoints, getSSREntryPoints} from '@github-ui/client-build-tools/entry-points'
import {createGeneratedFiles} from '@github-ui/client-build-tools/generated-files'
import bundlerFlags from '@github-ui/client-build-tools/bundler-flags.json' with {type: 'json'}
import type {AlloyManifest, CSSManifest, JSManifest} from './manifest-types'

type BundlerFlags = Record<string, {flag: string; bundler: string}>

const publicPath = fullPathFromRoot('public')
const assetsPath = join(publicPath, 'assets')
const jsManifestPath = join(assetsPath, 'manifest.json')
const cssManifestPath = join(assetsPath, 'manifest.css.json')
const alloyManifestPath = join(assetsPath, 'manifest.alloy.json')

const fakeChecksum = 'aaaaaaaaaaaa'

/** Ensure the parent directories for the manifest exist on disk */
function setupDirectoryStructure() {
  if (!existsSync(publicPath)) {
    mkdirSync(publicPath)
  }

  if (!existsSync(assetsPath)) {
    mkdirSync(assetsPath)
  }
}

/**
 * Generate a stub Javascript manifest based on the Webpack config which can be passed to the Rails test suite
 * and not rely on running webpack and transpiling all of the assets on disk.
 */
function generateJavascriptManifest(): JSManifest {
  const entry = getJSEntryPoints()
  const manifest: JSManifest = {}

  // defining some entry points that are required in tests but not
  // visible through the webpack config's entry object
  manifest['wp-runtime.js'] = {src: `wp-runtime-${fakeChecksum}.js`}

  const propertyNames = Object.getOwnPropertyNames(entry)
  for (const propertyName of propertyNames) {
    const value = entry[propertyName]
    if (typeof value !== 'string') {
      throw new Error(`Unexpected entry point value: ${value}`)
    }

    const fileName = `${propertyName}.js`
    const sourceValue = `${propertyName}-${fakeChecksum}.js`
    const recordValue = {src: sourceValue}

    manifest[fileName] = recordValue
  }

  return manifest
}

/**
 * Generate a stub CSS manifest based on the Webpack config which can be passed to the Rails test suite
 * and not rely on running webpack and transpiling all of the assets on disk.
 */
function generateStubCssManifest(): CSSManifest {
  const entry = getCSSEntryPoints()
  const manifest: CSSManifest = {}

  const propertyNames = Object.getOwnPropertyNames(entry)
  for (const propertyName of propertyNames) {
    const cssFileName = `${propertyName}.css`
    const cssSourceFileName = `${propertyName}-${fakeChecksum}.css`
    manifest[cssFileName] = {src: cssSourceFileName}

    const jsCssFileName = `${cssFileName}.js`
    manifest[jsCssFileName] = {src: `${cssSourceFileName}.js`}
  }

  return manifest
}

const ssrNames = Object.keys(getSSREntryPoints()).sort()

function generateStubAlloyManifest(): AlloyManifest {
  return {
    entries: {
      alloy: `alloy-${fakeChecksum}.js`,
    },
    chunks: [],
    ssrNames,
    manifest: `manifest-${fakeChecksum}.json`,
  }
}

/**
 * Write the manifest object to disk as JSON
 */
function persistManifest(path: string, manifest: JSManifest | CSSManifest | AlloyManifest) {
  const manifestText = JSON.stringify(manifest, null, 2)
  writeFileSync(path, manifestText)
}

/**
 * Write the assets object to disk
 */
function persistAssets(jsManifest: JSManifest, cssManifest: CSSManifest, alloyManifest: AlloyManifest) {
  for (const {src: asset} of [...Object.values(jsManifest), ...Object.values(cssManifest)]) {
    writeFileSync(join(assetsPath, asset), '')
  }
  for (const asset of Object.values(alloyManifest.entries)) {
    writeFileSync(join(assetsPath, asset), '')
  }
}

export function buildAssetsForTests() {
  setupDirectoryStructure()

  const jsManifest = generateJavascriptManifest()
  persistManifest(jsManifestPath, jsManifest)

  for (const bundlerFlagKey of Object.getOwnPropertyNames(bundlerFlags as BundlerFlags)) {
    const manifestPath = join(assetsPath, `manifest.${bundlerFlagKey}.json`)
    persistManifest(manifestPath, jsManifest)
  }

  const cssManifest = generateStubCssManifest()
  persistManifest(cssManifestPath, cssManifest)

  const alloyManifest = generateStubAlloyManifest()
  persistManifest(alloyManifestPath, alloyManifest)

  persistAssets(jsManifest, cssManifest, alloyManifest)

  createGeneratedFiles()
}
