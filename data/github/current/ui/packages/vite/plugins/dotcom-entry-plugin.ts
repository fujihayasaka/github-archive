import {getCSSEntryPoints, getJSEntryPoints, getStandaloneEntryNames} from '@github-ui/client-build-tools/entry-points'
import type {PluginOption} from 'vite'

function removeRelativePathPrefix(path: string) {
  return path.replace(/^\.\//, '')
}

const entries: Record<string, string> = {}
const jsEntryPoints = getJSEntryPoints()
const standaloneEntryFiles = new Set([...getStandaloneEntryNames(jsEntryPoints)].map(name => `${name}.js`))

for (const [name, relativePath] of Object.entries(jsEntryPoints)) {
  entries[`${name}.js`] = removeRelativePathPrefix(relativePath)
}

for (const [name, relativePath] of Object.entries(getCSSEntryPoints())) {
  entries[`${name}.css`] = removeRelativePathPrefix(relativePath)
}

const manifest = JSON.stringify(
  Object.entries(entries).reduce((acc, [name, filePath]) => {
    const jsFiles = ['@vite/client', filePath]
    const isBlocking = filePath.endsWith('blocking-entry.ts')

    if (standaloneEntryFiles.has(name)) {
      return {
        ...acc,
        // use a top-level path for the entry point, which will then be redirected to the actual file path
        [name]: {
          src: name,
          blocking: isBlocking || undefined,
        },
      }
    }

    return {
      ...acc,
      [name]: {
        src: filePath,
        files: name.endsWith('.js') ? jsFiles : undefined, // css does not have additional files
        blocking: isBlocking || undefined,
      },
    }
  }, {}),
  null,
  2,
)

export function dotcomEntryPlugin(): PluginOption {
  return {
    name: 'dotcom-entry-plugin',

    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        // Serve the manifest file when requested
        if (req.url === '/vite/manifest.vite.json') {
          res.setHeader('Content-Type', 'application/json')
          res.end(manifest)
          return
        }

        const fileName = req.url?.replace(/^\/vite\//, '')
        if (fileName && standaloneEntryFiles.has(fileName)) {
          // Redirect standalone entries to the actual file path
          const actualPath = entries[fileName]
          res
            .writeHead(307, {
              Location: actualPath,
            })
            .end()
          return
        }

        // Otherwise let Vite handle the request
        next()
      })
    },

    config() {
      return {
        build: {
          rollupOptions: {
            input: Object.values(entries), // Override the input with all entry points
          },
        },
      }
    },
  }
}
