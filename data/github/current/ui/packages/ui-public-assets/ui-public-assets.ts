import {readFileSync, writeFileSync} from 'fs'
import {rootPath} from '@github-ui/client-build-tools/path-utils'

import {getFingerprintMapping, invertFingerprintMapping} from './fingerprinted-mapping.ts'
import {
  mapOnlyFingerprintMatches,
  mergeAndDeduplicate,
  perfomAndOrganizeSearch,
  runCommand,
  writeToFile,
} from './process-utils.ts'
import {
  ALL_ASSETS_PATH,
  ASSET_EXTENSIONS,
  DUPLICATE_ASSETS_PATH,
  FINGERPRINT_MAPPING_PATH,
  FINGERPRINT_MANIFEST_PATH,
  IGNORED_PATHS,
  MOVE_ASSETS_PATH,
  POSTCSS_ASSETS_PATH,
  WEBPACK_ASSETS_PATH,
  WEBPACK_MANIFEST_PATH,
} from './constants.ts'
import type {OrganizedAssets, RipgrepMatchMap} from './types'

performance.mark('start-ui-public-assets')
const fingerprintCommand = `npm run --prefix ${rootPath} fingerprint-static-assets`
runCommand(fingerprintCommand)

invertFingerprintMapping(FINGERPRINT_MANIFEST_PATH, FINGERPRINT_MAPPING_PATH)
console.log(`✅ Fingerprinted map written to ${FINGERPRINT_MAPPING_PATH}\n`)

const postCssCommand = `EXTRACT_POSTCSS_URLS=true npm run --prefix ${rootPath} webpack:css:prod`

// This will write all extracted urls to assets/postcss-assets.txt on exit from postcss.config.js from running npm run webpack:css:prod
runCommand(postCssCommand)

// Run webpack - this will update the manifest.json in public/assets/
runCommand(`npm run --prefix ${rootPath} webpack:prod`)

// Filter webpack manifest image URLs from manifest and write image urls to assets/webpack-assets.txt
try {
  const data = readFileSync(WEBPACK_MANIFEST_PATH, 'utf-8')
  const manifest = JSON.parse(data)
  const imagePaths = Object.keys(manifest)
    .filter(key => ASSET_EXTENSIONS.some(ext => key.endsWith(ext)))
    .map(key => manifest[key].src)

  // All of the relative paths in the webpack manifest are from ui/packages
  // So this searches the src which is a fingerprinted image. We then want to map the fingerprinted
  // image src. If found, it will return the location.
  const fingerprintedPaths = mapOnlyFingerprintMatches(imagePaths, getFingerprintMapping(FINGERPRINT_MAPPING_PATH))
  console.log(`✅ Fingerprinted webpack assets URLs\n`)
  writeFileSync(WEBPACK_ASSETS_PATH, fingerprintedPaths.join('\n'), 'utf-8')

  console.log(`✅ Image asset keys written to ${WEBPACK_ASSETS_PATH}\n`)
} catch (err) {
  console.error(`❌ Error writing assets keys from webpack manifest to ${WEBPACK_ASSETS_PATH}`, err)
}

// Contains deduped webpack and postcss extracted asset urls
const allUrls: string[] = mergeAndDeduplicate([POSTCSS_ASSETS_PATH, WEBPACK_ASSETS_PATH])

if (allUrls.length === 0) {
  console.error('❌ No URLs found in either source.')
  process.exit(1)
}

const searchResults = perfomAndOrganizeSearch(allUrls, IGNORED_PATHS)
const rgMatches: RipgrepMatchMap | undefined = searchResults.matchMap
const organizedAssets: OrganizedAssets | undefined = searchResults.organizedAssets

// Write results to assets/
writeToFile(ALL_ASSETS_PATH, JSON.stringify(rgMatches, null, 2))
writeToFile(MOVE_ASSETS_PATH, JSON.stringify(Array.from(organizedAssets.moveAssets), null, 2))
writeToFile(DUPLICATE_ASSETS_PATH, JSON.stringify(Array.from(organizedAssets.duplicateAssets), null, 2))

performance.mark('end-ui-public-assets')

performance.measure('total-execution-time', 'start-ui-public-assets', 'end-ui-public-assets')

const measures = performance.getEntriesByName('total-execution-time')

for (const measure of measures) {
  console.log(`Execution time: ${measure.duration}ms`)
}
