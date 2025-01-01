import {useChatStateValues} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import {usePlugins} from '@github-ui/copilot-chat/plugin/registry'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useEffect, useMemo} from 'react'

import {useRouteThreadId} from './use-route-thread-id'

/**
 * Sync the active plugin to the route if the active plugin does not match.
 */
export function useSyncPluginToRoute() {
  const plugins = usePlugins()
  const routePluginId = useRoutePluginId(plugins)
  const routeThreadId = useRouteThreadId()
  const {activePlugin} = useChatStateValues('activePlugin')
  const manager = useChatManager()
  useEffect(() => {
    // if there is a thread, we don't want to change the active plugin since thread routes don't currently
    // reflect the plugin that the thread is associated with.
    if (routeThreadId) return

    const activePluginId = activePlugin ?? null
    if (activePluginId !== routePluginId) {
      manager.selectPlugin(routePluginId)
    }
  }, [activePlugin, manager, routePluginId, routeThreadId])
}

/**
 * Extracts the plugin name from the current URL's pathname.
 */
export function useRoutePluginId(plugins: ImmersivePlugin[]): string | null {
  const pathname = ssrSafeLocation.pathname
  return useMemo(() => {
    const matchedPlugin = plugins.find(plugin => {
      return plugin.routes?.some(route => route.test(pathname))
    })

    return matchedPlugin ? matchedPlugin.id : null
  }, [pathname, plugins])
}
