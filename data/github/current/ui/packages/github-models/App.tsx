import {useLayoutEffect} from '@github-ui/use-layout-effect'
import type {PropsWithChildren} from 'react'

export function App(props: PropsWithChildren) {
  useLayoutEffect(() => {
    const header = document.getElementsByClassName('header-wrapper')
    const height = header[0]?.clientHeight
    if (height) {
      document.documentElement.style.setProperty('--header-height', `${height}px`)
    }
  }, [])

  return <>{props.children}</>
}
