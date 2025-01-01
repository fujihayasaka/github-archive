import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {PageHeader, UnderlineNav} from '@primer/react'
import {enterpriseRolesPath} from '@github-ui/paths'

export interface EnterpriseRoleAssignmentsPayload {
  slug: string
}

export function EnterpriseRoleAssignments() {
  const payload = useRoutePayload<EnterpriseRoleAssignmentsPayload>()

  return (
    <PageHeader>
      <PageHeader.TitleArea>
        <PageHeader.Title as="h2">Enterprise roles</PageHeader.Title>
      </PageHeader.TitleArea>
      <PageHeader.Navigation>
        <UnderlineNav aria-label="Enterprise roles" sx={{paddingInline: 0}}>
          <UnderlineNav.Item href={enterpriseRolesPath({slug: payload.slug})}>Role management</UnderlineNav.Item>
          <UnderlineNav.Item aria-current="page">Role assignments</UnderlineNav.Item>
        </UnderlineNav>
      </PageHeader.Navigation>
    </PageHeader>
  )
}
