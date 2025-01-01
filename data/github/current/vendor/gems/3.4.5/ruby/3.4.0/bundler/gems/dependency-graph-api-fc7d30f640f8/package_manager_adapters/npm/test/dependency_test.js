const path = require('path')
const root = path.join(__dirname, '/../')
const expect = require('expect.js')
const Dependency = require(path.join(root, 'lib/dependency'))

describe('Dependency', () => {
  it('is well-formed when a string', () => {
    let dependency = new Dependency({
      packageName: 'ids',
      requirements: '^0.1.0'
    })

    expect(dependency.isMalformed()).to.not.be.ok()

    dependency = new Dependency({
      packageName: 'ids'
    })

    expect(dependency.isMalformed()).to.not.be.ok()
  })

  it('is malformed when not a string', () => {
    let dependency = new Dependency({
      packageName: 'ids',
      requirements: {}
    })

    expect(dependency.isMalformed()).to.be.ok()
  })

  it('handles multiple requirements', () => {
    const dependency = new Dependency({
      packageName: 'ids',
      requirements: ' ^0.1.0 < 0.1.3 || ~0.2.0'
    })

    expect(dependency.requirements).to.equal('^0.1.0,< 0.1.3 || ~0.2.0')
  })

  it('fills in missing "=" operators', () => {
    const dependency = new Dependency({
      packageName: 'ids',
      requirements: '0.1.0'
    })

    expect(dependency.requirements).to.equal('= 0.1.0')
  })

  it('normalizes ranges', () => {
    const dependency = new Dependency({
      packageName: 'ids',
      requirements: '0.1.0 - 0.2.0'
    })

    expect(dependency.requirements).to.equal('>= 0.1.0,<= 0.2.0')
  })

  it('fills in missing "~>" operators', () => {
    let dependency = new Dependency({
      packageName: 'ids',
      requirements: '0.1.x || 1.1.x'
    })

    expect(dependency.requirements).to.equal('~> 0.1.0 || ~> 1.1.0')

    dependency = new Dependency({
      packageName: 'ids',
      requirements: '0.x || 1.x'
    })

    expect(dependency.requirements).to.equal('~> 0.0 || ~> 1.0')
  })

  it('strips leading "v"s', () => {
    let dependency = new Dependency({
      packageName: 'ids',
      requirements: '> v0.1.1 || v0.1.x || v1.x'
    })

    expect(dependency.requirements).to.equal('> 0.1.1 || ~> 0.1.0 || ~> 1.0')
  })

  it('identifies HTTP URLs', () => {
    const dependency = new Dependency({
      packageName: 'ids',
      requirements: 'https://github.com/bpmn-io/ids/archive/v0.2.0.tar.gz'
    })

    expect(dependency.isHttpUrl()).to.be.ok()
    expect(dependency.httpUrl).to.equal('https://github.com/bpmn-io/ids/archive/v0.2.0.tar.gz')
  })

  it('identifies git URLs', () => {
    let dependency = new Dependency({
      packageName: 'ids',
      requirements: 'git+ssh://git@github.com:bpmn-io/ids.git'
    })

    expect(dependency.isGitRemote()).to.be.ok()
    expect(dependency.git).to.equal('git@github.com:bpmn-io/ids.git')
    expect(dependency.hasRef()).to.not.be.ok()
    expect(dependency.ref).to.equal(undefined)

    dependency = new Dependency({
      packageName: 'ids',
      requirements: 'git+ssh://git@github.com:bpmn-io/ids.git#v0.2.0'
    })

    expect(dependency.isGitRemote()).to.be.ok()
    expect(dependency.git).to.equal('git@github.com:bpmn-io/ids.git')
    expect(dependency.hasRef()).to.be.ok()
    expect(dependency.ref).to.equal('v0.2.0')
  })

  it('handles invalid git URLs', () => {
    let dependency = new Dependency({
      packageName: 'ids',
      requirements: 'git+ssh://git@github.com'
    })

    expect(dependency.isGitRemote()).to.not.be.ok()
  })

  it('identifies GitHub repos', () => {
    let dependency = new Dependency({
      packageName: 'ids',
      requirements: 'bpmn-io/ids/archive'
    })

    expect(dependency.isGitHubRepo()).to.be.ok()
    expect(dependency.githubRepo).to.equal('bpmn-io/ids/archive')
    expect(dependency.hasRef()).to.not.be.ok()
    expect(dependency.ref).to.equal(undefined)

    dependency = new Dependency({
      packageName: 'ids',
      requirements: 'bpmn-io/ids/archive#master'
    })

    expect(dependency.isGitHubRepo()).to.be.ok()
    expect(dependency.githubRepo).to.equal('bpmn-io/ids/archive')
    expect(dependency.hasRef()).to.be.ok()
    expect(dependency.ref).to.equal('master')
  })

  it('identifies local paths', () => {
    const dependency = new Dependency({
      packageName: 'ids',
      requirements: '~/projects/bpmn-io/ids'
    })

    expect(dependency.isPath()).to.be.ok()
    expect(dependency.path).to.equal('~/projects/bpmn-io/ids')
  })

  it('identifies wildcards', () => {
    const dependency = new Dependency({
      packageName: 'ids',
      requirements: '* '
    })

    expect(dependency.requirements).to.equal('')
  })

  it('treats "latest", "beta" and "x.x" as wildcards', () => {
    let dependency = new Dependency({
      packageName: 'ids',
      requirements: 'Latest '
    })

    expect(dependency.requirements).to.equal('')

    dependency = new Dependency({
      packageName: 'ids',
      requirements: 'beta'
    })

    expect(dependency.requirements).to.equal('')

    dependency = new Dependency({
      packageName: 'ids',
      requirements: 'x.x.x'
    })

    expect(dependency.requirements).to.equal('')

    dependency = new Dependency({
      packageName: 'ids',
      requirements: 'x.x'
    })

    expect(dependency.requirements).to.equal('')

    dependency = new Dependency({
      packageName: 'ids',
      requirements: 'x'
    })

    expect(dependency.requirements).to.equal('')
  })
})
