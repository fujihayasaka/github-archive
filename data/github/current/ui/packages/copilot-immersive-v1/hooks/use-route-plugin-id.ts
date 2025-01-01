import {useChatStateValues} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {usePlugins} from '@github-ui/copilot-chat/plugin/registry'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useEffect, useMemo} from 'react'

const pluginIdRegex = /\/copilot\/([^/]+)/

/**
 * Sync the active plugin to the route if the active plugin does not match.
 */
export function useSyncPluginToRoute() {
  const routePluginId = useRoutePluginId()
  const {activePlugin, selectedThreadID} = useChatStateValues('activePlugin', 'selectedThreadID')
  const manager = useChatManager()
  useEffect(() => {
    // if there is a thread, we don't want to change the active plugin since thread routes don't currently
    // reflect the plugin that the thread is associated with.
    if (selectedThreadID) return

    const activePluginId = activePlugin ?? null
    if (activePluginId !== routePluginId) {
      manager.selectPlugin(routePluginId)
    }
  }, [activePlugin, manager, routePluginId, selectedThreadID])
}

/**
 * Extracts the plugin name from the current URL's pathname.
 */
export function useRoutePluginId() {
  const pathname = ssrSafeLocation.pathname
  const plugins = usePlugins()
  return useMemo(() => {
    const match = pathname.match(pluginIdRegex)
    if (!match) return null

    const [, pluginId] = match

    // confirm plugin exists in plugin list
    if (!pluginId) return null
    if (!plugins.find(plugin => plugin.id === pluginId)) return null

    return pluginId
  }, [pathname, plugins])
}
