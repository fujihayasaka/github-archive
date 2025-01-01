import type {BusinessTeamsListViewPayload} from '../routes/BusinessTeamsListView'
import type {BusinessTeamMembersViewPayload} from '../routes/BusinessTeamMembersView'
import type {BusinessTeamOrganizationsViewPayload} from '../routes/BusinessTeamOrganizationsView'
import type {BusinessTeamRolesViewPayload} from '../routes/BusinessTeamRolesView'
import type {BusinessTeamsCreateAndEditPayload} from '../routes/BusinessTeamsCreateEditView'
import type {AddUserToTeamButtonProps} from '../components/AddUserToTeamButton'
import type {BusinessTeamHeaderViewProps} from '../components/BusinessTeamHeaderView'
import type {OrganizationSelectPanelProps, OrganizationSuggestions} from '../helpers/OrganizationSelectPanel'
import type {StafftoolsBusinessTeamsListPayload} from '../routes/stafftools/StafftoolsBusinessTeamsListView'
import type {StafftoolsBusinessTeamsItemPayload} from '../routes/stafftools/StafftoolsBusinessTeamsItemView'
import type {StafftoolsBusinessTeamMembersPayload} from '../routes/stafftools/StafftoolsBusinessTeamMembersView'

export function getBusinessTeamsTableViewRoutePayload(): BusinessTeamsListViewPayload {
  return {
    enterpriseSlug: 'acme-corp',
    enterpriseTeamsLimit: 5,
    enterpriseTeamsLimitReached: false,
    isOwner: true,
    enterpriseTeams: [
      {
        name: 'Acme Engineering',
        id: 1,
        memberCount: 15,
        slug: 'acme-engineering',
        description: "Acme Corp's engineering team",
        viewTeamUrl: '/enterprises/acme-corp/teams/acme-engineering',
        editTeamUrl: '/enterprises/acme-corp/teams/acme-engineering/edit',
      },
    ],
    createTeamUrl: '/enterprises/acme-corp/new_team',
    totalTeamsCount: 1,
    meta: {
      filter: '',
      page: 1,
      pageSize: 10,
      sortOption: 'Last added',
      orderOption: 'Ascending',
    },
  }
}

export function getBusinessTeamHeaderViewProps(): BusinessTeamHeaderViewProps {
  return {
    orgAssignmentsEnabled: true,
    enterpriseSlug: 'acme-corp',
    enterpriseTeam: {
      id: 1,
      name: 'Acme Engineering',
      slug: 'acme-engineering',
      description: "Acme Corp's engineering team",
      totalMemberCount: 2,
      totalOrganizationCount: 1,
      totalRoleCount: 3,
    },
    currentView: 'Members',
  }
}

export function getBusinessTeamMembersViewRoutePayloadEmpty(): BusinessTeamMembersViewPayload {
  return {
    orgAssignmentsEnabled: true,
    enterpriseSlug: 'acme-corp',
    enterpriseTeamMembersLimit: 100,
    enterpriseTeam: {
      id: 1,
      name: 'Acme Engineering',
      slug: 'acme-engineering',
      description: "Acme Corp's engineering team",
      totalMemberCount: 0,
      totalOrganizationCount: 1,
      totalRoleCount: 0,
    },
    meta: {
      filter: '',
      queryMemberCount: 0,
      page: 1,
      pageSize: 10,
      sortOption: 'Name',
      orderOption: 'Ascending',
      membersAllowedToAdd: 100,
      memberLimitReached: false,
    },
    members: [],
  }
}

export function getBusinessTeamMembersViewRoutePayload(): BusinessTeamMembersViewPayload {
  return {
    orgAssignmentsEnabled: true,
    enterpriseSlug: 'acme-corp',
    enterpriseTeamMembersLimit: 100,
    enterpriseTeam: {
      id: 1,
      name: 'Acme Engineering',
      slug: 'acme-engineering',
      description: "Acme Corp's engineering team",
      totalMemberCount: 2,
      totalOrganizationCount: 1,
      totalRoleCount: 0,
    },
    meta: {
      filter: '',
      queryMemberCount: 2,
      page: 1,
      pageSize: 10,
      sortOption: 'Name',
      orderOption: 'Ascending',
      membersAllowedToAdd: 98,
      memberLimitReached: false,
    },
    members: [
      {
        displayLogin: 'hubot',
        id: 1,
        profileName: 'hubot',
        avatarUrl: 'http://alambic.github.localhost/avatars/u/2',
      },
      {
        displayLogin: 'monalisa',
        id: 2,
        profileName: 'monalisa octocat',
        avatarUrl: 'http://alambic.github.localhost/avatars/u/1',
      },
    ],
  }
}

