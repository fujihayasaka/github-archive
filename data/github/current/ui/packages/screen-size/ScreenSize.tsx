import React, {useCallback, useMemo, useSyncExternalStore} from 'react'
import {subscribe} from './resize-observer'

export const ScreenSize = {
  small: 1,
  medium: 544,
  large: 768,
  xlarge: 1012,
  xxlarge: 1280,
  xxxlarge: 1350,
  xxxxlarge: 1440,
} as const

export type ScreenSize = (typeof ScreenSize)[keyof typeof ScreenSize]

const screenBreakpoints = [
  ScreenSize.xxxxlarge,
  ScreenSize.xxxlarge,
  ScreenSize.xxlarge,
  ScreenSize.xlarge,
  ScreenSize.large,
  ScreenSize.medium,
  ScreenSize.small,
]

interface ScreenContextData {
  /**
   * Specifies the size of the current window
   */
  screenSize: ScreenSize
}

const ScreenContext = React.createContext<ScreenContextData>({screenSize: ScreenSize.small})

export function useScreenSize() {
  return React.useContext(ScreenContext)
}

interface Props {
  /**
   * @property {ScreenSize} [initialValue=ScreenSize.small] Initial value is useful to test react components that rely on ScreenContext.
   */
  initialValue?: ScreenSize
}

function getClientValue() {
  return getCurrentSize(window.innerWidth)
}

export function ScreenSizeProvider({children, initialValue = ScreenSize.small}: React.PropsWithChildren<Props>) {
  const screenSize = useSyncExternalStore(
    subscribe,
    getClientValue,
    useCallback(() => initialValue, [initialValue]),
  )

  const contextValue = useMemo(() => {
    return {screenSize}
  }, [screenSize])

  return <ScreenContext.Provider value={contextValue}>{children}</ScreenContext.Provider>
}

export function getCurrentSize(elementWidth: number) {
  for (const breakpoint of screenBreakpoints) {
    if (elementWidth >= breakpoint) {
      return breakpoint
    }
  }
  return ScreenSize.small
}
