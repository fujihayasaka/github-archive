const Sink = require('./lib/sink')
const ChangesStream = require('changes-stream')
const Checkpoint = require('./lib/checkpoint')
const toPackage = require('./lib/package_transform')
const log = require('./lib/logger')
const sinkProxyUrl = process.env.SINK_PROXY_URL || "http://localhost:7777"
const db = 'https://replicate.npmjs.com/registry'
const checkpoint = new Checkpoint(sinkProxyUrl)
const undici = require('undici')

const extract = () => {
  checkpoint.get()
    .then((offset) => {
      const changes = new ChangesStream({
        db: db,
        include_docs: false,
        since: offset
      })
      const sink = Sink.packageReleases({
        url: sinkProxyUrl
      })

      log(`Starting at offset ${offset}`)

      changes
        .pipe(toPackage)
        .pipe(sink)
        .on('data', updateOffset)
        .on('error', onError)
    }).catch(onError)
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

const onError = (error) => {
  console.error(error)
  reportError(error)
    .finally(() => {
      process.exit(1)
    })
}

const updateOffset = (pkg) => {
  checkpoint.set(pkg.seq).catch(onError)
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
(async () => { await extract() })();
