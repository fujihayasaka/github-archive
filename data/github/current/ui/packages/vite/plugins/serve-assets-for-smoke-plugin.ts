import fs from 'fs/promises'
import path from 'path'
import {send, type PluginOption} from 'vite'

const assetsDir = '/tmp/smoke-test-assets'

export function serveAssetsForSmokePlugin(): PluginOption {
  return {
    name: 'serve-assets-for-smoke-plugin',
    configureServer(server) {
      server.middlewares.use(async (req, res, next) => {
        if (req.url?.startsWith(assetsDir)) {
          try {
            const filePath = path.join(assetsDir, path.relative(assetsDir, path.resolve(req.url)))
            const content = await fs.readFile(filePath)
            const ext = path.extname(filePath).slice(1)

            send(req, res, content, ext, {})
          } catch {
            next()
          }
        } else {
          next()
        }
      })
    },
  }
}
