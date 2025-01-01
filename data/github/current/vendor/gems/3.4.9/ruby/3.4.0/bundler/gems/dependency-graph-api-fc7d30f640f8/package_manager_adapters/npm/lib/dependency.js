const Url = require('url')
const Requirements = require('./requirements')

// Various non-standard requirement flavors
const GIT_REMOTE = /^(git|ssh).*:/
const FILE_PATH = /^(\.{1,2}|~)?\//
const GITHUB_REPO = /[\w-]+\/[\w-]+/

module.exports = class Dependency {
  constructor (attributes) {
    this.packageName = attributes.packageName
    this.scope = attributes.scope
    this.rawRequirements = attributes.requirements || ''

    if (this.rawRequirements && this.rawRequirements.version) {
      this.rawRequirements = this.rawRequirements.version
    }

    if (this.rawRequirements && typeof this.rawRequirements === 'string') {
      this.url = Url.parse(this.rawRequirements)
    }
  }

  isMalformed () {
    return !(typeof this.rawRequirements === 'string')
  }

  get requirements () {
    return new Requirements(this.rawRequirements).normalize()
  }

  isHttpUrl () {
    if (!this.url) return false

    return ['http:', 'https:'].includes(this.url.protocol)
  }

  get httpUrl () {
    return Url.format(this.url)
  }

  isGitRemote () {
    if (!this.url) return false

    return GIT_REMOTE.test(this.url.protocol) && this.url.path
  }

  get git () {
    const repo = this.url.path.replace(/^\/:?/, ':')

    return `${this.url.auth}@${this.url.host}${repo}`
  }

  hasRef () {
    return !!this.ref
  }

  get ref () {
    return this.rawRequirements.split('#')[1]
  }

  isPath () {
    return this.rawRequirements.match(FILE_PATH)
  }

  get path () {
    return this.url.path
  }

  isGitHubRepo () {
    return this.rawRequirements.match(GITHUB_REPO)
  }

  get githubRepo () {
    return this.rawRequirements.split('#')[0]
  }
}
