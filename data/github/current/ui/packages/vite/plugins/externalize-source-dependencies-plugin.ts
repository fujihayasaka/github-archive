import type {PluginOption} from 'vite'

/**
 * https://rollupjs.org/plugin-development/#resolveid
 * @param {Array<string>} sources
 */
export function externalizeSourceDependenciesPlugin(sources: string[]): PluginOption {
  return {
    name: 'externalize-source-dependencies-plugin',
    /**
     * @param {string} source
     */
    resolveId(source: string) {
      if (sources.includes(source)) {
        return {
          id: source,
          external: true,
        }
      }
      return null
    },
  }
}
