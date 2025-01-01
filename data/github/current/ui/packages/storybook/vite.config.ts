// eslint-disable-next-line import/extensions
import viteConfig from '@github-ui/vite/vite.config.ts'

viteConfig.plugins = viteConfig.plugins?.filter(plugin => {
  // Remove the dotcom-entry-plugin from the Vite config since Storybook handles it's own entry points
  if (plugin && 'name' in plugin && plugin.name === 'dotcom-entry-plugin') {
    return false
  }

  return true
})

if (viteConfig.define) {
  // Override the APP_ENV to ensure test ids are included in production mode
  viteConfig.define['process.env.APP_ENV'] = '"storybook"'
}

// eslint-disable-next-line no-barrel-files/no-barrel-files
export default viteConfig
