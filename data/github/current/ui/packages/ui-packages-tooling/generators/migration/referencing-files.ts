import path from 'node:path'
import {execSync} from 'node:child_process'
import {rgPath} from '@vscode/ripgrep'
import {fullPathFromRoot, relativePathFromRoot} from '@github-ui/client-build-tools/path-utils'
import {resolveImports} from '@github-ui/resolve-imports'

export async function getReferencingFiles(file: string, ignoreFiles = new Set<string>()) {
  if (!file.startsWith('/')) {
    file = fullPathFromRoot(file)
  }
  const {name} = path.parse(file)
  const command = `${rgPath} -e "'\\..*/${name}'" --json test/js test/components app/assets/modules app/components`

  try {
    const ripgrepResults = execSync(command, {cwd: fullPathFromRoot('')}).toString()
    const filesToCheck = new Set<string>()

    for (const line of ripgrepResults.split('\n')) {
      if (!line.trim()) continue
      try {
        const result = JSON.parse(line)
        if (result.type === 'match') {
          filesToCheck.add(result.data.path.text)
        }
      } catch {
        console.log('invalid json:', line)
      }
    }

    const referencingFiles = []
    const referencingPath = relativePathFromRoot(file)
    for (const fileToCheck of filesToCheck) {
      if (ignoreFiles.has(fileToCheck)) {
        continue
      }

      const resolvedImports = await resolveImports(fullPathFromRoot(fileToCheck))
      if (resolvedImports.files.includes(referencingPath)) {
        referencingFiles.push(fileToCheck)
      }
    }

    return referencingFiles
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } catch (e: any) {
    if (e.stdout?.toString().includes('matched_lines')) {
      // No matches found
      return []
    }

    throw e
  }
}
