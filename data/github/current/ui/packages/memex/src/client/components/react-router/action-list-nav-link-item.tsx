import {type ActionListLinkItemProps, NavList} from '@primer/react'
import type {ComponentProps} from 'react'
import {forwardRef} from 'react'
import {useMatch, useResolvedPath} from 'react-router-dom'

import {NavLinkWithActiveClassName} from './nav-link-with-active-class-name'

export const NavLinkActionListItem = forwardRef<
  HTMLAnchorElement,
  ActionListLinkItemProps & ComponentProps<typeof NavLinkWithActiveClassName>
>(function NavLinkActionListItem({to, children, isActive, ...props}, ref) {
  const resolved = useResolvedPath(to)
  const isCurrent = useMatch({path: resolved.pathname, end: true})
  return (
    <NavList.Item
      aria-current={isActive || isCurrent ? 'page' : false}
      as={NavLinkWithActiveClassName}
      {...props}
      to={to}
      ref={ref}
    >
      {children}
    </NavList.Item>
  )
})
