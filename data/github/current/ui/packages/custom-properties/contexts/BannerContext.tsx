import {createContext, useCallback, useContext, useEffect, useMemo, useRef, useState} from 'react'

export type BannerType =
  | 'definition.created.success'
  | 'definition.updated.success'
  | 'definition.deleted.success'
  | 'definition.promotion.success'
  | 'repos.properties.updated'

interface BannerContextState {
  banner: BannerType | null
}
const BannerContext = createContext<BannerContextState>({} as BannerContextState)
const SetBannerContext = createContext<(banner: BannerType | null) => void>(() => undefined)

export const BANNER_HIDE_DELAY_MS = 5 * 1_000

export function BannerProvider({children}: React.PropsWithChildren) {
  const timestampRef = useRef(0)
  const [banner, setBanner] = useState<BannerType | null>(null)

  const state = useMemo<BannerContextState>(() => ({banner}), [banner])
  const setter = useCallback((type: BannerType | null) => {
    setBanner(type)
    timestampRef.current = Date.now()
  }, [])

  const hideExpiredBanners = useCallback(() => {
    if (Date.now() - timestampRef.current > BANNER_HIDE_DELAY_MS) {
      setBanner(null)
    }
  }, [])

  useEffect(() => {
    document.addEventListener('soft-nav:start', hideExpiredBanners)
    return () => document.removeEventListener('soft-nav:start', hideExpiredBanners)
  }, [hideExpiredBanners])

  return (
    <BannerContext.Provider value={state}>
      <SetBannerContext.Provider value={setter}>{children}</SetBannerContext.Provider>
    </BannerContext.Provider>
  )
}

export function useSetBanner() {
  const setter = useContext(SetBannerContext)
  if (!setter) {
    throw new Error('useSetBanner must be used within BannerProvider')
  }

  return setter
}

function useBannerContext() {
  const context = useContext(BannerContext)

  if (!context) {
    throw new Error('useBannerContext must be used within BannerProvider')
  }

  return context
}

export function useActiveBanner(): BannerType | null {
  const {banner} = useBannerContext()

  return banner
}
