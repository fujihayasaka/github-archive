import type React from 'react'
import {BannerProvider} from '@github-ui/role-assignments/banner-provider'

/**
 * The App component is used to render content which should be present on _all_ routes within this app
 */
export function App(props: {children?: React.ReactNode}) {
  return (
    <BannerProvider>
      <div>{props.children}</div>
    </BannerProvider>
  )
}
