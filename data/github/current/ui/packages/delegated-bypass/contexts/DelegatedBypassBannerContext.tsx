import {announce} from '@github-ui/aria-live'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import type {FlashProps} from '@primer/react'
import {createContext, useCallback, useContext, useMemo, useState} from 'react'

export type Banner = {
  variant: Extract<FlashProps['variant'], 'success' | 'danger'>
  message: string
  description?: React.ReactNode
  announce?: string
}

interface DelegatedBypassContextType {
  banner?: Banner
  setBanner: (banner?: Banner) => void
}

const DelegatedBypassBannersContext = createContext<DelegatedBypassContextType>({
  banner: undefined,
  setBanner: () => undefined,
})

/**
 * Gets a function to add a banner. This function never changes and is thus useful for code in useEffect().
 */
export function useDelegatedBypassBanner() {
  return useContext(DelegatedBypassBannersContext).banner
}
/**
 * Gets a function to add a banner. This function never changes and is thus useful for code in useEffect().
 */
export function useDelegatedBypassSetBanner() {
  return useContext(DelegatedBypassBannersContext).setBanner
}

export function DelegatedBypassBannersProviderV1({children}: {children: React.ReactNode}) {
  const [banner, setBanner] = useState<Banner>()
  const value = useMemo(() => ({banner, setBanner}), [banner, setBanner])

  return <DelegatedBypassBannersContext.Provider value={value}>{children}</DelegatedBypassBannersContext.Provider>
}

export function DelegatedBypassBannersProviderV2({children}: {children: React.ReactNode}) {
  const [banner, setBannerState] = useState<Banner>()

  const setBanner = useCallback(
    (newBanner?: Banner) => {
      if (
        newBanner &&
        (newBanner.message !== banner?.message ||
          newBanner.variant !== banner?.variant ||
          newBanner.announce !== banner?.announce)
      ) {
        announce(newBanner.announce ? newBanner.announce : newBanner.message)
        setBannerState(newBanner)
      }
    },
    [banner],
  )

  const value = useMemo(() => ({banner, setBanner}), [banner, setBanner])

  return <DelegatedBypassBannersContext.Provider value={value}>{children}</DelegatedBypassBannersContext.Provider>
}

export function DelegatedBypassBannersProvider({children}: {children: React.ReactNode}) {
  const rulesA11y = useFeatureFlag('rules_a11y')
  return rulesA11y ? (
    <DelegatedBypassBannersProviderV2>{children}</DelegatedBypassBannersProviderV2>
  ) : (
    <DelegatedBypassBannersProviderV1>{children}</DelegatedBypassBannersProviderV1>
  )
}
