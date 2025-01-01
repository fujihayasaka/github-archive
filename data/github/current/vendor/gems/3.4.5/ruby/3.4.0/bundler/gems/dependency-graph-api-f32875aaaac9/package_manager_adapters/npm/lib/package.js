const Url = require('url')
const Dependency = require('./dependency')
const PackageRelease = require('./package_release')

const REPOSITORY_SHORTHAND = /^[\w-]+\/[\w-]+$/

// DAO for raw couchDB records
module.exports = class Package {
  constructor (attributes, seq) {
    this.seq = seq
    this.externalId = attributes._id
    this.fullName = attributes.name
    this.description = attributes.description || ''
    this.repository = attributes.repository || {}
    this.homepage = attributes.homepage
    this.time = attributes.time || {}
    this.versions = attributes.versions || {}

    // The only key here that is of unbounded size is readme, and we don't need it.
    Object.keys(this.versions).forEach((version) => {
      delete this.versions[version].readme
    })
  }

  get name () {
    return this.components[0]
  }

  get scope () {
    return this.components[this.components.length - 2]
  }

  get sourceUrl () {
    if (typeof this.repository === "string") {
      return REPOSITORY_SHORTHAND.test(this.repository) ?
        `https://github.com/${this.repository}` : this.repository
    } else if (typeof this.repository.url === "string") {
      return this.repository.url
    } else {
      return null
    }
  }

  get homeUrl () {
    if (Array.isArray(this.homepage)) {
      return this.homepage[0]
    } else {
      return this.homepage && (this.homepage.url || this.homepage)
    }
  }

  get components () {
    if (!this.fullName) return []

    const match = this.fullName.match(/^(?:@([^/]+)\/)?([^/]+)$/)
    return match ? [match[0], match[1], match[2]] : [this.fullName]
  }

  get releases () {
    return Object.keys(this.versions).map((version) => {
      return new PackageRelease(
        this,
        Object.assign(
          this.versions[version],
          {
            publishedAt: this.time[version]
          }
        )
      )
    })
  }
}
