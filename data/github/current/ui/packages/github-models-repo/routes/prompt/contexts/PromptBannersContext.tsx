import type {BannerProps} from '@primer/react/experimental'
import {createContext, useContext, useMemo, useState} from 'react'

export type Banner = {
  variant: Extract<BannerProps['variant'], 'success' | 'critical' | 'info'>
  message: string
  description?: React.ReactNode
}

interface PromptBannersContextType {
  banner?: Banner
  setBanner: (banner?: Banner) => void
}

const PromptBannersContext = createContext<PromptBannersContextType>({
  banner: undefined,
  setBanner: () => undefined,
})

export function usePromptsBanner() {
  return useContext(PromptBannersContext)
}

export function PromptsBannersProvider({children}: {children: React.ReactNode}) {
  const [banner, setBanner] = useState<Banner>()
  const value = useMemo(() => ({banner, setBanner}), [banner, setBanner])
  return <PromptBannersContext.Provider value={value}>{children}</PromptBannersContext.Provider>
}
