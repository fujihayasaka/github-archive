import {dirname, join} from 'path'
import type {StorybookConfig as StorybookConfigWebpack} from '@storybook/react-webpack5'
import UICommandsPlugin from '@github-ui/ui-commands-scripts/plugin'
import type {StorybookConfig as StorybookConfigVite} from '@storybook/react-vite'
import {loadCsf} from '@storybook/csf-tools'
import {readFileSync} from 'fs'
import type {IndexerOptions, Indexer, IndexInput} from '@storybook/types'
import {createGeneratedFiles} from '@github-ui/client-build-tools/generated-files'
import postcssConfig from '@github-ui/postcss/postcss.config'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'
import swcConfig from '@github-ui/swc/config'

createGeneratedFiles()

const __dirname = new URL('.', import.meta.url).pathname

// matches prefixes 'ui/packages/', '@github-ui/', or any number of '../'
const packagePrefixRegex = /^((ui\/packages\/)|@github-ui\/)|(..\/)+/

const getStories = () => {
  const [packages, pattern] = process.argv.slice(-2)
  console.log('👀', 'received packages pattern:', pattern)

  if (packages === 'packages' && pattern) {
    const storyGlob = pattern
      .split(',')
      .map((p: string) => `../../${p.trim().replace(packagePrefixRegex, '')}/**/*.stories.@(tsx|ts|jsx|js)`)
    console.log('👉 Using custom story glob pattern:', storyGlob)
    return storyGlob
  }

  return ['../../../../app/assets/modules/**/*.stories.@(tsx|ts|jsx|js)', '../../**/*.@(mdx|stories.@(tsx|ts|jsx|js))']
}
const stories = getStories()

const addons = [
  getAbsoluteModulePath('@storybook/addon-a11y'),
  getAbsoluteModulePath('@storybook/addon-links'),
  getAbsoluteModulePath('@storybook/addon-essentials'),
  getAbsoluteModulePath('@storybook/addon-interactions'),
  getAbsoluteModulePath('@storybook/addon-storysource'),
  getAbsoluteModulePath('@storybook/addon-mdx-gfm'),
]

const staticDirs = [
  fullPathFromRoot('public/'),
  // contains the `mockServiceWorker.js` file used by `msw` to mock network requests
  fullPathFromRoot('test/assets/'),
  join(__dirname, '../public/'),
]

const createStoryIndices = (indexers?: Indexer[]): Indexer[] => {
  if (process.env.SKIP_CUSTOM_INDEX) {
    return [...(indexers ?? [])]
  }

  const storybookCategoryTitles = ['Templates', 'Recipes', 'Utilities', 'Apps']

  const createIndex = async (fileName: string, compilationOptions: IndexerOptions): Promise<IndexInput[]> => {
    const code = readFileSync(fileName, {encoding: 'utf-8'})

    const makeTitle = (userTitle: string) =>
      storybookCategoryTitles.includes(userTitle.split('/')[0] || '') ? userTitle : `Others/${userTitle}`

    return loadCsf(code, {...compilationOptions, makeTitle, fileName}).parse().indexInputs
  }

  return [
    {
      test: /\.(tsx|ts|jsx|js|mdx)$/,
      createIndex,
    },
    ...(indexers ?? []),
  ]
}

const viteStorybookConfig: StorybookConfigVite = {
  stories,

  staticDirs,

  addons,

  framework: {
    name: '@storybook/react-vite',
    options: {},
  },

  typescript: {
    reactDocgen: 'react-docgen-typescript',
    reactDocgenTypescriptOptions: {
      tsconfigPath: join(__dirname, '../tsconfig.json'),
    },
  },

  refs: {
    primer: {
      title: 'Primer React Components',
      url: 'https://primer.style/react/storybook/',
      expanded: false,
    },
  },

  experimental_indexers: createStoryIndices,

  core: {
    disableWhatsNewNotifications: true,
  },
}

const webpackStorybookConfig: StorybookConfigWebpack = {
  stories,

  staticDirs,

  addons: [...addons, getAbsoluteModulePath('@storybook/addon-webpack5-compiler-swc')],

  framework: {
    name: getAbsoluteModulePath('@storybook/react-webpack5'),
    options: {
      fastRefresh: true,
      strictMode: true,
      useSwc: true,
    },
  },

  refs: {
    primer: {
      title: 'Primer React Components',
      url: 'https://primer.style/react/storybook/',
      expanded: false,
    },
  },

  experimental_indexers: createStoryIndices,

  webpackFinal: async config => {
    if (config.resolve) {
      config.resolve.fallback = {
        fs: false,
        path: false,
      }
    }

    return {
      ...config,
      module: {
        ...config.module,
        rules: [
          ...(config.module?.rules ?? []).map(ruleset => {
            if (
              ruleset &&
              typeof ruleset === 'object' &&
              'test' in ruleset &&
              ruleset.test &&
              ruleset.test.toString() === '/\\.css$/'
            ) {
              ruleset.exclude = /\.module\.css$/
            }

            return ruleset
          }),
          {
            /**
             * We have a custom loader that will dynamically find and update the element registry to reference
             * all custom elements in the `app/components` directory. The js code for these
             * custom elements will be dynamically loaded on the page whenever the element tag is added to the DOM.
             */
            test: /element-registry\.ts?$/,
            loader: '@github-ui/webpack/loaders/dynamic-elements-loader',
          },
          {
            test: /\.scss$/,
            exclude: /\.module\.scss$/,
            use: [
              'style-loader',
              {
                loader: 'css-loader',
                options: {
                  url: false,
                },
              },
              {
                loader: 'postcss-loader',
                options: {
                  postcssOptions: postcssConfig,
                },
              },
            ],
          },
          {
            test: /\.module\.css$/,
            use: [
              'style-loader',
              {
                loader: 'css-loader',
                options: {
                  url: false,
                  modules: {
                    localIdentName: '[name]__[local]--[hash:base64:5]',
                    namedExport: false,
                    exportLocalsConvention: 'as-is',
                  },
                },
              },
            ],
          },
        ],
      },
      plugins: [
        ...(config.plugins ?? []),
        new UICommandsPlugin({
          env: 'development',
        }),
      ],
    }
  },

  core: {
    disableWhatsNewNotifications: true,
  },

  swc: () => {
    return {
      ...swcConfig,
      jsc: {
        ...swcConfig.jsc,
        target: undefined,
        transform: {
          ...swcConfig.jsc?.transform,
          react: {
            ...swcConfig.jsc?.transform?.react,
            refresh: false,
          },
        },
      },
    }
  },

  typescript: {
    reactDocgen: 'react-docgen-typescript',
  },
}

const config = process.env.WEBPACK ? webpackStorybookConfig : viteStorybookConfig

export default config

function getAbsoluteModulePath(moduleName: string): string {
  return fullPathFromRoot(`node_modules/${moduleName}`)
}
