import {Box, Heading, Link} from '@primer/react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

type EnterpriseTeam = {
  isMembersManagementEnabled: boolean
  id: number
  name: string
  slug: string
  externalGroupCount: number
  externalGroupMemberCount: number
  externalGroupPath: string
  externalGroupName: string
  externalGroupSyncStatus: string
  memberCount: number
  organizationSelectionType: string
  databaseRoute: string
  membersRoute: string
  organizationCount: number
  organizationsRoute: string
  displayOrgsPage: boolean
}

export interface StafftoolsBusinessTeamsItemPayload {
  // Update this type to reflect the data you place in payload in Rails
  enterpriseTeam: EnterpriseTeam
  businessSlug: string
}

export function StafftoolsBusinessTeamsItemView() {
  const payload = useRoutePayload<StafftoolsBusinessTeamsItemPayload>()

  const pluralize = (count: number, noun: string, suffix = 's') => `${count} ${noun}${count !== 1 ? suffix : ''}`
  if (payload.enterpriseTeam.isMembersManagementEnabled) {
    return (
      <>
        <header className="Subhead">
          <Heading as="h2" className="Subhead-heading" data-testid={`heading`}>
            {payload.enterpriseTeam.name}
          </Heading>
        </header>

        <Box sx={{mb: 5}}>
          <table
            className="site-admin-table"
            style={{border: `var(--borderColor-default)`, borderRadius: `var(--borderRadius-medium)`}}
          >
            <tbody>
              <tr>
                <th style={{color: `var(--fgColor-default)`}}>ID</th>
                <th data-testid={`team-id`}>{payload.enterpriseTeam.id}</th>
              </tr>
              <tr>
                <th style={{color: `var(--fgColor-default)`}}>Name</th>
                <th data-testid={`team-name`}>{payload.enterpriseTeam.name}</th>
              </tr>
              <tr>
                <th style={{color: `var(--fgColor-default)`}}>Slug</th>
                <th data-testid={`team-slug`}>{payload.enterpriseTeam.slug}</th>
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
              Linked External Group
            </Heading>
          </header>
          {payload.enterpriseTeam.externalGroupCount > 0 ? (
            <table
              className="site-admin-table"
              style={{border: `var(--borderColor-default)`, borderRadius: `var(--borderRadius-medium)`}}
            >
              <tbody>
                <tr>
                  <th style={{color: `var(--fgColor-default)`}}>
                    <Link href={payload.enterpriseTeam.externalGroupPath} data-testid={`external-group-link`}>
                      {payload.enterpriseTeam.externalGroupName}
                    </Link>
                  </th>
                  <th style={{color: `var(--fgColor-default)`}} data-testid={`external-group-members-count`}>
                    {pluralize(payload.enterpriseTeam.externalGroupMemberCount, 'member')}
                  </th>
                  <th style={{color: `var(--fgColor-default)`}} data-testid={`external-group-sync-status`}>
                    {payload.enterpriseTeam.externalGroupSyncStatus}
                  </th>
                </tr>
              </tbody>
            </table>
          ) : (
            <p>No linked external groups found.</p>
          )}
        </Box>

        <Box sx={{mb: 5}}>
          <header className="Subhead">
            <Heading as="h3" className="Subhead-heading">
              Team details
            </Heading>
          </header>
          <table
            className="site-admin-table"
            style={{border: `var(--borderColor-default)`, borderRadius: `var(--borderRadius-medium)`}}
          >
            <tbody>
              <tr>
                <th style={{color: `var(--fgColor-default)`}}>Members</th>
                <th data-testid={`member-count`}>
                  <Link href={payload.enterpriseTeam.membersRoute} data-testid={`members-link`}>
                    {pluralize(payload.enterpriseTeam.memberCount, 'member')}
                  </Link>
                </th>
              </tr>
              {payload.enterpriseTeam.displayOrgsPage && (
                <tr>
                  <th style={{color: `var(--fgColor-default)`}}>Assigned organizations</th>
                  <th data-testid={`assigned-organizations-count`}>
                    <Link href={payload.enterpriseTeam.organizationsRoute} data-testid={`assigned-organizations-link`}>
                      {pluralize(payload.enterpriseTeam.organizationCount, 'organization')}
                    </Link>
                  </th>
                </tr>
              )}
            </tbody>
          </table>
        </Box>
      </>
    )
  } else {
    return (
      <>
        <header className="Subhead">
          <Heading as="h2" className="Subhead-heading" data-testid={`heading`}>
            {payload.enterpriseTeam.name}
          </Heading>
        </header>

        <Box sx={{mb: 5}}>
          <table
            className="site-admin-table"
            style={{border: `var(--borderColor-default)`, borderRadius: `var(--borderRadius-medium)`}}
          >
            <tbody>
              <tr>
                <th style={{color: `var(--fgColor-default)`}}>ID</th>
                <th data-testid={`team-id`}>{payload.enterpriseTeam.id}</th>
              </tr>
              <tr>
                <th style={{color: `var(--fgColor-default)`}}>Name</th>
                <th data-testid={`team-name`}>{payload.enterpriseTeam.name}</th>
              </tr>
              <tr>
                <th style={{color: `var(--fgColor-default)`}}>Slug</th>
                <th data-testid={`team-slug`}>{payload.enterpriseTeam.slug}</th>
              </tr>
              <tr>
                <th style={{color: `var(--fgColor-default)`}}>External Groups</th>
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
          <table
            className="site-admin-table"
            style={{border: `var(--borderColor-default)`, borderRadius: `var(--borderRadius-medium)`}}
          >
            <tbody>
              <tr>
                <th style={{color: `var(--fgColor-default)`}}>Direct members</th>
                <th data-testid={`direct-member-count`}>
                  <Link href={payload.enterpriseTeam.membersRoute} data-testid={`members-link`}>
                    {pluralize(payload.enterpriseTeam.memberCount, 'member')}
                  </Link>
                </th>
              </tr>
              <tr>
                <th style={{color: `var(--fgColor-default)`}}>External group members</th>
                <th data-testid={`external-member-count`}>
                  {pluralize(payload.enterpriseTeam.externalGroupMemberCount, 'external group member')}
                </th>
              </tr>
              {payload.enterpriseTeam.displayOrgsPage && (
                <tr>
                  <th style={{color: `var(--fgColor-default)`}}>Assigned organizations</th>
                  <th data-testid={`assigned-organizations-count`}>
                    <Link href={payload.enterpriseTeam.organizationsRoute} data-testid={`assigned-organizations-link`}>
                      {pluralize(payload.enterpriseTeam.organizationCount, 'organization')}
                    </Link>
                  </th>
                </tr>
              )}
            </tbody>
          </table>
        </Box>
      </>
    )
  }
}
