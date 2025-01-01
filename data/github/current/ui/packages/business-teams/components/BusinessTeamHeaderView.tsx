import {useNavigate} from '@github-ui/use-navigate'
import {IdBadgeIcon, OrganizationIcon, PencilIcon, PeopleIcon} from '@primer/octicons-react'
import {Breadcrumbs, Button, Stack, UnderlineNav} from '@primer/react'
import {pathingForTeam, teamsPath} from '../paths'
import styles from '../styles/BusinessTeamHeaderView.module.css'
import type {EnterpriseTeam} from '../types'

type BusinessTeamHeaderTab = 'Members' | 'Organizations' | 'Assigned roles'

export interface BusinessTeamHeaderViewProps {
  orgAssignmentsEnabled: boolean
  enterpriseSlug: string
  enterpriseTeam: EnterpriseTeam
  currentView: BusinessTeamHeaderTab
}

export function BusinessTeamHeaderView(props: BusinessTeamHeaderViewProps) {
  const navigate = useNavigate()
  const teamName = props.enterpriseTeam.name
  const navPathing = pathingForTeam(props.enterpriseSlug, props.enterpriseTeam.slug)

  return (
    <div>
      <Breadcrumbs>
        <Breadcrumbs.Item data-testid="breadcrumb-teams-link" href={teamsPath(props.enterpriseSlug)}>
          Enterprise Teams
        </Breadcrumbs.Item>
        <Breadcrumbs.Item data-testid="breadcrumb-team-name" selected>
          {teamName}
        </Breadcrumbs.Item>
      </Breadcrumbs>

      <div>
        <Stack direction="horizontal" justify="space-between">
          <h1 data-hpc data-testid="overview-team-name">
            {teamName}
          </h1>
          <Button leadingVisual={PencilIcon} onClick={() => navigate(navPathing.edit)} className={styles.editButton}>
            Edit
          </Button>
        </Stack>
        <Stack>
          <p data-testid="overview-team-description">{props.enterpriseTeam.description}</p>
        </Stack>
      </div>

      <UnderlineNav aria-label="Enterprise team details" sx={{pl: 0}}>
        {navItem('Members', navPathing.members, props.enterpriseTeam.totalMemberCount)}
        {props.orgAssignmentsEnabled &&
          navItem('Organizations', navPathing.organizations, props.enterpriseTeam.totalOrganizationCount)}
        {navItem('Assigned roles', navPathing.roles, props.enterpriseTeam.totalRoleCount)}
      </UnderlineNav>
    </div>
  )

  function navItem(title: BusinessTeamHeaderTab, href: string, count: number) {
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
