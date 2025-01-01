// @ts-check
import {rootPath} from '@github-ui/client-build-tools/path-utils'
import {execSync} from 'child_process'
/**
 * @returns {Set<string>}
 */
export function getWorkspacePackages() {
  try {
    const output = execSync('npm ls --workspaces --json', {
      encoding: 'utf-8',
      cwd: rootPath, // Change working directory to the project root
    })
    const parsedOutput = JSON.parse(output)
    return new Set(Object.keys(parsedOutput.dependencies || {}))
  } catch (error) {
    if (error instanceof Error) {
      console.error(`Error fetching workspace packages: ${error.message}`)
    } else {
      console.error(error)
    }
    return new Set()
  }
}
