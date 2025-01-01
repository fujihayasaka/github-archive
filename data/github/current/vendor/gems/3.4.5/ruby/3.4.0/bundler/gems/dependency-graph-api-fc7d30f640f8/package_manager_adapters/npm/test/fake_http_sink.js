const express = require('express')
const bodyParser = require('body-parser')
const wait = require('wait-promise')

module.exports = class Server {
  constructor (options) {
    this.packageReleases = []
    this.manifests = []
    this.port = options.port
    this.errors = 0
    this.checkpoints = {}
  }

  start () {
    const app = express()

    app.use(bodyParser.urlencoded({extended: true}))

    app.post('/package_releases', (request, response) => {
      this.packageReleases.push(
        ...JSON.parse(request.body['package_releases']))

      response.status(200).send('Created!')
    })

    app.post('/errors', (request, response) => {
      this.errors += 1
      response.status(422).send('Invalid!')
    })

    app.get('/checkpoints/:checkpoint', (request, response) => {
      const checkpoint = request.params.checkpoint
      this.checkpoints[checkpoint] = this.checkpoints[checkpoint] || 0
      response.status(200).send({value: this.checkpoints[checkpoint]})
    })

    app.put('/checkpoints/:checkpoint', (request, response) => {
      const checkpoint = request.params.checkpoint
      this.checkpoints[checkpoint] = parseInt(request.body.value)
      response.status(200).send('Accepted!')
    })

    app.listen(this.port)
  }

  reset () {
    this.packageReleases = []
    this.errors = 0
    this.checkpoints = {}
  }

  waitForPackageReleases (n) {
    return wait.until(() => {
      return this.packageReleases.length >= n
    })
  }

  waitForErrors (n) {
    return wait.until(() => {
      return this.errors >= n
    })
  }

  sortedPackageReleases () {
    const compare = (left, right) => {
      if (left.package_name < right.package_name) return -1
      if (left.package_name > right.package_name) return 1
      return 0
    }

    return this.packageReleases.sort(compare)
  }
}
