const express = require('express')
const bodyParser = require('body-parser')
const wait = require('wait-promise')

const registryData = require('./fake_registry_data')
const log = require('../lib/logger')

module.exports = class Server {
  constructor (options) {
    // results is a map of checkpoints to result objects
    this.results = {}
    this.port = options.port
  }

  start () {
    const app = express()

    app.use(bodyParser.urlencoded({extended: true, limit: '10mb'}))

    // This is simulating https://replicate.npmjs.com/registry/_changes
    app.get('/registry/_changes', (request, response) => {
      // This header is required until May 29, 2025.
      if (request.headers['npm-replication-opt-in'] !== 'true') {
        response.status(401).send('Unauthorized')
        return
      }
      let since = request.query.since
      if (since === undefined) {
        since = ''
      }
      log(`Fetching changes since ${since}`)
      const data = this.results[since]
      if (data === undefined) {
        log(`No data for checkpoint ${since}`)
        response.status(404).send('Not Found')
        return
      }
      log(`Found ${data.results.length} entries`)
      response.status(200).send(data)
    })

    // This is simulating https://registry.npmjs.com/<package>
    app.get('/:package', (request, response) => {
      const packageName = request.params.package
      log(`Fetching package metadata for ${packageName}`)
      const data = registryData[packageName]
      if (data === undefined) {
        log(`No data for package ${packageName}`)
        response.status(404).send('Not Found')
        return
      }
      log(`Found package metadata for ${packageName}`)
      response.status(200).send(data)
    })

    app.listen(this.port)
  }

  // Entries are shaped like this:
  // {"seq":41336897,"id":"@nav-matrix/ui-components","changes":[{"rev":"61-29253bcc4c2e86cf5722a540fa50c076"}]},
  addResult (checkpoint, entries) {
    // Next checkpoint is the seq number of the last entry
    const nextCheckpoint = entries[entries.length - 1].seq
    // Add the entries to the results map
    this.results[checkpoint] = {
      results: entries,
      last_seq: nextCheckpoint
    }
  }

  reset () {
    this.results = {}
  }
}
