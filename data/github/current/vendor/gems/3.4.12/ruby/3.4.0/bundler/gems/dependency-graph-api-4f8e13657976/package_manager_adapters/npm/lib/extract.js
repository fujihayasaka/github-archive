const fetchChanges = require('./fetchchanges')
const Checkpoint = require('./checkpoint')
const Sink = require('./sink')
const PackageTransformer = require('./package_transform')
const {Readable} = require('node:stream')
const {pipeline} = require('node:stream/promises')
const log = require('./logger')

module.exports = async (url, sinkProxyUrl, packageMetadataAPI) => {
  const checkpoint = new Checkpoint(sinkProxyUrl)
  const toPackage = new PackageTransformer(packageMetadataAPI, {})

  const since = await checkpoint.get()
  const result = await fetchChanges(url, since)

  const sink = Sink.packageReleases({
    url: sinkProxyUrl
  })

  log(`Starting at offset ${since}`)

  await pipeline(
    Readable.from(result.results),
    toPackage,
    sink,
    async (pkg) => {
      if (pkg && pkg.seq) {
        await checkpoint.set(pkg.seq)
      }
    }
  );
  if (result.last_seq) {
    log(`Storing last sequence number: ${result.last_seq}`)
    await checkpoint.set(result.last_seq)
  }
}
