import type {PluginOption} from 'vite'
import commonjs from 'vite-plugin-commonjs'

/**
 * This is a temporary plugin to patch the ms.analytics-web.js file so that it can be imported
 * by Vite. The marketing team is working toward using an ESM version of the file, at which point
 * we can remove this plugin. We DO NOT want to add more commonjs files to the build, so please
 * do not add more files to this plugin.
 */
export function temporaryCommonjsPlugin(): PluginOption {
  return [
    commonjs({
      filter: id => id.endsWith('ms.analytics-web.js'),
    }),
  ]
}
