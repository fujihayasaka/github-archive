// @ts-check
const swcConfig = require('@github-ui/swc/config')
const path = require('path')
const {fullPathFromRoot} = require('@github-ui/client-build-tools/path-utils')

const isCI = Boolean(process.env.CI)
const isJanky = Boolean(process.env.GITHUB_CI)
const isReactNext = Boolean(process.env.REACT_NEXT)
let reporters = undefined

if (isJanky) {
  reporters = ['default', require.resolve('./reporters/janky-reporter.mjs')]
} else if (isCI) {
  reporters = [['github-actions', {silent: false}], require.resolve('./reporters/janky-reporter.mjs'), 'summary']
}

/**
 * Jest automatically ignores transforming node_modules, however
 * we want to transform these files if they are esm.
 *
 * To accommodate this we tell jest to not ignore these files.
 * by removing them from the transform ignore list by negated regex.
 */
const esmDependencies = [
  '@azure/abort-controller',
  '@azure/core-auth',
  '@azure/core-client',
  '@azure/core-http-compat',
  '@azure/core-rest-pipeline',
  '@azure/core-util',
  '@github-ui/query-builder-element',
  '@github-ui/query-builder',
  '@github/alive-client',
  '@github/auto-check-element',
  '@github/blackbird-parser',
  '@github/browser-support',
  '@github/catalyst',
  '@github/combobox-nav',
  '@github/g-emoji-element',
  '@github/hotkey',
  '@github/hydro-analytics-client',
  '@github/jtml',
  '@github/markdown-toolbar-element',
  '@github/multimap',
  '@github/paste-markdown',
  '@github/remote-form',
  '@github/stable-socket',
  '@github/template-parts',
  '@github/text-expander-element',
  '@github/webauthn-json',
  '@koddsson/textarea-caret',
  '@lit-labs/ssr-dom-shim',
  '@lit/react',
  '@ngneat/falso',
  '@primer/behaviors',
  '@primer/behaviors/utils',
  '@primer/react-markdown-viewer/lib-esm',
  '@primer/react',
  '@primer/react/lib-esm',
  '@primer/react/node_modules/@github/combobox-nav',
  '@typespec/ts-http-runtime',
  'bail',
  'ccount',
  'character-entities',
  'client-zip',
  'comma-separated-tokens',
  'd3',
  'd3-dag',
  'date-fns',
  'decode-named-character-reference',
  'delaunator',
  'devlop',
  'dom-input-range',
  'escape-string-regexp',
  'estree-util-',
  'globby',
  'hast-',
  'hastscript',
  'html-url-attributes',
  'invokers-polyfill',
  'is-plain-obj',
  'internmap',
  'leven',
  'lit-html',
  'lodash-es',
  'longest-streak',
  'lowlight',
  'markdown-table',
  'mdast-',
  'micromark',
  'node-plop',
  'property-information',
  'react-markdown',
  'rehype-highlight',
  'remark',
  'remark-',
  'remark-gfm',
  'robust-predicates',
  'slash',
  'space-separated-tokens',
  'three',
  'trim-lines',
  'trough',
  'unified',
  'unist-',
  'uuid',
  'vfile-message',
  'vfile',
  'zwitch',
]

/** @type {import('jest').Config} */
module.exports = {
  /**
   * Ensure that we only lookup modules from the node_modules folder, to avoid loading
   * some that might be in `vendored` dependencies
   */
  moduleDirectories: ['node_modules'],
  moduleNameMapper: {
    '@github/webauthn-json/browser-ponyfill': fullPathFromRoot('node_modules/@github/webauthn-json'),
    '.*/ui-packages-tooling/plopfile.ts': fullPathFromRoot('ui/packages/ui-packages-tooling/plopfile.ts'),
    ...(isReactNext
      ? {
          '^react$': fullPathFromRoot('ui/packages/react-next/node_modules/react'),
          '^react-dom$': fullPathFromRoot('ui/packages/react-next/node_modules/react-dom'),
          '^react-is$': fullPathFromRoot('ui/packages/react-next/node_modules/react-is'),
        }
      : {
          '^react$': fullPathFromRoot('node_modules/react'),
          '^react-dom$': fullPathFromRoot('node_modules/react-dom'),
          '^react-is$': fullPathFromRoot('node_modules/react-is'),
        }),
  },
  passWithNoTests: true,
  reporters,
  setupFiles: [require.resolve('./fetch-polyfills.ts')],
  resolver: `${__dirname}/resolver.cjs`,
  setupFilesAfterEnv: [require.resolve('./jest-setup.ts'), 'jest-canvas-mock'],
  testEnvironment: 'jsdom',
  // Use shorter timeout for local development, so slow tests fail fast instead of being flaky in CI.
  // This makes slow tests more noticeable, so devs can realize and improve them before committing.
  // This can be overridden per test.
  testTimeout: isCI ? 10_000 : 2500,
  transform: {
    '^.+\\.(t|m?j)sx?$': ['@swc/jest', {...swcConfig, sourceMaps: false}],
    '@primer\\/react\\/.+.css$': require.resolve('./transformers/cssTransformer.js'),
    '\\.(png|jpe?g|gif|webp|mp4|svg|glb)$': path.join(__dirname, 'transformers', 'static-assets-transformer.js'),
    '^.+\\.(yml|yaml)$': path.join(__dirname, 'transformers', 'yaml-transformer.js'),
    '.+\\.module\\.(css|scss)$': 'jest-css-modules-transform',
  },
  // Some modules only export esm, and need to be transformed for jest
  transformIgnorePatterns: [`node_modules/(?!${esmDependencies.join('|')})`],
  workerThreads: true,
  fakeTimers: {
    doNotFake: ['performance', 'queueMicrotask'],
  },
}
