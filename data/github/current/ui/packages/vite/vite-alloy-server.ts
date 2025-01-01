import {createServer as createViteServer} from 'vite'
import {cjsInterop} from 'vite-plugin-cjs-interop'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'
import {getSSREntryPoints} from '@github-ui/client-build-tools/entry-points'
import {createServer as createHttpServer, type IncomingMessage} from 'http'
import {injectCssModuleLinks} from './plugins/alloy-plugin.ts'
import ssrShims from '@github-ui/ssr-shims'
import {formatError} from '@github-ui/error-serialization'
import {getAlloyDefinePluginConfig} from '@github-ui/client-build-plugins/define'

const alloyEntryPath = '@github-ui/alloy-entry'
const commonJsDependencies = [
  /**
   * These commonjs dependencies are imported as if they were esm, which causes default imports to fail.
   * This plugin allows us to auto-fix the imports, but we need to keep a list of all impacted modules.
   */
  'styled-components',
  '@styled-system/css',
  'react-relay',
  'react-relay/*',
  'relay-runtime',
  'chart.js',
  '@primer/react-brand',
  '@contentful/rich-text-types',
]
const vite = await createViteServer({
  cacheDir: fullPathFromRoot('node_modules/.vite/alloy-deps/'),
  plugins: [cjsInterop({dependencies: commonJsDependencies})],
  server: {
    middlewareMode: true, // Required, otherwise css modules break on some pages
  },
  ssr: {
    // Ensure @primer/react gets transformed by Vite, allowing us to patch CSS Module behavior
    noExternal: ['@primer/react'],
  },
  resolve: {
    // Apply ssr shims, like we do for Alloy in Webpack
    alias: ssrShims.ssrShimFileMap,
  },
  define: getAlloyDefinePluginConfig({bundler: 'vite-alloy'}),
  appType: 'custom',
  configFile: fullPathFromRoot('ui/packages/vite/vite.config.ts'),
})
const commonJsErrorRegex = /'([^']*)' is a CommonJS module/

function parseBodyAsJSON(req: IncomingMessage) {
  return new Promise((resolve, reject) => {
    let data = ''
    req.on('data', (chunk: Buffer) => {
      data += chunk
    })
    req.on('end', () => {
      try {
        resolve(JSON.parse(data))
      } catch (error) {
        reject(error)
      }
    })
    req.on('error', reject)
  })
}

const server = createHttpServer(async (req, res) => {
  const url = req.url

  try {
    if (url === '/render' && req.method === 'POST') {
      const start = performance.now()
      const {arg} = (await parseBodyAsJSON(req)) as {arg: {name: string}}
      console.log(`Rendering ${arg.name}`)
      const {registerHandlerAsync} = await vite.ssrLoadModule(alloyEntryPath)
      const handler = await registerHandlerAsync(arg.name)
      const content = await handler(arg)
      const contentWithLinks = injectCssModuleLinks(content)

      console.log(`Rendered ${arg.name} in ${performance.now() - start} ms`)

      res.writeHead(200, {'Content-Type': 'text/html'})
      res.write(contentWithLinks)
      res.end()
    } else {
      res.writeHead(404, {'Content-Type': 'text/plain'})
      res.write('Not found')
      res.end()
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } catch (initialError: any) {
    let error = initialError
    if ('message' in error && commonJsErrorRegex.test(error.message)) {
      const match = error.message?.match(commonJsErrorRegex)
      error = new Error(
        `The package "${match[1]}" is a CommonJS module. Please add it to the "commonJsDependencies" array in ui/packages/vite/vite-alloy-server.ts`,
      )
    }

    res.writeHead(500, {'Content-Type': 'text/plain'})
    if (error instanceof Error) {
      res.write(JSON.stringify(formatError(error)))
    } else {
      res.write('Unknown error occurred. See server console for more information.')
    }
    res.end()
    console.error(error)
  }
})

// eslint-disable-next-line unused-imports/no-unused-vars
async function warmAllEntries() {
  const entryPoints = getSSREntryPoints()
  const {registerHandlerAsync} = await vite.ssrLoadModule(alloyEntryPath)

  await Promise.all(
    Object.keys(entryPoints).map(async name => {
      await registerHandlerAsync(name)
      console.log(`Warmed entry point: ${name}`)
    }),
  )
  console.log('All entry points warmed successfully')
}

// Listen on port 9100
server.listen(9100, () => {
  console.log('Vite Alloy server started on http://localhost:9100')

  // If you need to confirm the ability to load all entry points, uncomment the following line
  // warmAllEntries()
})
