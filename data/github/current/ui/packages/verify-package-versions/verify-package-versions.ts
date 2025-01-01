import fs from 'node:fs'
import packageLock from '../../../package-lock.json' with {type: 'json'}

interface DependencyTree {
  [key: string]: {
    [key: string]: string[]
  }
}

interface PackageJSON {
  name: string
  dependencies?: {[key: string]: string}
  devDependencies?: {[key: string]: string}
  workspaces?: string[]
}

const packages = packageLock.packages
type PackagePath = keyof typeof packages

const IGNORED_PACKAGES = ['@github-ui/react-next']

const allPackages = Object.keys(packages) as PackagePath[]

function findMismatchedVersions(dependencyMap: DependencyTree) {
  const errors: string[] = []

  for (const [name, versions] of Object.entries(dependencyMap)) {
    if (Object.keys(versions).length > 1) {
      const msg: string[] = [`❌ Found mismatched versions for ${name}:`]

      for (const [version, packageNames] of Object.entries(versions)) {
        msg.push(`    - ${version} in ${packageNames.join(', ')}`)
      }

      errors.push(msg.join('\n'))
    }
  }

  return errors
}

function extractDependencies(
  dependencyTree: DependencyTree,
  packageName: string,
  dependencies?: {[key: string]: string},
) {
  if (!dependencies) return

  for (const [dependency, version] of Object.entries(dependencies)) {
    if (version === '*' || IGNORED_PACKAGES.includes(packageName)) continue

    dependencyTree[dependency] ||= {}
    dependencyTree[dependency][version] ||= []
    dependencyTree[dependency][version].push(packageName)
  }
}

function findDependencies() {
  const paths = allPackages.filter(
    // filter down to just workspaces
    name => name && !name.includes('node_modules'),
  )
  const dependencyTree: DependencyTree = {}

  if (paths.length < 100) {
    throw new Error('package.json blob did not discover a sufficient number of packages')
  }

  for (const path of paths) {
    const pkg = packages[path] as PackageJSON

    extractDependencies(dependencyTree, pkg.name, pkg.dependencies)
    extractDependencies(dependencyTree, pkg.name, pkg.devDependencies)
  }

  return dependencyTree
}

function findMismatchedDependencies() {
  console.log('🕵️ Checking for mismatched package versions...')
  const dependencyTree = findDependencies()
  const errors = findMismatchedVersions(dependencyTree)

  if (errors.length > 0) {
    console.error(errors.join('\n'))
    throw new Error('Found mismatched package versions')
  }

  console.log('✨ All package versions are consistent')
}

// We have some packages that should only have a single version installed, even as a sub-dependency
const forceSingleVersionFilters = [/^@primer\//, /^@github\//, /^@oddbird\/popover-polyfill/]
// We have some duplicate packages currently, but this can be removed once we dedupe them
// DO NOT ADD NEW PACKAGES TO THIS LIST
const ignoredDuplicates = new Set([
  '@github/tab-container-element',
  '@primer/live-region-element',
  '@github/combobox-nav',
  '@github/template-parts',
])

async function findMismatchedSubDependencies() {
  console.log('🕵️ Checking for mismatched sub-dependencies...')
  const matchedPackages = new Map<string, PackagePath[]>()

  // Read through all the installed packages and find any that are supposed to have only a single version
  for (const packagePath of allPackages) {
    const packageName = packagePath.split('node_modules/').pop()
    const forceSingleVersion = packageName && forceSingleVersionFilters.some(filter => filter.test(packageName))

    if (forceSingleVersion) {
      const existingPackages = matchedPackages.get(packageName) || []
      matchedPackages.set(packageName, [...existingPackages, packagePath])
    }
  }

  let foundDuplicate = false
  let foundDedupedIgnoredPackage = false
  for (const [packageName, packagePaths] of matchedPackages) {
    const shouldIgnore = ignoredDuplicates.has(packageName)
    // We should not find more than 1 instance for non-ignored packages
    if (packagePaths.length > 1 && !shouldIgnore) {
      console.error(`❌ Found mismatched sub-dependency versions for ${packageName}:`)
      console.error(
        packagePaths
          .map(p => `    - ${'version' in packages[p] ? packages[p].version : 'unspecified version'} in ${p}`)
          .join('\n'),
      )
      foundDuplicate = true
    } else if (packagePaths.length === 1 && shouldIgnore) {
      // This package was ignored, but now only has one version installed. Make sure our ignore list gets cleaned up
      foundDedupedIgnoredPackage = true
      console.error(
        `🔥 Package ${packageName} is no longer duplicated 🎉. Please remove it from the ignoredDuplicates list in verify-package-versions.ts`,
      )
    }
  }

  if (foundDuplicate) {
    throw new Error(
      'Duplicate packages can cause runtime errors and excessive bundle size. Please inspect the duplicate versions above and ensure only one version is installed for each of these packages.',
    )
  }

  if (foundDedupedIgnoredPackage) {
    throw new Error(
      'Thanks for cleaning up a duplicate dependency! Please fix the ignoredDuplicates list in verify-package-versions.ts to ensure future duplications are not accidentally ignored.',
    )
  }

  console.log('✨ No duplicate packages found')
}

const prcPath = '/workspaces/github/node_modules/@primer/react'

if (!fs.existsSync(prcPath) || !fs.lstatSync(prcPath).isSymbolicLink()) {
  findMismatchedDependencies()
  findMismatchedSubDependencies()
}
