import {createServer, type ServerResponse} from 'http'
import type {UIManifest} from './manifest-types.ts'
import {getBaseManifest} from './base-manifest.ts'
import {bundlerFlags} from './bundler-flags.ts'
import {readFile} from 'node:fs/promises'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'

const flaggedBundlers = bundlerFlags.map(({bundler}) => bundler)
const manifestUrls = {
  webpack: 'http://localhost:3011/manifest.json',
  css: 'http://localhost:3012/manifest.css.json',
  vite: 'http://localhost:3013/vite/manifest.vite.json',
  ...Object.fromEntries(flaggedBundlers.map(bundler => [bundler, `http://localhost:3011/manifest.${bundler}.json`])),
}

const manifestPaths = {
  alloy: 'public/assets/manifest.alloy.json',
  relay: 'public/assets/manifest.relay.json',
}

// These are  the specific combinations of bundlers which would be considered a complete set of manifests.
const requiredBundlers = [['webpack', 'css'], ...flaggedBundlers.map(bundler => [bundler, 'css']), ['vite']]

async function fetchManifest(url: string) {
  const response = await fetch(url)
  return await response.json()
}

async function readManifestFile(path: string) {
  const content = await readFile(fullPathFromRoot(path), 'utf-8')
  return JSON.parse(content)
}

/**
 * Builds the UI manifest by fetching individual manifests from the specified URLs.
 * Each manifest is included in the UI manifest based on the key in the manifestUrls object.
 */
const buildUIManifest = async () => {
  const start = Date.now()

  // Fetch manifests in parallel by URL
  const manifestFetchPromises = Object.entries(manifestUrls).map(async ([key, url]) => {
    try {
      const manifest = await fetchManifest(url)
      return [key, manifest]
    } catch {
      // Fetching the manifests may fail since not all dev servers are running at all times
      return null
    }
  })

  // Read manifests in parallel by path
  const manifestReadPromises = Object.entries(manifestPaths).map(async ([key, path]) => {
    try {
      const manifest = await readManifestFile(path)
      return [key, manifest]
    } catch {
      // Reading the manifest files may fail if the files do not exist
      return null
    }
  })

  const baseManifest = await getBaseManifest()
  const manifests = await Promise.all([...manifestFetchPromises, ...manifestReadPromises])
  const bundlerManifest = Object.fromEntries(manifests.filter(entry => entry !== null))

  if (!requiredBundlers.some(combination => combination.every(bundler => bundler in bundlerManifest))) {
    throw new Error('Bundler manifests were not available. Make sure your webpack or vite dev servers are running.')
  }

  console.log('Built UI manifest with bundlers', Object.keys(bundlerManifest), `in ${Date.now() - start} ms`)

  const uiManifest: UIManifest = {
    ...baseManifest,
    ...bundlerManifest,
  }

  return uiManifest
}

async function sendUIManifest(res: ServerResponse) {
  const uiManifest = await buildUIManifest()
  res.setHeader('Content-Type', 'application/json')
  res.write(JSON.stringify(uiManifest, null, 2))
  res.end()
}

const server = createServer(async (req, res) => {
  const url = req.url?.replace('/ui/', '/')

  try {
    if (url === '/ui-manifest.json') {
      await sendUIManifest(res)
    } else {
      res.writeHead(404, {'Content-Type': 'text/plain'})
      res.write('Not found')
      res.end()
    }
  } catch (error) {
    res.writeHead(500, {'Content-Type': 'text/plain'})
    if (error instanceof Error) {
      res.write(error.toString())
    } else {
      res.write('Unknown error occurred. See server console for more information.')
    }
    res.end()
    console.error(error)
  }
})

// Listen on port 3014
server.listen(3014, () => {
  console.log('UI asset server started on http://localhost:3014')
})
