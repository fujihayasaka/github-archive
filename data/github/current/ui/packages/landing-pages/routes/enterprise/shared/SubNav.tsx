import {SubNav} from '@primer/react-brand'

interface EnterpriseSubNavProps {
  currentPage?: string
}

export default function EnterpriseSubNav({currentPage}: EnterpriseSubNavProps) {
  return (
    <div className="lp-SubNavContainer">
      <SubNav className="lp-SubNav px-3 px-md-4 px-lg-5">
        <SubNav.Heading href="/enterprise">Enterprise</SubNav.Heading>

        <SubNav.Link
          href="/enterprise/advanced-security"
          aria-current={currentPage === '/enterprise/advanced-security' ? 'page' : undefined}
        >
          Advanced Security
        </SubNav.Link>

        <SubNav.Link
          href="/enterprise/premium-support"
          aria-current={currentPage === '/enterprise/premium-support' ? 'page' : undefined}
        >
          Premium Support
        </SubNav.Link>
      </SubNav>
    </div>
  )
}
