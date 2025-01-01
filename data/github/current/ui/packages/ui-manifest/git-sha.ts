import {exec} from 'node:child_process'
import {promisify} from 'node:util'

const execAsync = promisify(exec)

export async function getCurrentGitSha() {
  const {stdout} = await execAsync('git rev-parse HEAD')
  return stdout.trim()
}