export function getBusinessTeamRolesViewRoutePayloadEmpty(): BusinessTeamRolesViewPayload {
  return {
    orgAssignmentsEnabled: true,
    enterpriseSlug: 'acme-corp',
    enterpriseTeam: {
      id: 1,
      name: 'Acme Engineering',
      slug: 'acme-engineering',
      description: "Acme Corp's engineering team",
      totalMemberCount: 2,
      totalOrganizationCount: 1,
      totalRoleCount: 0,
    },
    roleAssignments: [],
    fgps: {},
    viewerPermissions: {
      read: true,
      write: true,
    },
  }
}

export function getBusinessTeamOrganizationsViewRoutePayload(): BusinessTeamOrganizationsViewPayload {
  return {
    orgAssignmentsEnabled: true,
    enterpriseSlug: 'acme-corp',
    enterpriseTeam: {
      id: 1,
      name: 'Acme Engineering',
      slug: 'acme-engineering',
      description: "Acme Corp's engineering team",
      totalMemberCount: 2,
      totalOrganizationCount: 1,
      totalRoleCount: 3,
    },
    organizations: [
      {
        id: 1,
        name: 'A first org',
        avatarUrl: 'http://alambic.github.localhost/avatars/orgs/1',
        description: 'The first org',
      },
      {
        id: 2,
        name: 'The other org',
        avatarUrl: 'http://alambic.github.localhost/avatars/orgs/2',
        description: null,
      },
      {
        id: 3,
        name: 'The third org',
        avatarUrl: 'http://alambic.github.localhost/avatars/orgs/3',
        description: null,
      },
    ],
  }
}

export function getBusinessTeamRolesViewRoutePayload(): BusinessTeamRolesViewPayload {
  return {
    orgAssignmentsEnabled: true,
    enterpriseSlug: 'acme-corp',
    enterpriseTeam: {
      id: 1,
      name: 'Acme Engineering',
      slug: 'acme-engineering',
      description: "Acme Corp's engineering team",
      totalMemberCount: 2,
      totalOrganizationCount: 1,
      totalRoleCount: 3,
    },
    roleAssignments: [
      {
        role: {id: 1, name: 'admin role title', description: 'admin role description', octicon: 'shield'},
        directly_assigned: true,
        indirect_assignments: [],
      },
      {
        role: {id: 2, name: 'manager role title', description: 'manager role description', octicon: 'people'},
        directly_assigned: true,
        indirect_assignments: [],
      },
    ],
    fgps: {
      1: {
        Enterprise: {admin: ['permissionA']},
        Organization: {},
        Repository: {},
      },
      2: {
        Enterprise: {manager: ['permissionB']},
        Organization: {},
        Repository: {},
      },
    },
    viewerPermissions: {
      read: true,
      write: true,
    },
  }
}

export function getAddUserToTeamButtonProps(): AddUserToTeamButtonProps {
  return {
    inactive: false,
    enterpriseSlug: 'acme-corp',
    teamSlug: 'team-slug',
    addMembersToTable: jest.fn(),
    membersAllowedToAdd: 100,
    teamMembersLimit: 100,
  }
}

export function getOrganizationSelectPanelProps(): OrganizationSelectPanelProps {
  return {
    enterpriseSlug: 'acme-corp',
    initialSelectedIds: [],
    onOrganizationsAdded: jest.fn(),
    enterpriseTeamsOrgAssignmentLimit: 100,
  }
}

export function getOrganizationSuggestionsPayload(): OrganizationSuggestions {
  return {
    organizations: [
      {
        id: 1,
        name: 'A fisrt org',
        avatarUrl: 'http://alambic.github.localhost/avatars/orgs/1',
        description: 'The fisrt org',
      },
      {
        id: 2,
        name: 'The other org',
        avatarUrl: 'http://alambic.github.localhost/avatars/orgs/2',
        description: null,
      },
      {
        id: 3,
        name: 'The third org',
        avatarUrl: 'http://alambic.github.localhost/avatars/orgs/3',
        description: null,
      },
    ],
    totalAvailableCount: 6,
  }
}

