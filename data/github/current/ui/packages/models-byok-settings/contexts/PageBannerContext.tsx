import {IS_BROWSER} from '@github-ui/ssr-utils'
import {Portal, registerPortalRoot} from '@primer/react'
import {clsx} from 'clsx'
import {cloneElement, type ReactElement, useSyncExternalStore} from 'react'

import styles from '../components/PageBanner.module.css'

type BannerElement = ReactElement<{className?: string; onDismiss?: () => void}>

const zone: ReturnType<typeof createStore> = createStore()

export function setBanner(el: BannerElement) {
  zone.set(el)
}

function createStore() {
  let callback: (() => void) | null = null
  let currentBanner: BannerElement | null = null

  function update() {
    callback?.()
  }

  return {
    subscribe: (cb: () => void) => {
      callback = cb
      return () => {
        currentBanner = null
        callback = null
      }
    },
    getSnapshot: (): BannerElement | null => {
      return currentBanner
    },
    dismiss: () => {
      currentBanner = null
      update()
    },
    set: (el: BannerElement) => {
      currentBanner = el
      update()
    },
  }
}

export function PageBannerOutlet() {
  if (IS_BROWSER) {
    const node = document.getElementById('js-flash-container')!
    registerPortalRoot(node, 'flashContainer')
  }

  // At this stage, banners cannot be set on the server, so just return null.
  const el = useSyncExternalStore(zone.subscribe, zone.getSnapshot, () => null)

  if (el == null) return null

  return (
    <Portal containerName="flashContainer">
      {cloneElement(el, {className: clsx(styles.PageBanner, el.props.className), onDismiss: zone.dismiss})}
    </Portal>
  )
}
