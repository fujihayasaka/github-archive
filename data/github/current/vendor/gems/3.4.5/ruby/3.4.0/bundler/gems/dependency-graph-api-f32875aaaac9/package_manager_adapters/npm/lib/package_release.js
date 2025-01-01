const Dependency = require('./dependency')

// Before Dec 2010, there was no time object.
const PREHISTORY = '2010-12-01 00:00'

module.exports = class PackageRelease {
  constructor (pkg, attributes) {
    this.package = pkg
    this.version = attributes.version
    this.author = attributes.author || {}
    this.repository = attributes.repository || {}
    this.license = this.extractLicense(attributes)
    this.ctime = attributes.ctime
    this._publishedAt = attributes.publishedAt
    this._description = attributes.description
    this._dependencies = attributes.dependencies || {}
    this._devDependencies = attributes.devDependencies || {}
  }

  isMalformed () {
    return !(this.packageName && this.version && this.publishedAt)
  }

  get packageName () {
    return this.package.name
  }

  get packageScope () {
    return this.package.scope
  }

  get authors () {
    if (typeof this.author === 'string') {
      return this.author
    } else {
      return this.author.name
    }
  }

  get description () {
    return (this._description || this.package.description).toString()
  }

  get sourceUrl () {
    const url = this.repository.url || this.package.sourceUrl
    if (typeof url === 'string') {
      return url
    } else {
      return null
    }
  }

  get homeUrl () {
    return this.package.homeUrl
  }

  get externalId () {
    return this.package.externalId
  }

  get publishedAt () {
    const publishedAt = this._publishedAt || this.ctime || PREHISTORY

    return Math.floor(new Date(publishedAt).getTime() / 1000)
  }

  get dependencies () {
    return this.reformatDependencies('runtime', this._dependencies)
      .concat(this.reformatDependencies('development', this._devDependencies))
  }

  // see also: https://docs.npmjs.com/cli/v9/configuring-npm/package-json#license
  extractLicense(attributes) {
    // "license" value can be a string or a hash with "type" field
    if (attributes.license) {
      if (typeof attributes.license == "string") {
        return attributes.license || ""
      } else {
        return attributes.license?.type || ""
      }
    }

    // "licenses" value is an array of objects with "type" fields
    if (attributes.licenses && Array.isArray(attributes.licenses)) {
      return attributes.licenses.filter((lsc) => lsc?.type).map((lsc) => lsc.type).join(" OR ")
    }

    return ""
  }

  reformatDependencies (scope, dependencies) {
    return Object.keys(dependencies).map((key) => {
      return new Dependency({
        packageName: key,
        scope: scope,
        requirements: dependencies[key]
      })
    })
  }
}
