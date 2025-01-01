import {Box, SubNav} from '@primer/react-brand'
import {clsx} from 'clsx'

import {SUBNAV_LINKS} from './SecuritySubNav.data'

import Styles from './SecuritySubNav.module.css'

interface SecuritySubNavProps {
  currentUrl?: string
}

interface SecuritySubNavItem {
  label: string
  url: string
  items?: SecuritySubNavItem[] // Optional array of sub-items
}

export default function SecuritySubNav({currentUrl}: SecuritySubNavProps) {
  return (
    <>
      <Box className={Styles['SecuritySubNav__spacer']} />
      <SubNav className={clsx(Styles['SecuritySubNav'], Styles['SecuritySubNav--highContrast'])}>
        <SubNav.Heading href={SUBNAV_LINKS.logo.url} className={clsx('d-block', 'position-relative')}>
          {SUBNAV_LINKS.logo.label}
        </SubNav.Heading>
        {SUBNAV_LINKS.items.map((item: SecuritySubNavItem) => {
          const isCurrentUrl = item.url === currentUrl
          return (
            <SubNav.Link
              key={`subnav_${item.url}`}
              href={isCurrentUrl ? '#' : item.url}
              className={isCurrentUrl ? 'selected' : ''}
              aria-current={isCurrentUrl ? 'page' : undefined}
            >
              {item.label}

              {item.items && (
                <SubNav.SubMenu>
                  {item.items.map(subItem => {
                    const isCurrentSubUrl = subItem.url === currentUrl
                    return (
                      <SubNav.Link
                        key={`subnav_${subItem.url}`}
                        href={isCurrentSubUrl ? '#' : subItem.url}
                        className={isCurrentSubUrl ? 'selected' : ''}
                        aria-current={isCurrentSubUrl ? 'page' : undefined}
                      >
                        {subItem.label}
                      </SubNav.Link>
                    )
                  })}
                </SubNav.SubMenu>
              )}
            </SubNav.Link>
          )
        })}
      </SubNav>
    </>
  )
}
