const path = require('path')
const expect = require('expect.js')
const root = path.join(__dirname, '/../')
const Package = require(path.join(root, 'lib/package'))
const stubs = require('./stub_data')
const pkg = stubs.validPackage

describe('Package', () => {
  it('has attributes', () => {
    expect(pkg.seq).to.equal(10)
    expect(pkg.name).to.equal('left-pad')
    expect(pkg.scope).to.be(undefined)
    expect(pkg.description).to.equal('String left pad')
    expect(pkg.sourceUrl).to.equal('git://github.com/stevemao/left-pad.git')
    expect(pkg.homeUrl).to.equal('http://left-pad.com')
  })

  it('has releases', () => {
    expect(pkg.releases.length).to.equal(1)

    const release = pkg.releases[0]
    expect(release.packageName).to.equal('left-pad')
    expect(release.version).to.equal('1.1.3')
    expect(release.authors).to.equal('azer')
    expect(release.description).to.equal('String left pad')
    expect(release.sourceUrl).to.equal('git://github.com/stevemao/left-pad.git')
    expect(release.homeUrl).to.equal('http://left-pad.com')
    expect(release.publishedAt).to.equal(1475308867)
  })

  it('has dependencies', () => {
    const release = new Package({
      name: '@github/left-pad',
      time: {},
      versions: {
        '1.1.3': {
          name: 'left-pad',
          dependencies: {
            ids: '^0.2.0'
          },
          devDependencies: {
            sinon: '~1.14.1'
          }
        }
      }
    }).releases[0]

    expect(release.dependencies.length).to.equal(2)

    expect(release.dependencies[0].packageName).to.eql('ids')
    expect(release.dependencies[0].requirements).to.eql('^0.2.0')
    expect(release.dependencies[0].scope).to.eql('runtime')

    expect(release.dependencies[1].packageName).to.eql('sinon')
    expect(release.dependencies[1].requirements).to.eql('~1.14.1')
    expect(release.dependencies[1].scope).to.eql('development')
  })

  it('handles repository URL shorthand', () => {
    let release = new Package({
      name: 'github/left-pad',
      time: {},
      repository: "https://github.com/stevemao/left-pad"
    })

    expect(release.sourceUrl).to.eql("https://github.com/stevemao/left-pad")

    release = new Package({
      name: 'github/left-pad',
      time: {},
      repository: "stevemao/left-pad"
    })

    expect(release.sourceUrl).to.eql("https://github.com/stevemao/left-pad")

    release = new Package({
      name: 'github/left-pad',
      time: {},
      repository: "bitbucket:stevemao/left-pad"
    })

    expect(release.sourceUrl).to.be.undefined
  })

  it('ignores misstructured repository URLs', () => {
    const release = new Package({
      name: 'github/left-pad',
      time: {},
      repository: {
        type: 'git',
        url: {
          type: 'git',
          url: 'https://github.com/stevemao/left-pad'
        }
      }
    })

    expect(release.sourceUrl).to.be.undefined
  })

  it('handles {release: x} dependency formats', () => {
    const release = new Package({
      name: '@github/left-pad',
      time: {},
      versions: {
        '1.1.3': {
          name: 'left-pad',
          dependencies: {
            ids: null
          },
          devDependencies: {
            sinon: {version: '~1.14.1'}
          }
        }
      }
    }).releases[0]

    expect(release.dependencies.length).to.equal(2)

    expect(release.dependencies[0].packageName).to.eql('ids')
    expect(release.dependencies[0].requirements).to.eql('')
    expect(release.dependencies[0].scope).to.eql('runtime')

    expect(release.dependencies[1].packageName).to.eql('sinon')
    expect(release.dependencies[1].requirements).to.eql('~1.14.1')
    expect(release.dependencies[1].scope).to.eql('development')
  })

  it('handles package scopes', () => {
    const pkg = new Package({
      name: '@github/left-pad',
      time: {},
      versions: {
        '1.1.3': {
          name: 'left-pad'
        }
      }
    })

    expect(pkg.name).to.equal('@github/left-pad')
    expect(pkg.scope).to.equal('github')
    expect(pkg.releases[0].packageScope).to.equal('github')
  })

  it('handles timestamps on releases', () => {
    const pkg = new Package({
      name: '@github/left-pad',
      time: null,
      versions: {
        '0.1.0': {
          name: 'left-pad',
          ctime: '2010-11-09T23:37:07Z'
        }
      }
    })

    expect(pkg.name).to.equal('@github/left-pad')
    expect(pkg.scope).to.equal('github')
    expect(pkg.releases[0].packageScope).to.equal('github')
    expect(pkg.releases[0].publishedAt).to.equal(1289345827)
  })

  it('handles [String] homepage URLs', () => {
    const pkg = new Package({
      name: '@github/left-pad',
      time: {},
      homepage: ['http://left-pad.io'],
      versions: {
        '0.1.0': {
          name: 'left-pad'
        }
      }
    })

    expect(pkg.releases[0].homeUrl).to.equal('http://left-pad.io')
  })

  it('identifies malformed releases', () => {
    const wellFormed = pkg.releases[0]
    const malformed = new Package({
      name: 'left-pad',
      time: {},
      homepage: ['http://left-pad.io'],
      versions: {
        '0.1.0': {
          name: 'left-pad'
        }
      }
    }).releases[0]

    expect(wellFormed.isMalformed()).to.not.be.ok()
    expect(malformed.isMalformed()).to.be.ok()
  })
})
