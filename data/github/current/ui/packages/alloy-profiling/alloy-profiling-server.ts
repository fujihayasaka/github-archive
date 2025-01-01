import {createServer, type ServerResponse} from 'http'
import {readFile} from 'node:fs/promises'
import {createReadStream} from 'node:fs'
import path from 'node:path'

function getFilePath(relativePath: string) {
  return import.meta.resolve(relativePath).replace('file://', '')
}

async function getAlloyFileName() {
  // Read the manifest from public/assets, which has the hashed file name for the alloy bundle
  const publicDirectory = getFilePath('../../../public/assets')
  const manifestContent = await readFile(`${publicDirectory}/manifest.alloy.json`, 'utf-8')
  const manifest = JSON.parse(manifestContent)
  return path.join(publicDirectory, manifest.entries.alloy)
}

function sendFile(filePath: string, contentType: string, res: ServerResponse) {
  const stream = createReadStream(filePath)
  res.setHeader('Content-Type', contentType)
  stream.pipe(res).on('error', error => console.error(error))
}

const server = createServer(async (req, res) => {
  const url = req.url

  try {
    if (url === '/alloy.js') {
      sendFile(await getAlloyFileName(), 'application/javascript', res)
    } else if (url === '/alloy-profiling-client.js') {
      sendFile(getFilePath('./alloy-profiling-client.js'), 'application/javascript', res)
    } else if (url === '/' && req.headers.accept?.includes('text/html')) {
      sendFile(getFilePath('./index.html'), 'text/html', res)
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

// Listen on port 9101
server.listen(9101, () => {
  console.log('Alloy profiling server started on http://localhost:9101')
})
