import {useLayoutEffect} from '@github-ui/use-layout-effect'

export function useHideGlobalAppHeader() {
  // hack to hide the header when viewing the space new/edit page
  useLayoutEffect(() => {
    const header = document.querySelector<HTMLElement>('header.AppHeader')
    if (header) {
      header.style.display = 'none'
    }

    // also need to remove the margin applied to the main app content when this header's being used
    const appMain = document.querySelector<HTMLElement>('.with-global-sidebar .application-main')
    if (appMain) {
      appMain.style.marginLeft = '0'
    }

    return () => {
      if (header) {
        header.style.display = ''
      }
      if (appMain) {
        appMain.style.marginLeft = ''
      }
    }
  }, [])
}
