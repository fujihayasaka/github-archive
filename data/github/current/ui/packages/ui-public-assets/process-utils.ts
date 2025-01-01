import {execSync} from 'child_process'
import {existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync} from 'fs'
import {rgPath} from '@vscode/ripgrep'
import {rootPath} from '@github-ui/client-build-tools/path-utils'

import {getFingerprintMapping} from './fingerprinted-mapping.ts'
import {ASSETS_DIR_PATH, FINGERPRINT_MAPPING_PATH, MOVE_EXTENSIONS, POSTCSS_ASSETS_PATH} from './constants.ts'
import type {OrganizedAssets, RipgrepMatch, RipgrepMatchMap} from './types'

export function mapPostcssAssetsToFile(extractedUrls: string[]): void {
  const processedUrls = [
    ...new Set(
      extractedUrls.reduce<string[]>((acc: string[], url: string) => {
        // Check if the URL does not start with 'data:' or '#'
        if (!url.startsWith('data:') && !url.startsWith('#')) {
          const formattedUrl = url.startsWith('/') ? url : `/${url}`
          acc.push(formattedUrl)
        }
        return acc
      }, []),
    ),
  ]

  if (processedUrls.length > 0) {
    if (!existsSync(ASSETS_DIR_PATH)) {
      mkdirSync(ASSETS_DIR_PATH, {recursive: true})
    }

    const txtUrlsContent = mapToOriginalOrKeep(processedUrls, getFingerprintMapping(FINGERPRINT_MAPPING_PATH)).join(
      '\n',
    )
    console.log(`✅ Fingerprinted postcss assets URLs\n`)
    writeToFile(POSTCSS_ASSETS_PATH, txtUrlsContent)
  } else {
    console.log('ℹ️  No valid asset URLs were collected from postcss.')
  }
}

export function mapToOriginalOrKeep(urls: string[], mapping: Record<string, string>) {
  return urls.map(url => mapping[url] || url)
}

export function mapOnlyFingerprintMatches(urls: string[], mapping: Record<string, string>) {
  return urls.map(url => mapping[url]).filter(Boolean)
}

export function runCommand(command: string) {
  try {
    execSync(command, {stdio: 'inherit'})
    console.log(`✅ Successfully ran "${command}"\n`)
  } catch (error) {
    console.error(`❌ Error during command run: ${command}`, error)
    process.exit(1)
  }
}

export function writeToFile(file: string, content: string | NodeJS.ArrayBufferView) {
  try {
    writeFileSync(file, content, 'utf-8')
    console.log(`✅ File created and written at: ${file}\n`)
  } catch (error) {
    console.error('❌ Error writing to file:', error)
  }
}

export function mergeAndDeduplicate(files: string[]): string[] {
  const linesSet: Set<string> = new Set()

  for (const file of files) {
    try {
      const fileContent = readFileSync(file, 'utf-8')
      const lines = fileContent.split('\n')

      for (const line of lines) {
        const trimmedLine = line.trim()
        if (trimmedLine !== '') {
          linesSet.add(trimmedLine)
        }
      }
    } catch (error) {
      console.error(`❌ Error reading URLs from ${file}`, error)
    }
  }
  return Array.from(linesSet)
}

export function perfomAndOrganizeSearch(urls: string[], ignorePaths?: string[]) {
  const matchMap: RipgrepMatchMap = {}
  const organizedAssets: OrganizedAssets = {
    moveAssets: new Set<string>(),
    duplicateAssets: new Set<string>(),
  }

  let ignoreGlobs = ''
  if (ignorePaths) {
    ignoreGlobs = ignorePaths.map(pathName => `--glob !${pathName}`).join(' ')
  }

  for (const url of urls) {
    try {
      const rawResult = execSync(
        `${rgPath} --no-heading --with-filename --line-number "${url}" ../../../ ${ignoreGlobs}`,
        {
          encoding: 'utf8',
        },
      ).toString()
      const matches: RipgrepMatch[] = []

      for (const line of rawResult.split('\n')) {
        const match = line.match(/^(.*?):(\d+):(.*)$/) // Match pattern: filename:line:matched text
        if (match) {
          const [, file, lineNumber, matchedText] = match
          const foundLocation = file?.replace('../../..', '')
          if (foundLocation) {
            matches.push({
              location: foundLocation,
              lineNumber: lineNumber ? parseInt(lineNumber) : undefined,
              matchedText,
            })
            addByExtension(url, foundLocation, organizedAssets)
          }
        }
        matchMap[url] = matches
      }
    } catch {
      // no match
    }
  }
  return {matchMap, organizedAssets}
}

function addByExtension(url: string, location: string, organizedMap: OrganizedAssets) {
  // URLs can be symlinks, so we want the real path
  try {
    const realPath = realpathSync(`${rootPath}/public${url}`)
    const extension = location.substring(location.lastIndexOf('.'))

    if (extension && !MOVE_EXTENSIONS.includes(extension)) {
      organizedMap.duplicateAssets.add(realPath.replace(`${rootPath}/`, ''))
    } else if (MOVE_EXTENSIONS.includes(extension)) {
      organizedMap.moveAssets.add(realPath.replace(`${rootPath}/`, ''))
    } else {
      console.error(`❌ Error: The ${url} does not have an extension.`)
    }
  } catch (error) {
    console.error(`❌ Error adding url to move and duplicate asset files: ${url}`, error)
  }
}
