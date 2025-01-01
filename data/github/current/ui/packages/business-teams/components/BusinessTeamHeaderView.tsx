import {useNavigate} from '@github-ui/use-navigate'
import {IdBadgeIcon, OrganizationIcon, PencilIcon, PeopleIcon} from '@primer/octicons-react'
import {Breadcrumbs, Button, Label, Stack, UnderlineNav} from '@primer/react'
import {pathingForTeam, teamsPath} from '../paths'
import styles from '../styles/BusinessTeamHeaderView.module.css'
import type {EnterpriseTeam} from '../types'

type BusinessTeamHeaderTab = 'Members' | 'Organizations' | 'Assigned roles'

export interface BusinessTeamHeaderViewProps {
  orgAssignmentsEnabled: boolean
  viewerPermissions: {[permission: string]: boolean}
  enterpriseSlug: string
  enterpriseTeam: EnterpriseTeam
  currentView: BusinessTeamHeaderTab
}

export function BusinessTeamHeaderView(props: BusinessTeamHeaderViewProps) {
  const navigate = useNavigate()
  const teamName = props.enterpriseTeam.name
  const navPathing = pathingForTeam(props.enterpriseSlug, props.enterpriseTeam.slug)
  const organizationsCounter =
    props.enterpriseTeam.organizationSelectionType === 'all' ? 'All' : props.enterpriseTeam.totalOrganizationCount

  return (
    <div>
      <Breadcrumbs sx={{mb: 2}}>
        <Breadcrumbs.Item data-testid="breadcrumb-teams-link" href={teamsPath(props.enterpriseSlug)}>
          Enterprise teams
        </Breadcrumbs.Item>
        <Breadcrumbs.Item data-testid="breadcrumb-team-name" selected>
          {teamName}
        </Breadcrumbs.Item>
      </Breadcrumbs>

      <Stack direction="horizontal" gap="normal" align="center" justify="space-between" className="mb-3">
        <Stack direction="vertical" gap="none" justify="space-between">
          <div className="d-flex flex-items-center">
            <h1 data-hpc data-testid="overview-team-name" className="mr-2">
              {teamName}
            </h1>
            {props.enterpriseTeam.linkedToExternalGroup && <Label data-testid="idp-group-label">IdP group</Label>}
          </div>
          <p className={styles.teamDescription} data-testid="overview-team-description">
            {props.enterpriseTeam.description}
          </p>
        </Stack>
        <Button leadingVisual={PencilIcon} onClick={() => navigate(navPathing.edit)} className={styles.editButton}>
          Edit
        </Button>
      </Stack>

      <UnderlineNav aria-label="Enterprise team details" sx={{pl: 0}}>
        {navItem('Members', navPathing.members, props.enterpriseTeam.totalMemberCount)}
        {props.orgAssignmentsEnabled && navItem('Organizations', navPathing.organizations, organizationsCounter)}
        {props.viewerPermissions['read_enterprise_custom_enterprise_role'] &&
          navItem('Assigned roles', navPathing.roles, props.enterpriseTeam.totalRoleCount)}
      </UnderlineNav>
    </div>
  )

  function navItem(title: BusinessTeamHeaderTab, href: string, count: number | string) {
    const aria: {} = title === props.currentView ? {'aria-current': 'page'} : {}

    return (
      <UnderlineNav.Item data-testid={`nav-${title}`} href={href} counter={count} icon={navIcon(title)} {...aria}>
        {title}
      </UnderlineNav.Item>
    )
  }
}

function navIcon(section: BusinessTeamHeaderTab) {
  switch (section) {
    case 'Members':
      return <PeopleIcon size={16} />
    case 'Organizations':
      return <OrganizationIcon size={16} />
    case 'Assigned roles':
      return <IdBadgeIcon size={16} />
  }
}
