import type {PluginOption, UserConfig} from 'vite'
import path from 'node:path'
import {getSSREntryPoints} from '@github-ui/client-build-tools/entry-points'
import {relativePathFromRoot} from '@github-ui/client-build-tools/path-utils'
import {injectAlloyEntryImports} from '@github-ui/client-build-plugins/alloy-entry'
import {createHash} from 'node:crypto'

const ssrEntries = getSSREntryPoints()
const cssLeadingMarker = '--css-file--'
const cssTrailingMarker = '--_--'
const cssFileRegex = new RegExp(`${cssLeadingMarker}(?<fileName>.+?)${cssTrailingMarker}`, 'g')

function getCssFileNamePrefix(filename: string) {
  return cssLeadingMarker + filename + cssTrailingMarker
}
function generateScopedName(name: string, filename: string, ssr: boolean) {
  const hash = createHash('sha256').update(filename).update(name).digest('hex').slice(0, 8)
  const scopeName = `${path.basename(filename).split('.')[0]}_${name}_${hash}`

  if (ssr) {
    // Embed the full file path in the scope name so that we can extract it with injectCssModuleLinks
    return getCssFileNamePrefix(filename) + scopeName
  }

  return scopeName
}

export function injectCssModuleLinks(html: string) {
  const matches = html.matchAll(cssFileRegex)

  // Get the list of css files used to render the HTML
  const cssFiles = new Set<string>()
  for (const match of matches) {
    const fileName = match.groups?.fileName
    if (fileName) {
      cssFiles.add(fileName)
    }
  }

  // Generate link tags for each CSS file. These will be removed client-side after hydration
  let linkTags = ''
  for (const cssFile of cssFiles) {
    // eslint-disable-next-line github/unescaped-html-literal
    linkTags += `<link rel="stylesheet" href="/vite/${relativePathFromRoot(
      cssFile,
    )}" data-remove-after-hydration="true">`
  }

  // Embed the link tags in front of the the SSRd content
  return `${linkTags}${html.replace(cssFileRegex, '')}`
}

function applyIfSsr(enabled: boolean) {
  return (config: UserConfig) => {
    return Boolean(config.ssr) === enabled
  }
}

export function alloyPlugin(): PluginOption {
  return [
    {
      name: 'alloy-entry-plugin',
      enforce: 'pre',
      apply: applyIfSsr(true),
      transform: function injectDynamicAlloyImports(source, filePath) {
        return injectAlloyEntryImports(source, filePath, ssrEntries, 'import')
      },
    },
    {
      name: 'alloy-css-module-names-ssr',
      apply: applyIfSsr(true),
      config: () => {
        return {
          css: {
            modules: {
              generateScopedName(name, filename) {
                /**
                 * For ssr renders, generate the scopes with the file path embedded in the scope name
                 * These paths will be replaced using injectCssModuleLinks. This allows us to gather
                 * all CSS files used to generate the SSRd HTML, which can then be injected as link tags
                 */
                return generateScopedName(name, filename, true)
              },
            },
          },
        }
      },
    },
    {
      name: 'alloy-css-module-names-client',
      apply: applyIfSsr(false),
      config: () => {
        return {
          css: {
            modules: {
              generateScopedName(name, filename) {
                // For client renders, generate the scopes without an embedded file path
                return generateScopedName(name, filename, false)
              },
            },
          },
        }
      },
    },
    {
      name: 'alloy-css-module-hmr',
      apply: applyIfSsr(false),
      handleHotUpdate({file, modules}) {
        /**
         * When SSR is used for a page with a CSS module, the CSS module is embedded in the
         * SSR respone as a link tag. Vite will later load the same modules as a JS file.
         * HMR only works for the JS file, while the CSS file will cause a full page reload.
         * This plugin will ensure that a full page reload is avoided if the JS version of the
         * CSS modules is also loaded on the page.
         */
        if (!file.endsWith('.module.css')) {
          return
        }

        const isJsFilePresent = modules.some(m => m.file === file && m.type === 'js')
        if (isJsFilePresent) {
          return modules.filter(m => {
            if (m.file === file && m.type === 'css') {
              // JS file is present, so we don't need to do a full page reload for the CSS file
              return false
            }

            return true
          })
        }
      },
    },
    {
      name: 'primer-css-modules',
      apply: applyIfSsr(true),
      enforce: 'pre',
      transform(code, id) {
        /**
         * We also want to dynamically import css modules from primer/react when they are used in SSR.
         * These already have an established scope name, but follow a pattern of `prc-*`. We can leverage
         * this to inject the file name into the class name strings in the .module.css.js files.
         */
        if (id.includes('@primer/react/') && id.includes('.module.css.js')) {
          const cssImportRegex = /import ['"](.+?\.css)['"]/g
          const importMatch = cssImportRegex.exec(code)
          const cssFileImport = importMatch?.[1]

          if (!cssFileImport) {
            return code
          }

          const cssFilePath = path.resolve(path.dirname(id), cssFileImport)
          const classPrefix = getCssFileNamePrefix(cssFilePath)
          return code
            .replace(/"prc-/g, `"${classPrefix}prc-`) // Inject the file name into each of the PRC class names
            .replace(cssImportRegex, '') // Remove the css import server-side to avoid ESM runtime issues. It will still be included client-side.
        }

        return code
      },
    },
  ]
}
