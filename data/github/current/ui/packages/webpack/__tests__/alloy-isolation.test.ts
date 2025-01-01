import {webpack} from 'webpack'
import path from 'node:path'
import {readFile, rm} from 'node:fs/promises'
import {Script} from 'vm'
import AlloySelectiveIsolationPlugin from '../plugins/alloy-selective-isolation'

const ssrEntries = {
  'app-1': path.resolve(__dirname, 'fixtures/app-1.js'),
  'app-2': path.resolve(__dirname, 'fixtures/app-2.js'),
  'global-on-render': path.resolve(__dirname, 'fixtures/global-on-render.js'),
}

describe('Alloy Isolation', () => {
  let script: Script
  beforeAll(async () => {
    await new Promise<void>((resolve, reject) => {
      webpack(
        {
          mode: 'production',
          entry: {
            alloy: path.resolve(__dirname, 'fixtures/alloy-entry.js'),
          },
          module: {
            rules: [
              {
                test: /alloy-entry\.js$/,
                loader: require.resolve('../loaders/alloy-entry-loader.js'),
                options: {ssrEntries},
              },
            ],
          },
          output: {
            path: path.resolve(__dirname, 'output'),
            filename: '[name].js',
            library: {
              type: 'commonjs2',
              export: 'default',
            },
          },
          plugins: [
            new AlloySelectiveIsolationPlugin({
              entryNames: Object.keys(ssrEntries),
              trustedModules: ['fixtures/trusted-dep.js'],
            }),
          ],
          optimization: {
            concatenateModules: false,
          },
        },
        function (err) {
          if (err) {
            console.error(err)
            return reject(err)
          }
          resolve()
        },
      )
    })

    const content = await readFile(path.resolve(__dirname, 'output/alloy.js'), 'utf-8')
    script = new Script(`
      const module = {};
      ${content}
      module.exports
    `)
  })

  afterAll(async () => {
    await rm(path.resolve(__dirname, 'output'), {recursive: true})
  })

  function getSetup() {
    return script.runInNewContext()
  }

  it('should isolate between multiple setup calls', () => {
    const setup = getSetup()
    const args = {
      name: 'app-1',
      data: {a: 'b'},
    }
    expect(setup()(args)).toEqual({
      name: 'app-1',
      trusted: 0,
      trustedSubDepIndirect: 0,
      untrusted: 0,
      data: args.data,
    })

    expect(setup()(args)).toEqual({
      name: 'app-1',
      trusted: 1,
      trustedSubDepIndirect: 1,
      untrusted: 0,
      data: args.data,
    })
  })

  it('should trust sub-dependencies of trusted modules', () => {
    const setup = getSetup()
    const args = {
      name: 'app-2',
    }
    expect(setup()(args)).toEqual({
      name: 'app-2',
      trustedSubDepDirect: 0,
      untrusted: 0,
    })

    expect(setup()(args)).toEqual({
      name: 'app-2',
      trustedSubDepDirect: 1,
      untrusted: 0,
    })
  })

  it('should share trusted modules between entries', () => {
    const setup = getSetup()

    // Run app-1 first to load the trusted module
    expect(setup()({name: 'app-1'})).toEqual({
      name: 'app-1',
      trusted: 0,
      trustedSubDepIndirect: 0,
      untrusted: 0,
      data: undefined,
    })

    // Run app-2, which uses the sub-dependency from the trusted module
    expect(setup()({name: 'app-2'})).toEqual({
      name: 'app-2',
      trustedSubDepDirect: 1,
      untrusted: 0,
    })
  })

  it('should share untrusted modules when setup is not called again', () => {
    const setup = getSetup()
    const sharedHandler = setup()

    expect(sharedHandler({name: 'app-1', data: 'call 1'})).toEqual({
      name: 'app-1',
      trusted: 0,
      trustedSubDepIndirect: 0,
      untrusted: 0,
      data: 'call 1',
    })

    expect(sharedHandler({name: 'app-1', data: 'call 2'})).toEqual({
      name: 'app-1',
      trusted: 1,
      trustedSubDepIndirect: 1,
      untrusted: 1,
      data: 'call 2',
    })

    expect(sharedHandler({name: 'app-2'})).toEqual({
      name: 'app-2',
      trustedSubDepDirect: 2,
      untrusted: 0, // app-2 gets it's own copy of the untrusted module
    })

    expect(sharedHandler({name: 'app-2'})).toEqual({
      name: 'app-2',
      trustedSubDepDirect: 3,
      untrusted: 1,
    })
  })

  it('should throw if a reset occurs after multiple renders', () => {
    const setup = getSetup()
    const sharedHandler = setup()

    sharedHandler({name: 'app-1'})
    sharedHandler({name: 'app-2'})

    // at this point, 2 entries have been used without a reset. This is only ok if we are running without isolation
    // calling setup again should throw an error because we are only resetting some of the time
    expect(() => setup()).toThrow('Expected only one used handler per reset, but found multiple: app-1, app-2')
  })

  it('should throw if a global variable is created during a render', () => {
    const setup = getSetup()

    // Render an app which creates a global variable during the render
    setup()({name: 'global-on-render'})

    // During the reset process, the global should be detected and throw an error
    expect(() => setup()).toThrow(
      'Unexpected global keys created while creating handler global-on-render: someVariable',
    )
  })

  it('should throw if an unknown handler is rendered', () => {
    const setup = getSetup()

    // Render an unknown handler
    expect(() => setup()({name: 'some-unknown-handler'})).toThrow(
      'Requested handler "some-unknown-handler" was not found. Ensure the some-unknown-handler package has an ssr-entry.ts file.',
    )
  })
})
