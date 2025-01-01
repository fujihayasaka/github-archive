import {readFileSync, writeFileSync} from 'node:fs'
import {resolve as resolvePath} from 'node:path'
import type {CustomActionFunction} from 'plop'

export interface AddLineToFileConfig {
  type: 'addLineToFile'
  line: string
  path: string
  sectionStart: string
  sectionEnd: string
}

export const addLineToFile: CustomActionFunction = (answers, configInput, plop) => {
  if (process.env.NODE_ENV === 'test') {
    return 'Skipping action for tests'
  }

  const {line, path: targetPath, sectionStart, sectionEnd} = configInput as unknown as AddLineToFileConfig

  const filePath = resolvePath(plop.getPlopfilePath(), targetPath)
  const relativePath = filePath.replace(resolvePath(plop.getDestBasePath()), '')
  const fileData = readFileSync(filePath, 'utf8')
  const matcher = new RegExp(
    `(?<sectionStartLines>^${sectionStart}\n)(?<existingLines>.*)(?<sectionEndLines>\n${sectionEnd}$)`,
    'ms',
  )
  const match = matcher.exec(fileData)

  if (!match?.groups) {
    throw new Error(`Could not find the "${sectionStart}" - "${sectionEnd}" section in ${relativePath}`)
  }
  let newSection = ''
  if (match.groups.existingLines) {
    const list = match.groups.existingLines.split('\n')
    const renderedLine = plop.renderString(line, answers)
    list.push(renderedLine)
    const sortedList = list.sort().join('\n')
    newSection = `${sectionStart}\n${sortedList}\n${sectionEnd}`
  } else {
    newSection = `${match.groups.sectionStartLines}${line}${match.groups.sectionEndLines}`
  }

  writeFileSync(filePath, fileData.replace(matcher, newSection), 'utf8')
  return relativePath
}
