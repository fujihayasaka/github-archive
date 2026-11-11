const undici = require('undici')

const log = require('./lib/logger')
const extract = require('./lib/extract')

const url = 'https://replicate.npmjs.com/registry/_changes'
const sinkProxyUrl = process.env.SINK_PROXY_URL || "http://localhost:7777"
const packageMetadataAPI = 'https://registry.npmjs.org/'

async function runExtract() {
  try {
    await extract(url, sinkProxyUrl, packageMetadataAPI)
    log("Extraction completed successfully.")
  } catch (error) {
    log(`Error during npm extraction: ${error}`)
    reportError(error)
      .finally(() => {
        process.exit(1)
      })
  }
}


reportError = (error) => {
  return undici.fetch(`${sinkProxyUrl}/errors`, {
    method: 'POST',
    body: new URLSearchParams({
      message: error.message,
      backtrace: error.stack
    })
  })
}


const shutdown = () => {
  log("Exiting...")
  process.exit(0)
}

process.on('SIGTERM', shutdown)
process.on('SIGINT', shutdown);

// This is not yet legal code:
//   await extract()
// See https://techsparx.com/nodejs/async/top-level-async.html
(async () => { await runExtract() })();
