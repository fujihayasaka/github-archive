import type {PluginOption} from 'vite'
import MagicString from 'magic-string'

/**
 * This plugin transforms imports of `vi`, `describe`, and `it` from `@github-ui/tests` to imports directly from `vitest`.
 * This is necessary because Vitest's hoistMocksPlugin requires test utilities to be imported directly from vitest.
 * See: https://github.com/vitest-dev/vitest/blob/main/packages/mocker/src/node/hoistMocksPlugin.ts
 */
export function transformViImportsPlugin(): PluginOption {
  return {
    name: 'transform-vi-imports-plugin',
    enforce: 'pre',

    transform(code: string, id: string) {
      if (!id.match(/\.(ts)x?$/)) {
        return null
      }

      if (!code.includes('@github-ui/tests')) {
        return null
      }

      try {
        const importRegex = /import\s+{([^}]*)}\s+from\s+['"]@github-ui\/tests['"]/g
        let match: RegExpExecArray | null
        let hasChanges = false
        const magicString = new MagicString(code)

        while ((match = importRegex.exec(code)) !== null) {
          const fullImport = match[0]
          const importSpecifiers = match[1]?.split(',').map(s => s.trim())
          const start = match.index
          const end = start + fullImport.length

          // Check if 'vi', 'describe', or 'it' are among the imported specifiers
          const vitestSpecifiers = ['vi', 'describe', 'it']
          const vitestImports = importSpecifiers?.filter(spec => vitestSpecifiers.includes(spec))

          if (vitestImports && vitestImports.length > 0) {
            hasChanges = true

            // If all imports are vitest utilities, replace the entire import
            if (importSpecifiers?.length === vitestImports.length) {
              const replacement = `import { ${vitestImports.join(', ')} } from 'vitest'`
              magicString.overwrite(start, end, replacement)
            } else {
              // Else split imports when only some specifiers need to come from vitest
              const remainingSpecifiers = importSpecifiers?.filter(spec => !vitestSpecifiers.includes(spec)) || []
              const replacement = `import { ${remainingSpecifiers.join(
                ', ',
              )} } from '@github-ui/tests'; import { ${vitestImports.join(', ')} } from 'vitest'`
              magicString.overwrite(start, end, replacement)
            }
          }
        }

        if (hasChanges) {
          return {
            code: magicString.toString(),
            map: magicString.generateMap({hires: true}),
          }
        }
      } catch (error) {
        console.error(`Error transforming imports in ${id}:`, error)
      }

      return null
    },
  }
}
