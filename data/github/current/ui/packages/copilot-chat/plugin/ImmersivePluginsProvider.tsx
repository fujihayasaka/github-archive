import {createContext, type PropsWithChildren, useContext} from 'react'

import type {ImmersivePlugin} from './copilot-immersive-plugin'

const PluginsContext = createContext<ImmersivePlugin[]>([])

export function ImmersivePluginsProvider({plugins, children}: PropsWithChildren<{plugins: ImmersivePlugin[]}>) {
  return <PluginsContext.Provider value={plugins}>{children}</PluginsContext.Provider>
}

export function usePlugins(): ImmersivePlugin[] {
  return useContext(PluginsContext)
}

export function usePlugin(id: string | undefined): ImmersivePlugin | null {
  return usePlugins().find(p => p.id === id) ?? null
}
