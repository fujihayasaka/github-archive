// @ts-check
import {transformAsync} from '@babel/core'
import {optOutList, optInList} from './react-compiler-opt-out-list.js'
import {getReactVersion} from './define.js'

const reactMajorVersion = getReactVersion().split('.')[0]

/**
 * We only need to compile react-related files which are not on the opt-out list
 *
 * @param {string} source
 * @param {string} filePath
 */
function shouldCompile(source, filePath) {
  if (!filePath.endsWith('.tsx') && !filePath.endsWith('.ts')) {
    // Only compile .tsx and .ts files
    return false
  }

  if (filePath.endsWith('.ts') && !source.includes('react')) {
    // Some .ts files need to be compiled, but only if they include React code
    return false
  }

  const shouldOptOut = optOutList.some(packagePath => filePath.includes(packagePath))
  const shouldOptIn = optInList.some(packagePath => filePath.includes(packagePath))
  return shouldOptIn || !shouldOptOut
}

/**
 * This plugin runs the babel react-compiler against a subset of tsx/ts files
 *
 * @param {string} source The source code of the file being transformed
 * @param {string} filePath The path to the file being transformed
 */
export async function runReactCompiler(source, filePath) {
  if (!shouldCompile(source, filePath)) {
    return
  }

  // Only use the decorator plugin if a decorator is potentially in the file to save time
  const decoratorPlugins = source.includes('@') ? [['@babel/plugin-syntax-decorators', {version: 'legacy'}]] : []

  // Run babel with the react-compiler plugin
  const result = await transformAsync(source, {
    /**
     * These config options are ported from react-compiler-webpack, combined with our custom config
     * https://github.com/SukkaW/react-compiler-webpack/blob/58ca7845d8e5acf8441c02c9fc0c57e6163ee448/src/react-compiler-loader.ts#L21-L43
     */
    sourceFileName: filePath,
    filename: filePath,
    cloneInputAst: false,
    plugins: [
      [
        'babel-plugin-react-compiler',
        {
          // Set the target to match the installed version of React
          target: reactMajorVersion,
        },
      ],
      ...decoratorPlugins,
    ],
    parserOpts: {
      plugins: ['jsx', 'typescript'],
    },
    ast: false,
    sourceMaps: true,
    configFile: false,
    babelrc: false,
  })

  if (!result) {
    throw new TypeError('babel.transformAsync with react compiler plugin returns null')
  }

  const {code, map} = result
  return {code: code ?? undefined, map: map ?? undefined}
}
