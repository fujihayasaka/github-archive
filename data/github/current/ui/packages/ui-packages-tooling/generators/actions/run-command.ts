import {spawn} from 'child_process'
import type {CustomActionFunction} from 'plop'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'

export interface RunCommandConfig {
  type: 'runCommand'
  cmd: string
  args?: string[]
  cwd?: string
  ignoreFailure?: boolean
  showStdout?: boolean
}

const didSucceed = (code: number | null) => `${code}` === '0'
const baseDir = fullPathFromRoot('')

export const runCommand: CustomActionFunction = (answers, config, plop) => {
  if (process.env.NODE_ENV === 'test') {
    return 'Skipping action for tests'
  }

  const {
    cmd,
    args = [],
    cwd = baseDir,
    ignoreFailure = false,
    showStdout = false,
  } = config as unknown as RunCommandConfig
  const renderedCommand = plop.renderString(cmd, answers)
  const renderedArgs = args.map(arg => plop.renderString(arg, answers))
  const cmdString = `${cmd} ${renderedArgs.join(' ')}`

  return new Promise((resolve, reject) => {
    const command = spawn(renderedCommand, renderedArgs, {cwd, stdio: showStdout ? 'inherit' : 'pipe'})

    command.on('close', code => {
      if (ignoreFailure || didSucceed(code)) {
        resolve(`${cmdString} finished`)
      } else {
        reject(new Error(`${cmdString} exited with ${code}`))
      }
    })

    command.on('error', e => {
      if (ignoreFailure) {
        resolve(`${cmdString} finished with ignored error: ${e.message}`)
      } else {
        reject(e)
      }
    })
  })
}
