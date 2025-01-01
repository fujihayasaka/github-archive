import {exec} from 'node:child_process'
import {readFile, writeFile} from 'node:fs/promises'
import fs from 'node:fs'

interface PackageLock {
  packages: {
    [key: string]: {
      version: string
      dependencies?: {[key: string]: string}
      devDependencies?: {[key: string]: string}
      peerDependencies?: {[key: string]: string}
    }
  }
}

function execPromise(command: string) {
  return new Promise((resolve, reject) => {
    const child = exec(command, {cwd: '../../../'}, error => {
      if (error) {
        reject(error)
      }
      resolve(null)
    })
    child.stdout?.pipe(process.stdout)
    child.stderr?.pipe(process.stderr)
  })
}

async function readPackageLock() {
  const fileContents = await readFile('../../../package-lock.json')
  return JSON.parse(fileContents.toString()) as PackageLock
}

// A few packages are expected to have nested node_modules
const packagesWithExpectedNesting = ['react-next']

function getWorkspaceFromPath(path: string): string {
  const workspace = path.split('/node_modules').at(0)
  if (typeof workspace === 'undefined') throw new Error('workspace undefined')
  return workspace
}

function getPackageFromPath(path: string): string {
  const pkg = path.split('/node_modules/').at(-1)
  if (typeof pkg === 'undefined') throw new Error('package undefined')
  return pkg
}

function getUnhoistedPackages({packages}: PackageLock) {
  const unhoistedPackages = []

  for (const path of Object.keys(packages)) {
    const isUnhoisted = !path.startsWith('node_modules') && path.includes('node_modules')

    if (!isUnhoisted) {
      continue
    }

    // Skip packages with expected nesting
    if (packagesWithExpectedNesting.some(p => path.includes(`ui/packages/${p}`))) {
      continue
    }

    unhoistedPackages.push(path)
  }

  return unhoistedPackages
}

async function hoistNodeModules() {
  console.log('🕵️ Checking for unhoisted packages...')
  const packageLock = await readPackageLock()
  const unhoistedPackagePaths = getUnhoistedPackages(packageLock)

  // If no packages are unhoisted, exit
  if (!unhoistedPackagePaths.length) {
    console.log('✨ All node_modules are properly hoisted')
    return
  }

  console.log('🤖🛠️ Detected unhoisted packages, fixing...')

  // Find all explicit dependencies which are unhoisted
  const dependenciesToInstall = new Set<string>()
  for (const packagePath of unhoistedPackagePaths) {
    const workspaceDirectory = getWorkspaceFromPath(packagePath)
    const packageName = getPackageFromPath(packagePath)

    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    const {dependencies, devDependencies, peerDependencies} = packageLock.packages[workspaceDirectory]!
    const desiredVersion =
      dependencies?.[packageName] || devDependencies?.[packageName] || peerDependencies?.[packageName]

    if (desiredVersion && desiredVersion !== '*') {
      const packageToInstall = `${packageName}@${desiredVersion}`
      dependenciesToInstall.add(packageToInstall)

      console.log(`🏗️ Hoisting ${packageToInstall} from ${workspaceDirectory}`)
    }
  }

  // Grab the main package.json so that we can restore it when we are done
  const originalPackageJson = await readFile('../../../package.json')

  // Run npm install at the top level to hoist the dependencies
  const dependenciesToInstallString = [...dependenciesToInstall].join(' ')
  console.log(`Installing dependencies: ${dependenciesToInstallString}`)
  await execPromise(`npm i --ignore-scripts --no-fund --no-audit ${dependenciesToInstallString}`)

  // Restore the original main package.json
  await writeFile('../../../package.json', originalPackageJson)

  // Run npm install again to ensure package-lock.json is updated and submodules get hoisted
  await execPromise('npm i --ignore-scripts --no-fund --no-audit')

  const finalPackageLock = await readPackageLock()
  const remainingUnhoistedPackages = getUnhoistedPackages(finalPackageLock)
  if (remainingUnhoistedPackages.length) {
    console.error('❌ Failed to hoist the following packages:')
    for (const packagePath of remainingUnhoistedPackages) {
      const packageName = getPackageFromPath(packagePath)
      const exisingVersion = finalPackageLock.packages[`node_modules/${packageName}`]?.version
      console.error(
        `  - ${packageName} @ ${finalPackageLock.packages[packagePath]?.version} in ${getWorkspaceFromPath(
          packagePath,
        )}/package.json`,
      )
      if (exisingVersion) {
        console.error(`    💡 Consider switching to version ${exisingVersion}`)
      }
    }
    process.exit(1)
  } else {
    console.log('✅ Successfully hoisted all packages')
  }

  console.timeEnd('hoistNodeModules')
}

const prcPath = '/workspaces/github/node_modules/@primer/react'

if (!fs.existsSync(prcPath) || !fs.lstatSync(prcPath).isSymbolicLink()) {
  await hoistNodeModules()
}
