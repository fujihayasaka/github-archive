
const undici = require('undici')
const stream = require('stream')

const params = {
  dependency: (dep) => {
    if (dep.isMalformed()) {
      console.error('Bad dependency: ', dep)
      return
    }

    let json = {
      package_name: dep.packageName,
      scope: dep.scope
    }

    if (dep.isGitRemote()) {
      json.git = dep.git
      if (dep.hasRef()) json.ref = dep.ref
    } else if (dep.isHttpUrl()) {
      json.url = dep.httpUrl
    } else if (dep.isPath()) {
      json.path = dep.path
    } else if (dep.isGitHubRepo()) {
      json.github = dep.githubRepo
      if (dep.hasRef()) json.ref = dep.ref
    } else {
      json.requirements = dep.requirements
    }

    return json
  },

  packageRelease: (release) => {
    if (release.isMalformed()) {
      console.error('Bad release: ', release)
      return
    }

    return {
      package_manager: 'npm',
      external_id: release.externalId,
      package_name: release.packageName,
      namespace: release.packageScope,
      version: release.version,
      license: release.license,
      description: release.description,
      authors: release.authors,
      source_url: release.sourceUrl,
      home_url: release.homeUrl,
      published_at: release.publishedAt,
      dependencies: release.dependencies.map(params.dependency).filter((i) => i)
    }
  },

  packageReleases: (pkg) => {
    return pkg.releases.map(params.packageRelease).filter((i) => i)
  }
}

class ServerError extends Error {
  constructor (error, status) {
    super('Server error: ' + error)
    this.status = status
    this.error = error
  }
}

class Sink extends stream.Duplex {
  constructor (options) {
    options.objectMode = true
    super(options)

    this.endpoint = options.endpoint
    this.stack = []
  }

  // No-op for duplex stream API compliance. _write does all the pushing.
  _read () { }

  _write (entity, en, callback) {
    this.post(params.packageReleases(entity))
      .then(() => { this.push(entity) })
      .then(() => { callback() })
      .catch((error) => { callback(error) })
  }

  async post (data) {
    const response = await undici.fetch(this.endpoint, {
      method: "POST",
      body: new URLSearchParams({
        "package_releases": JSON.stringify(data)
      })
    });
    if (response.status !== 200) {
      const body = await response.text();
      throw new ServerError(body, response.status)
    }
  }
}

Sink.packageReleases = (options) => {
  const url = options.url
  const endpoint = options.endpoint || `${url}/package_releases`

  return new Sink({
    endpoint
  })
}

module.exports = Sink
module.exports.params = params
