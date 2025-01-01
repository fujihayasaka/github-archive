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
import type {StafftoolsBusinessTeamOrganizationsPayload} from '../routes/stafftools/StafftoolsBusinessTeamOrganizationsView'

export function getBusinessTeamsTableViewRoutePayload(): BusinessTeamsListViewPayload {
  return {
    enterpriseSlug: 'acme-corp',
    enterpriseTeamsLimit: 5,
    enterpriseTeamsLimitReached: false,
    canCreateNewTeams: true,
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
        linkedToExternalGroup: false,
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
    viewerPermissions: {
      read_enterprise_custom_enterprise_role: true,
      write_enterprise_custom_enterprise_role: true,
    },
  }
}

export function getBusinessTeamsTableViewNoAssignmentRoutePayload(): BusinessTeamsListViewPayload {
  return {
    enterpriseSlug: 'acme-corp',
    enterpriseTeamsLimit: 5,
    enterpriseTeamsLimitReached: false,
    canCreateNewTeams: true,
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
        linkedToExternalGroup: false,
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
    viewerPermissions: {
      read_enterprise_custom_enterprise_role: false,
      write_enterprise_custom_enterprise_role: false,
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
      organizationSelectionType: 'selected',
      linkedToExternalGroup: false,
    },
    currentView: 'Members',
    viewerPermissions: {
      read_enterprise_custom_enterprise_role: true,
      write_enterprise_custom_enterprise_role: true,
    },
  }
}

export function getBusinessTeamHeaderNoAssignmentPermissions(): BusinessTeamHeaderViewProps {
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
      organizationSelectionType: 'selected',
      linkedToExternalGroup: false,
    },
    currentView: 'Members',
    viewerPermissions: {
      read_enterprise_custom_enterprise_role: false,
      write_enterprise_custom_enterprise_role: false,
    },
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
      organizationSelectionType: 'selected',
      linkedToExternalGroup: false,
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
    viewerPermissions: {
      read_enterprise_custom_enterprise_role: true,
      write_enterprise_custom_enterprise_role: true,
    },
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
      organizationSelectionType: 'selected',
      linkedToExternalGroup: false,
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
    viewerPermissions: {
      read_enterprise_custom_enterprise_role: true,
      write_enterprise_custom_enterprise_role: true,
    },
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
      organizationSelectionType: 'selected',
      linkedToExternalGroup: false,
    },
    roleAssignments: [],
    fgps: {},
    viewerPermissions: {
      read: true,
      write: true,
      read_enterprise_custom_enterprise_role: true,
      write_enterprise_custom_enterprise_role: true,
    },
  }
}

export function getBusinessTeamOrganizationsViewRoutePayload(): BusinessTeamOrganizationsViewPayload {
  return {
    orgAssignmentsEnabled: true,
    enterpriseTeamsOrgAssignmentLimit: 500,
    enterpriseSlug: 'acme-corp',
    enterpriseTeam: {
      id: 1,
      name: 'Acme Engineering',
      slug: 'acme-engineering',
      description: "Acme Corp's engineering team",
      totalMemberCount: 2,
      totalOrganizationCount: 3,
      totalRoleCount: 3,
      organizationSelectionType: 'selected',
      linkedToExternalGroup: false,
    },
    meta: {
      pageSize: 30,
      page: 1,
    },
    organizations: [
      {
        id: 1,
        name: 'A first org',
        login: 'first-org',
        avatarUrl: 'http://alambic.github.localhost/avatars/orgs/1',
        description: 'The first org',
      },
      {
        id: 2,
        name: 'The other org',
        login: 'other-org',
        avatarUrl: 'http://alambic.github.localhost/avatars/orgs/2',
        description: null,
      },
      {
        id: 3,
        name: 'The third org',
        login: 'third-org',
        avatarUrl: 'http://alambic.github.localhost/avatars/orgs/3',
        description: null,
      },
    ],
    viewerPermissions: {
      read_enterprise_custom_enterprise_role: true,
      write_enterprise_custom_enterprise_role: true,
    },
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
      organizationSelectionType: 'selected',
      linkedToExternalGroup: false,
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
      read_enterprise_custom_enterprise_role: true,
      write_enterprise_custom_enterprise_role: true,
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
    alreadyAssignedOrgCount: 0,
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
        name: 'A first org',
        login: 'first-org',
        avatarUrl: 'http://alambic.github.localhost/avatars/orgs/1',
        description: 'The first org',
      },
      {
        id: 2,
        name: 'The other org',
        login: 'other-org',
        avatarUrl: 'http://alambic.github.localhost/avatars/orgs/2',
        description: null,
      },
      {
        id: 3,
        name: 'The third org',
        login: 'third-org',
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
      selectedOrganizationsCount: 3,
    },
    isMembersManagementEnabled: true,
    isEnterpriseManagedUser: true,
    canUseIdpGroups: true,
    idpGroupsUrl: '/enterprises/acme-corp/teams/group_suggestions',
    baseUrl: '/enterprises/acme-corp/teams',
    preventEditOrganizations: false,
    maxTeamNameLength: 100,
    maxTeamDescriptionLength: 350,
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
    maxTeamNameLength: 100,
    maxTeamDescriptionLength: 350,
    isMembersManagementEnabled: true,
    isEnterpriseManagedUser: true,
    canUseIdpGroups: true,
    idpGroupsUrl: '/enterprises/acme-corp/teams/group_suggestions',
  }
}

