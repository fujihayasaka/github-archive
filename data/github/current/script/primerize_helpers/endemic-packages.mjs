import fs from 'fs'
import {exec} from 'child_process'

function readFileFromMaster(file) {
  return new Promise((resolve, reject) => {
    exec(`/usr/local/bin/git show master:${file}`, { maxBuffer: 1024 * 1024 * 10 }, (error, stdout, stderr) => {
      resolve(stdout);
    });
  });
}

const getEndemicPackages = async () => {
  const prcPkgs = JSON.parse(fs.readFileSync('/workspaces/primer/react/packages/react/package.json'))
  const dotcomLockRaw = await readFileFromMaster('package-lock.json')
  const dotcomLock = JSON.parse(dotcomLockRaw)

  const prcDepNames = Object.keys(prcPkgs['dependencies'])
  const prcDepVersions = new Map();

  const dotcomDependentsOf = (pkgName) => {
    const dependents = []

    for (const [path, dotcomPkg] of Object.entries(dotcomLock['packages'])) {
      if ((dotcomPkg['dependencies'] ?? {})[pkgName]) {
        dependents.push(path)
      }
    }

    return dependents
  }

  for (const depName of prcDepNames) {
    const dotcomDependents = dotcomDependentsOf(depName)

    if (dotcomDependents.length === 1 && dotcomDependents[0] === 'node_modules/@primer/react') {
      const version = dotcomLock['packages'][`node_modules/${depName}`]?.version
      if (version) prcDepVersions.set(depName, version)
    }
  }

  return prcDepVersions
}

export default getEndemicPackages
