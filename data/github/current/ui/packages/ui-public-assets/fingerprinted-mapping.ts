import {readFileSync, writeFileSync} from 'fs'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'

export function getFingerprintMapping(fingerprintPath: string): Record<string, string> {
  return JSON.parse(readFileSync(fullPathFromRoot(fingerprintPath), 'utf-8'))
}

export function invertFingerprintMapping(fingerprintManifestFile: string, writePath: string): Record<string, string> {
  const fingerprintAssetLookup: Record<string, string> = JSON.parse(
    readFileSync(fullPathFromRoot(fingerprintManifestFile), 'utf-8'),
  )
  const inverted: Record<string, string> = {}
  for (const [srcImage, fingerprintedImg] of Object.entries(fingerprintAssetLookup)) {
    inverted[fingerprintedImg] = `/${srcImage}`
  }
  writeFileSync(writePath, JSON.stringify(inverted, null, 2))
  return inverted
}
