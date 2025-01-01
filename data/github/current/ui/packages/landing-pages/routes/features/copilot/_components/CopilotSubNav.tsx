import {SubNav} from '@primer/react-brand'
import {SUBNAV_LINKS} from './SubNav.data'

interface CopilotSubNavProps {
  currentUrl?: string
}

interface CopilotSubNavItem {
  label: string
  url: string
  items?: CopilotSubNavItem[] // Optional array of sub-items
}

export default function CopilotSubNav({currentUrl}: CopilotSubNavProps) {
  return (
    <SubNav className="lp-Hero-subnav lp-Hero-subnav--highContrast">
      <SubNav.Heading href={SUBNAV_LINKS.logo.url} className="d-block position-relative lp-Hero-subnav-heading">
        {SUBNAV_LINKS.logo.label}
      </SubNav.Heading>

      {SUBNAV_LINKS.items.map((item: CopilotSubNavItem) => {
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
  )
}
