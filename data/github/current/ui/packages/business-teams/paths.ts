export type NavPathing = {
  base: string
  edit: string
  members: string
  organizations: string
  roles: string
}

export function teamsPath(enterpriseSlug: string): string {
  return `/enterprises/${enterpriseSlug}/teams`
}

export function pathingForTeam(enterpriseSlug: string, teamSlug: string): NavPathing {
  const teamPath = `/enterprises/${enterpriseSlug}/teams/${teamSlug}`

  return {
    base: teamPath,
    edit: `${teamPath}/edit`,
    members: `${teamPath}/members`,
    organizations: `${teamPath}/organizations`,
    roles: `${teamPath}/roles`,
  }
}