export function getBusinessTeamRoutePayload(): BusinessTeamsCreateAndEditPayload {
  return {
    enterpriseSlug: 'acme-corp',
    allOrgsCount: 6,
    enterpriseTeamsLimit: 5,
    enterpriseTeamsLimitReached: false,
    enterpriseTeamsOrgAssignmentLimit: 100,
    canSelectAllOrganizations: true,
    canSelectOrganizationAssignmentType: true,
    enterpriseTeam: {
      name: 'Acme Engineering',
      slug: 'acme-engineering',
      description: "Acme Corp's engineering team",
      organizationSelectionType: 'selected',
      url: '/enterprises/acme-corp/teams/acme-engineering',
      selectedOrganizations: [
        {
          id: 1,
          name: 'acme-corp-1',
          avatarUrl: 'https://avatars.githubusercontent.com/u/1',
          description: '',
        },
        {
          id: 2,
          name: 'acme-corp-2',
          avatarUrl: 'https://avatars.githubusercontent.com/u/2',
          description: '',
        },
        {
          id: 3,
          name: 'acme-corp-3',
          avatarUrl: 'https://avatars.githubusercontent.com/u/3',
          description: '',
        },
      ],
    },
    baseUrl: '/enterprises/acme-corp/teams',
    preventEditOrganizations: false,
  }
}

export function getBusinessTeamRoutePayloadNoTeam(): BusinessTeamsCreateAndEditPayload {
  return {
    enterpriseSlug: 'acme-corp',
    baseUrl: '/enterprises/acme-corp/teams',
    allOrgsCount: 0,
    enterpriseTeamsLimit: 5,
    enterpriseTeamsLimitReached: false,
    enterpriseTeamsOrgAssignmentLimit: 100,
    canSelectAllOrganizations: true,
    canSelectOrganizationAssignmentType: true,
    preventEditOrganizations: false,
  }
}

export function getStafftoolsBusinessTeamsListViewRoutePayload(): StafftoolsBusinessTeamsListPayload {
  return {
    enterpriseTeams: [
      {
        id: 1,
        name: 'justice league',
        externalGroupCount: 0,
        memberCount: 1,
        organizationSelectionType: 'disabled',
        showRoute: '/enterprise_teams/1',
      },
      {
        id: 2,
        name: 'justice league 2',
        externalGroupCount: 2,
        memberCount: 2,
        organizationSelectionType: 'all',
        showRoute: '/enterprise_teams/2',
      },
      {
        id: 3,
        name: 'another',
        externalGroupCount: 2,
        memberCount: 2,
        organizationSelectionType: 'all',
        showRoute: '/enterprise_teams/3',
      },
    ],
    totalEntries: 3,
    totalPages: 2,
    businessSlug: 'github',
  }
}

export function getStafftoolsBusinessTeamsItemViewRoutePayload(): StafftoolsBusinessTeamsItemPayload {
  return {
    enterpriseTeam: {
      id: 1,
      name: 'justice league',
      slug: 'justice-league',
      externalGroupCount: 0,
      externalGroupMemberCount: 0,
      memberCount: 2,
      organizationSelectionType: 'disabled',
      databaseRoute: '/enterprise_teams/1/database',
      membersRoute: '/enterprise_teams/1/members',
    },
    businessSlug: 'github',
  }
}

export function getStafftoolsBusinessTeamMembersViewRoutePayload(): StafftoolsBusinessTeamMembersPayload {
  return {
    totalEntries: 2,
    totalPages: 2,
    enterpriseTeam: {
      id: 1,
      name: 'justice league',
      memberCount: 1,
      showRoute: '/enterprise_teams/1',
    },
    members: [
      {
        id: 1,
        name: 'monalisa',
        login: 'monalisa',
        showRoute: '/monalisa',
      },
      {
        id: 2,
        name: 'Jane Doe',
        login: 'jane-doe',
        showRoute: '/jane-doe',
      },
    ],
    businessSlug: 'github',
  }
}
