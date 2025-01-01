import {SubNav} from '@primer/react-brand'

export default function EnterpriseSubNav() {
  return (
    <SubNav className="lp-SubNav px-3 px-md-4 px-lg-5">
      <SubNav.Heading href="/enterprise">Enterprise</SubNav.Heading>

      <SubNav.Link href="/enterprise/advanced-security">Advanced Security</SubNav.Link>

      <SubNav.Link href="/premium-support">Premium Support</SubNav.Link>
    </SubNav>
  )
}
