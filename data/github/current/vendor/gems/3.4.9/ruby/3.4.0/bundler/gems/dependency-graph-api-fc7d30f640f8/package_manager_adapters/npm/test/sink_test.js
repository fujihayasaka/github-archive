const path = require('path')
const root = path.join(__dirname, '/../')
const expect = require('expect.js')
const stream = require('stream')
const Server = require('./fake_http_sink')
const stubs = require('./stub_data')
const Sink = require(path.join(root, 'lib/sink'))
const params = require(path.join(root, 'lib/sink')).params
const Dependency = require(path.join(root, 'lib/dependency'))
const server = new Server({port: 5555})

const packageSink = Sink.packageReleases({url: 'http://localhost:5555'})

describe('Sink', () => {
  before(() => server.start())
  beforeEach(() => server.reset())

  describe('POSTing packages', () => {
    it('POSTs packages to the endpoint', (done) => {
      const packages = createStream(stubs.validPackage)

      packages.pipe(packageSink)

      server.waitForPackageReleases(1)
        .then(() => {
          expect(server.packageReleases).to.eql([
            {
              package_manager: 'npm',
              external_id: 'left-pad',
              package_name: 'left-pad',
              version: '1.1.3',
              license: 'MIT OR Apache-2.0',
              description: 'String left pad',
              authors: 'azer',
              source_url: 'git://github.com/stevemao/left-pad.git',
              home_url: 'http://left-pad.com',
              published_at: 1475308867,
              dependencies: [
                {package_name: 'ids', requirements: '^0.2.0', scope: 'runtime'},
                {package_name: 'inherits', requirements: '^2.0.1', scope: 'runtime'},
                {package_name: 'lodash', requirements: '^3.0.1', scope: 'runtime'},
                {package_name: 'sinon', requirements: '~1.14.1', scope: 'development'},
                {package_name: 'sinon-chai', requirements: '~2.7.0', scope: 'development'}
              ]
            }
          ])
        })
        .then(done)
        .catch(done)
    })

    it('outputs POSTed packages', (done) => {
      const packages = createStream(stubs.validPackage)

      packages.pipe(packageSink).on('data', (actual) => {
        expect(stubs.validPackage).to.eql(actual)
      })
      server.waitForPackageReleases(1)
        .then(() => { done() })
        .catch(done)
    })

    it('throws errors if a POST fails', (done) => {
      let lastError;
      let onError = (error) => {
        onError.called = true
        lastError = error;
        return error
      }
      const packageSink = Sink.packageReleases({endpoint: 'http://localhost:5555/errors'})
      const packages = createStream(stubs.invalidPackage)

      packages
        .pipe(packageSink)
        .on('error', (error) => {
          expect(error.message).to.be("Server error: Invalid!")
          done();
        })
    })
  })

  describe('parameteriziation', () => {
    it('parameterizes dependencies with requirements', () => {
      const dependency = new Dependency({
        packageName: 'ids',
        scope: 'runtime',
        requirements: '0.1.0'
      })

      expect(params.dependency(dependency)).to.eql({
        package_name: 'ids',
        scope: 'runtime',
        requirements: '= 0.1.0'
      })
    })

    it('parameterizes dependencies with HTTP URL requirements', () => {
      const dependency = new Dependency({
        packageName: 'ids',
        scope: 'runtime',
        requirements: 'https://github.com/bpmn-io/ids/archive/v0.2.0.tar.gz'
      })

      expect(params.dependency(dependency)).to.eql({
        package_name: 'ids',
        scope: 'runtime',
        url: 'https://github.com/bpmn-io/ids/archive/v0.2.0.tar.gz'
      })
    })

    it('parameterizes dependencies with git URL requirements', () => {
      const dependency = new Dependency({
        packageName: 'ids',
        scope: 'runtime',
        requirements: 'git+ssh://git@github.com:bpmn-io/ids.git#v0.2.0'
      })

      expect(params.dependency(dependency)).to.eql({
        package_name: 'ids',
        scope: 'runtime',
        git: 'git@github.com:bpmn-io/ids.git',
        ref: 'v0.2.0'
      })
    })

    it('parameterizes dependencies with GitHub repo requirements', () => {
      const dependency = new Dependency({
        packageName: 'ids',
        scope: 'runtime',
        requirements: 'bpmn-io/ids/archive#master'
      })

      expect(params.dependency(dependency)).to.eql({
        package_name: 'ids',
        scope: 'runtime',
        github: 'bpmn-io/ids/archive',
        ref: 'master'
      })
    })

    it('parameterizes dependencies with file path requirements', () => {
      const dependency = new Dependency({
        packageName: 'ids',
        scope: 'runtime',
        requirements: '/projects/bpmn-io/ids'
      })

      expect(params.dependency(dependency)).to.eql({
        package_name: 'ids',
        scope: 'runtime',
        path: '/projects/bpmn-io/ids'
      })
    })
  })

  const createStream = (record) => {
    const readStream = new stream.Readable({
      objectMode: true,
      read () { }
    })
    readStream.push(record)
    return readStream
  }
})
