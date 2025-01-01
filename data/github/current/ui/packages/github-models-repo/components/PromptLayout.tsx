import {memo} from 'react'
import {Outlet} from 'react-router-dom'

export const PromptLayout = memo(function Layout() {
  return <Outlet />
})
