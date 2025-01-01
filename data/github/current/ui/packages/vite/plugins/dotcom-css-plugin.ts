import {wrapCssInPrimerReactLayer} from '@github-ui/client-build-plugins/primer-react-css-layer'
import type {PluginOption} from 'vite'

export function dotcomCssPlugin(): PluginOption {
  return [
    {
      name: 'primer-react-css-layers-plugin',
      transform: wrapCssInPrimerReactLayer,
    },
  ]
}
