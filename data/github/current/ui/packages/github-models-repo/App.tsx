import type React from 'react'
import {PromptsBannersProvider} from './routes/prompt/contexts/PromptBannersContext'
import {PromptsBanner} from './routes/prompt/components/PromptsBanner'
import {useLayoutEffect} from '@github-ui/use-layout-effect'

import './app.module.css'

/**
 * The App component is used to render content which should be present on _all_ routes within this app
 */
export function App(props: {children?: React.ReactNode}) {
  useLayoutEffect(() => {
    const header = document.getElementsByClassName('header-wrapper')
    const height = header[0]?.clientHeight
    if (height) {
      document.documentElement.style.setProperty('--header-height', `${height}px`)
    }
  }, [])

  return (
    <PromptsBannersProvider>
      <PromptsBanner />
      {props.children}
    </PromptsBannersProvider>
  )
}
