import {injectDynamicElementImports} from '@github-ui/client-build-plugins/dynamic-elements'
import type {PluginOption} from 'vite'

export function dynamicElementsPlugin(): PluginOption {
  return {
    name: 'dynamic-elements-plugin',
    enforce: 'pre',
    transform: injectDynamicElementImports,
  }
}
