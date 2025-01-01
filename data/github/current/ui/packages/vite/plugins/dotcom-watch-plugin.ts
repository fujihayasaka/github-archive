import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'
import type {PluginOption} from 'vite'

// Only these paths will be watched by Vite
// If we allow the default watch functionality, we fall into symlink loops
const watchPaths = [
  fullPathFromRoot('app/assets'),
  fullPathFromRoot('app/components'),
  fullPathFromRoot('ui'),
  fullPathFromRoot('test/js'),
]

export function dotcomWatchPlugin(): PluginOption {
  return {
    name: 'dotcom-watch-plugin',

    config() {
      return {
        server: {
          watch: {
            ignored: path => {
              for (const watchPath of watchPaths) {
                if (path.startsWith(watchPath) || watchPath.startsWith(path)) {
                  return false
                }
              }

              return true
            },
          },
        },
      }
    },
  }
}