export function getStafftoolsBusinessTeamsListViewRoutePayload(): StafftoolsBusinessTeamsListPayload {
  return {
    enterpriseTeams: [
      {
        isMembersManagementEnabled: false,
        id: 1,
        name: 'justice league',
        externalGroupCount: 0,
        externalGroupSyncStatus: '',
        memberCount: 1,
        organizationSelectionType: 'disabled',
        showRoute: '/enterprise_teams/1',
      },
      {
        isMembersManagementEnabled: false,
        id: 2,
        name: 'justice league 2',
        externalGroupCount: 2,
        externalGroupSyncStatus: '',
        memberCount: 2,
        organizationSelectionType: 'all',
        showRoute: '/enterprise_teams/2',
      },
      {
        isMembersManagementEnabled: false,
        id: 3,
        name: 'another',
        externalGroupCount: 2,
        externalGroupSyncStatus: '',
        memberCount: 2,
        organizationSelectionType: 'disabled',
        showRoute: '/enterprise_teams/3',
      },
    ],
    totalEntries: 3,
    totalPages: 2,
    businessSlug: 'github',
  }
}

export function getStafftoolsBusinessTeamsListViewRoutePayloadEnterpriseTeamMembersManagementFFEnabled(): StafftoolsBusinessTeamsListPayload {
  return {
    enterpriseTeams: [
      {
        isMembersManagementEnabled: true,
        id: 1,
        name: 'justice league',
        externalGroupCount: 0,
        externalGroupSyncStatus: 'Not linked',
        memberCount: 1,
        organizationSelectionType: '',
        showRoute: '/enterprise_teams/1',
      },
      {
        isMembersManagementEnabled: true,
        id: 2,
        name: 'justice league 2',
        externalGroupCount: 1,
        externalGroupSyncStatus: 'Synced',
        memberCount: 2,
        organizationSelectionType: '',
        showRoute: '/enterprise_teams/2',
      },
      {
        isMembersManagementEnabled: true,
        id: 3,
        name: 'another',
        externalGroupCount: 2,
        externalGroupSyncStatus: 'Out of sync',
        memberCount: 2,
        organizationSelectionType: '',
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
      isMembersManagementEnabled: false,
      id: 1,
      name: 'justice league',
      slug: 'justice-league',
      externalGroupCount: 0,
      externalGroupMemberCount: 0,
      externalGroupName: '',
      externalGroupPath: '',
      externalGroupSyncStatus: '',
      memberCount: 2,
      organizationSelectionType: 'disabled',
      organizationCount: 0,
      databaseRoute: '/enterprise_teams/1/database',
      membersRoute: '/enterprise_teams/1/members',
      organizationsRoute: `/stafftools/enterprises/your-business-slug/enterprise_teams/1/organizations`,
      displayOrgsPage: true,
    },
    businessSlug: 'github',
  }
}

export function getStafftoolsBusinessTeamsItemViewRoutePayloadEnterpriseTeamMembersManagementFFEnabled(): StafftoolsBusinessTeamsItemPayload {
  return {
    enterpriseTeam: {
      isMembersManagementEnabled: true,
      id: 1,
      name: 'justice league',
      slug: 'justice-league',
      externalGroupCount: 1,
      externalGroupMemberCount: 2,
      externalGroupName: 'justice-league-external-group',
      externalGroupPath: '/stafftools/enterprises/github/external_groups/13',
      externalGroupSyncStatus: 'Synced',
      memberCount: 2,
      organizationSelectionType: 'disabled',
      organizationCount: 0,
      databaseRoute: '/enterprise_teams/1/database',
      membersRoute: '/enterprise_teams/1/members',
      organizationsRoute: `/stafftools/enterprises/your-business-slug/enterprise_teams/1/organizations`,
      displayOrgsPage: false,
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
export function getStafftoolsBusinessTeamOrganizationsViewRoutePayload(): StafftoolsBusinessTeamOrganizationsPayload {
  return {
    totalEntries: 2,
    totalPages: 2,
    enterpriseTeam: {
      id: 1,
      name: 'justice league',
      showRoute: '/enterprise_teams/1',
    },
    orgs: [
      {
        id: 1,
        name: 'monalisa',
        showRoute: '/monalisa',
      },
      {
        id: 2,
        name: 'Jane Doe',
        showRoute: '/jane-doe',
      },
    ],
    businessSlug: 'github',
  }
}

export function getStafftoolsBusinessTeamOrganizationsViewRoutePayloadNoOrg(): StafftoolsBusinessTeamOrganizationsPayload {
  return {
    totalEntries: 0,
    totalPages: 0,
    enterpriseTeam: {
      id: 1,
      name: 'justice league',
      showRoute: '/enterprise_teams/1',
    },
    orgs: [],
    businessSlug: 'github',
  }
}

export function getStafftoolsBusinessTeamMembersViewRoutePayloadNoMembers(): StafftoolsBusinessTeamMembersPayload {
  return {
    totalEntries: 0,
    totalPages: 0,
    enterpriseTeam: {
      id: 1,
      name: 'justice league',
      memberCount: 0,
      showRoute: '/enterprise_teams/1',
    },
    members: [],
    businessSlug: 'github',
  }
}

export function getStafftoolsBusinessTeamsListViewRoutePayloadNoTeams(): StafftoolsBusinessTeamsListPayload {
  return {
    totalEntries: 0,
    totalPages: 0,
    businessSlug: 'github',
    enterpriseTeams: [],
  }
}
