import {readFileSync, writeFileSync} from 'node:fs'
import {resolve as resolvePath} from 'node:path'
import type {CustomActionFunction} from 'plop'

export interface ReplaceInFileConfig {
  type: 'replaceInFile'
  path: string
  matcher: RegExp
  newValue: string
}

export const replaceInFile: CustomActionFunction = (answers, configInput, plop) => {
  if (process.env.NODE_ENV === 'test') {
    return 'Skipping action for tests'
  }

  const {matcher, path: targetPath, newValue} = configInput as unknown as ReplaceInFileConfig

  const filePath = resolvePath(plop.getPlopfilePath(), targetPath)
  const relativePath = filePath.replace(resolvePath(plop.getDestBasePath()), '')

  // Replace the matcher with the new value
  const fileData = readFileSync(filePath, 'utf8').replace(matcher, newValue)

  // Write the file back to disk
  writeFileSync(filePath, fileData, 'utf8')

  return relativePath
}
