import {promises as fs} from 'fs'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'
import {
  baseManifestKeys,
  type CSSManifest,
  type JSManifest,
  type StaticAssetManifest,
  type UIManifest,
  type UIManifestBaseKey,
} from './manifest-types.ts'
import {getAssetsBasePath} from './paths.ts'

function isAllowedExtraFile(file: string) {
  if (file.startsWith('ui-manifest') && file.endsWith('.json')) {
    return true
  }

  if (file.endsWith('.map')) {
    return true
  }

  return false
}

function getExpectedFiles(uiManifest: UIManifest, staticManifest: StaticAssetManifest) {
  const filesFromManifest = new Set<string>(['manifest.static.json'])

  function addManifestFiles(...files: string[]) {
    for (const file of files) {
      filesFromManifest.add(file)
    }
  }

  // Add all files from the UI manifest
  for (const manifestType of Object.keys(uiManifest)) {
    // ignore metadata in the manifest
    if (baseManifestKeys.has(manifestType as UIManifestBaseKey)) {
      // base keys are for non-bundler data, so they won't have a matching manifest file
      continue
    }

    // Add the manifest file itself to the expected files list
    const manifestFileName = manifestType === 'webpack' ? 'manifest.json' : `manifest.${manifestType}.json`
    addManifestFiles(manifestFileName)

    if (manifestType === 'alloy') {
      // Alloy has a different structure, so we need to handle it separately
      const alloyManifest = uiManifest[manifestType]

      addManifestFiles(...Object.values(alloyManifest.entries))
      addManifestFiles(...alloyManifest.chunks)
      addManifestFiles(alloyManifest.manifest)
      continue
    }

    if (manifestType === 'relay') {
      // Relay does not generate any additional files
      continue
    }

    const manifest = uiManifest[manifestType] as CSSManifest | JSManifest
    addManifestFiles(...Object.values(manifest).map(entry => entry.src))
  }

  // Add all files from the static manifest
  addManifestFiles(...Object.values(staticManifest))

  return filesFromManifest
}

export async function validateManifest(uiManifest: UIManifest, staticManifest: StaticAssetManifest) {
  const expectedFiles = getExpectedFiles(uiManifest, staticManifest)

  const dir = fullPathFromRoot(getAssetsBasePath())
  const seen: Set<string> = new Set()
  const errors: Error[] = []
  for (const file of await fs.readdir(dir)) {
    if (expectedFiles.has(file) || isAllowedExtraFile(file)) {
      seen.add(file)
    } else {
      errors.push(new Error(`Saw file not in manifest.json: ${file}`))
    }
  }

  const remainder = Array.from(expectedFiles)
    .filter(file => !seen.has(file))
    .map(file => new Error(`Did not see file listed in manifest: ${file}`))
  const allErrors = [...errors, ...remainder]
  const haveErrors = allErrors.length > 0
  for (const error of allErrors) {
    console.error(`❌ ${error.message}`)
  }
  console.log(`🔎 Scanned ${seen.size} files from ui-manifest.json`)

  if (haveErrors) {
    throw new Error('Manifest validation failed. See errors above.')
  }
  console.log('✅ UI Manifest validation passed')
}
