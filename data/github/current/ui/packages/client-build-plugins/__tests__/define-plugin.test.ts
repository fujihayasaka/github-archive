import {getAlloyDefinePluginConfig, getDefinePluginConfig, getReactVersion} from '../define'
import reactCorePackage from '../../react-core/package.json' with {type: 'json'}
import reactNextPackage from '../../react-next/package.json' with {type: 'json'}

describe('define plugin', () => {
  it('should provide a basic define config', () => {
    const config = getDefinePluginConfig({bundler: 'some-bundler'})

    // Check a subset of the config. Some fields are simple contents and don't need to be tested.
    expect(config).toMatchObject({
      BUNDLER: JSON.stringify('some-bundler'),
      'process.env.APP_ENV': JSON.stringify(process.env.NODE_ENV),
    })
  })

  it('should allow react version to be overridden', () => {
    const config = getDefinePluginConfig({bundler: 'some-bundler', reactVersion: '1.2.3'})

    // Check a subset of the config. Some fields are simple contents and don't need to be tested.
    expect(config).toMatchObject({
      REACT_VERSION: JSON.stringify('1.2.3'),
    })
  })
})

describe('react version', () => {
  it('should be the version from react-core package.json', () => {
    const version = getReactVersion()
    expect(typeof version).toBe('string')
    expect(version).toBe(reactCorePackage.dependencies.react)
  })

  it('should be able to get the react next version', () => {
    const version = getReactVersion(true)
    expect(typeof version).toBe('string')
    expect(version).toBe(reactNextPackage.dependencies.react)
  })
})

describe('define for alloy', () => {
  it('should provide a basic define config', () => {
    const config = getAlloyDefinePluginConfig({bundler: 'webpack-alloy'})

    // Check a subset of the config. Some fields are simple contents and don't need to be tested.
    expect(config).toMatchObject({
      BUNDLER: JSON.stringify('webpack-alloy'),
      'process.env.APP_ENV': JSON.stringify(process.env.NODE_ENV),
    })
  })
})
