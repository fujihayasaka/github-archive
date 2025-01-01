import {getJSEntryPoints} from '@github-ui/client-build-tools/entry-points'
import {performance} from 'perf_hooks'
import {chromium} from 'playwright'
import {type PluginOption, createServer} from 'vite'
import viteConfig from './vite.config.ts'

const behaviorEntryPath = getJSEntryPoints().behaviors

function statsServerPlugin(): PluginOption {
  return {
    name: 'stats-server-plugin',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if (req.url === '/vite/stats') {
          const indexHtml = `
            <!DOCTYPE html>
            <head>
              <script type="module" src="@vite/client"></script>
            </head>
            <script type="module" src="${behaviorEntryPath}"></script>
          `
          res.setHeader('Content-Type', 'text/html')
          res.end(indexHtml)
          return
        }

        next()
      })
    },
  }
}

async function run() {
  const browser = await chromium.launch({headless: true})
  const context = await browser.newContext()
  const page = await context.newPage()

  const startTime = performance.now()

  const server = await createServer({
    ...viteConfig,
    plugins: [...(viteConfig.plugins || []), statsServerPlugin()],
    // Force dependency pre-optimization to imitate a fresh server start
    optimizeDeps: {
      ...viteConfig.optimizeDeps,
      force: true,
    },
  })

  server.config.logger.info = msg => {
    console.log(`[VITE] ${msg}`)
  }

  await server.listen()

  // Get the server URL http://localhost:$PORT/vite/. Navigate to the /vite/stats route.
  const url = server.resolvedUrls?.local[0]
  await page.goto(`${url}stats`)

  const endTime = performance.now()
  const timeTaken = endTime - startTime

  console.log(`[VITE] Server ready in ${timeTaken}ms`)

  await browser.close()
  await server.close()
}

;(async () => {
  try {
    await run()
  } catch (error) {
    console.error(error)
  }
})()
