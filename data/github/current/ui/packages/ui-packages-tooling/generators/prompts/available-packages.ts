import {readdirSync} from 'fs'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'

export function listMatchingPackages(input: string) {
  const packagesDir = fullPathFromRoot('ui/packages')
  const packageNames = readdirSync(packagesDir, {withFileTypes: true})
    .filter(dirent => dirent.isDirectory())
    .map(dirent => dirent.name)

  if (!input) {
    return packageNames
  }

  return packageNames.filter(packageName => packageName.startsWith(input))
}
