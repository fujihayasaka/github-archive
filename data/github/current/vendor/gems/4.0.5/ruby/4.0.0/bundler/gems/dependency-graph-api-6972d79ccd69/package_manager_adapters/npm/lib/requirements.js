// Multiple requirements are separated by '||'
const OR_BOUNDARY = /\s+\|\|\s+/
// Compound requirements are separated by whitespace
const REQUIREMENT_BOUNDARY = /\s+(?=[><~^=])/
// e.g. "2.3.0 - 2.4.0"
const RANGE = /^[\d.]+\s*-/
const WILDCARD = '*'
// e.g. "2.1.x"
const EMBEDDED_WILDCARD = /^[\d.]+\.x/
// e.g. "2.1.0"
const NO_OPERATOR = /^\d/
const LATEST = /^latest|beta|[x.]+$/

// Normalizes requirements to the dependency graph standard serialization
// format. This entails:
// - Replacing '*' with ''
// - Replacing space-separated compound requirements with comma-separated
//   compound requirements
// - Prefixing '=' when an operator is omitted
// - Prefixing '~>' when an the patch is 'x' e.g. '1.2.x'
module.exports = class Requirements {
  constructor (requirements) {
    this.requirements = requirements.trim()
  }

  normalize () {
    if (this.requirements === WILDCARD) return ''

    return this.requirements
      .split(OR_BOUNDARY)
      .map(this.normalizeRange.bind(this))
      .join(' || ')
  }

  normalizeRange (range) {
    return range.trim().split(REQUIREMENT_BOUNDARY)
      .map(this.normalizeRequirement)
      .join(',')
  }

  normalizeRequirement (requirement) {
    requirement = requirement.replace(/v(?=\d)/, '')

    if (requirement.match(RANGE)) {
      const [lower, upper] = requirement.split(/\s*-\s*/)
      return `>= ${lower},<= ${upper}`
    }

    if (requirement.match(EMBEDDED_WILDCARD)) {
      return `~> ${requirement.replace('x', '0')}`
    }

    if (requirement.match(NO_OPERATOR)) {
      return `= ${requirement}`
    }

    if (requirement.toLowerCase().match(LATEST)) {
      return ''
    }

    return requirement
  }
}
