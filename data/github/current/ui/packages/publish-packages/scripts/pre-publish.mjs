import {copyFileSync, readFileSync, writeFileSync} from 'node:fs'
import path from 'node:path'

// Access the argument passed from Bash
const [, , packagePath] = process.argv

const packageJsonPath = path.join(packagePath, './package.json')
const packageJsonText = readFileSync(packageJsonPath, 'utf8')
const packageJson = JSON.parse(packageJsonText)
const packageLockJson = JSON.parse(readFileSync('../../../package-lock.json', 'utf8'))

// Create a backup of the original package.json
copyFileSync('package.json', 'package.temp.json')

// Update package exports to point to transpiled JS files
if (packageJson.exports) {
  const distJSExports = packageJson.exports
  for (const fileExport in distJSExports) {
    if (distJSExports[fileExport]) {
      // Add dist
      if (distJSExports[fileExport].startsWith('./')) {
        distJSExports[fileExport] = distJSExports[fileExport].replace('./', './dist/')
      } else {
        distJSExports[fileExport] = `dist/${distJSExports[fileExport]}`
      }

      // Change file extension
      if (distJSExports[fileExport].endsWith('ts') || distJSExports[fileExport].endsWith('tsx')) {
        distJSExports[fileExport] = distJSExports[fileExport].replace(/.ts(x?)$/s, '.js')
      }
    }
  }

  packageJson.exports = distJSExports
}

// Update package main to point to transpiled JS file
if (packageJson.main) {
  packageJson.main = `dist/${packageJson.main}`.replace(/.ts(x?)$/s, '.js')
}

// Update package dependencies to use hoisted package-lock versions & mark @github-ui dependencies as bundleDependencies
if (packageJson.dependencies) {
  for (const dependency in packageJson.dependencies) {
    packageJson.bundleDependencies = packageJson.bundleDependencies || []

    // internal dependencies are bundled and not published, so when building the published package
    // we move all @github-ui dependencies to bundleDependencies and remove them from the package dependencies
    // which will prevent npm from attempting to install them from the registry when the package is installed
    if (dependency.startsWith('@github-ui/')) {
      packageJson.bundleDependencies.push(dependency)

      // Delete the individual dependency from the temporary package's dependencies entry (to prevent npm install)
      if (packageJson.dependencies[dependency]) delete packageJson.dependencies[dependency]
    } else {
      // for external dependencies, get the version number from the hoisted package-lock
      // set the version in the package to "^${version}"
      const packageName = `node_modules/${dependency}`
      const version = packageLockJson.packages[packageName]?.version

      if (version && packageJson.dependencies[dependency]) {
        packageJson.dependencies[dependency] = `^${version}`
      }
    }
  }

  // we don't need to include these in the published package.json
  delete packageJson.devDependencies
}

// sort the bundleDependencies alphabetically
packageJson.bundleDependencies.sort()

writeFileSync(packageJsonPath, `${JSON.stringify(packageJson, null, 2)}\n`, 'utf8')
