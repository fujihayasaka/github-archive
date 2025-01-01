import {testIdProps} from '@github-ui/test-id-props'
import {useNavigate, type NavigateOptionsWithPreventAutofocus} from '@github-ui/use-navigate'
import {Banner} from '@primer/react/experimental'
import {createContext, useContext, type PropsWithChildren, useMemo, useState, useCallback} from 'react'
import type {To} from 'react-router-dom'

type bannerVariantType = 'success' | 'warning' | 'critical' | undefined

interface BannerState {
  message: string | null
  variant: bannerVariantType
}

interface ContextProps {
  navigate: (to: To, options?: NavigateOptionsWithPreventAutofocus, bannerState?: BannerState) => void
  showBanner: (newBannerState: BannerState) => void
}

const defaultBannerState: BannerState = {
  message: null,
  variant: undefined,
}

const BannerContext = createContext<ContextProps | null>(null)

export const BannerProvider = ({children}: PropsWithChildren) => {
  const [bannerState, setBanner] = useState<BannerState>(defaultBannerState)
  const [shouldShowBanner, setShouldShowBanner] = useState(false)

  const internalNavigate = useNavigate()
  const navigate = useCallback(
    (to: To, options?: NavigateOptionsWithPreventAutofocus, newBannerState: BannerState = defaultBannerState) => {
      internalNavigate(to, options)
      setBanner(newBannerState)
      setShouldShowBanner(newBannerState.message !== null)
    },
    [internalNavigate],
  )

  const showBanner = useCallback((newBannerState: BannerState) => {
    setBanner(newBannerState)
    setShouldShowBanner(newBannerState.message !== null)
  }, [])

  const value = useMemo(() => ({navigate, showBanner}), [navigate, showBanner])
  return (
    <BannerContext.Provider value={value}>
      <div className="d-flex flex-column gap-3">
        {bannerState.message && shouldShowBanner && (
          <Banner
            hideTitle
            title={bannerState.message}
            description={bannerState.message}
            variant={bannerState.variant}
            onDismiss={() => setShouldShowBanner(false)}
            {...testIdProps('banner')}
          />
        )}
        {children}
      </div>
    </BannerContext.Provider>
  )
}

export const useBannerContext = () => {
  const context = useContext(BannerContext)
  if (!context) {
    throw new Error('useBannerContext must be used within a BannerProvider')
  }
  return context
}
