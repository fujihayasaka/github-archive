import {Box, Heading, Link} from '@primer/react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

type EnterpriseTeam = {
  id: number
  name: string
  slug: string
  externalGroupCount: number
  externalGroupMemberCount: number
  memberCount: number
  organizationSelectionType: string
  databaseRoute: string
  membersRoute: string
}

export interface StafftoolsBusinessTeamsItemPayload {
  // Update this type to reflect the data you place in payload in Rails
  enterpriseTeam: EnterpriseTeam
  businessSlug: string
}

export function StafftoolsBusinessTeamsItemView() {
  const payload = useRoutePayload<StafftoolsBusinessTeamsItemPayload>()

  const pluralize = (count: number, noun: string, suffix = 's') => `${count} ${noun}${count !== 1 ? suffix : ''}`

  return (
    <>
      <header className="Subhead">
        <Heading as="h2" className="Subhead-heading" data-testid={`heading`}>
          {payload.enterpriseTeam.name}
        </Heading>
      </header>

      <Box sx={{mb: 5}}>
        <table className="site-admin-table">
          <tbody>
            <tr>
              <th>ID</th>
              <th data-testid={`team-id`}>{payload.enterpriseTeam.id}</th>
            </tr>
            <tr>
              <th>Name</th>
              <th data-testid={`team-name`}>{payload.enterpriseTeam.name}</th>
            </tr>
            <tr>
              <th>Slug</th>
              <th data-testid={`team-slug`}>{payload.enterpriseTeam.slug}</th>
            </tr>
            <tr>
              <th>External Groups</th>
              <th data-testid={`team-group-count`}>
                {pluralize(payload.enterpriseTeam.externalGroupCount, 'external group')}
              </th>
            </tr>
          </tbody>
        </table>

        <Link href={payload.enterpriseTeam.databaseRoute} data-testid={`database-link`}>
          View database record
        </Link>
      </Box>

      <Box sx={{mb: 5}}>
        <header className="Subhead">
          <Heading as="h3" className="Subhead-heading">
            Linked External Groups
          </Heading>
        </header>
        <p>No linked external groups found.</p>
      </Box>

      <Box sx={{mb: 5}}>
        <header className="Subhead">
          <Heading as="h3" className="Subhead-heading">
            Team details
          </Heading>
        </header>
        <table className="site-admin-table">
          <tbody>
            <tr>
              <th>Direct members</th>
              <th data-testid={`direct-member-count`}>
                <Link href={payload.enterpriseTeam.membersRoute} data-testid={`members-link`}>
                  {pluralize(payload.enterpriseTeam.memberCount, 'member')}
                </Link>
              </th>
            </tr>
            <tr>
              <th>External group members</th>
              <th data-testid={`external-member-count`}>
                {pluralize(payload.enterpriseTeam.externalGroupMemberCount, 'external group member')}
              </th>
            </tr>
          </tbody>
        </table>
      </Box>
    </>
  )
}
