import {
  CopilotForBusinessSeatPolicy,
  SeatType,
  type CSVUploadPayload,
  type CSVUser,
  type CopilotSeatAssignable,
  type CopilotForBusinessPayload,
  type CopilotForBusinessPoliciesPayload,
  type CopilotSeatAssignment,
  type UserAssignable,
  type Requester,
  type FeatureRequestInfo,
  type UserEmailAssignable,
} from '../types'

type RecursivePartial<T> = {
  [P in keyof T]?: T[P] extends Array<infer U>
    ? Array<RecursivePartial<U>>
    : T[P] extends object | undefined
      ? RecursivePartial<T[P]>
      : T[P]
}

export const User: CopilotSeatAssignable = {
  id: 123,
  login: 'Blah123',
  display_name: 'The Blah',
  avatar_url: 'https://avatars.githubusercontent.com/u/0?v=4',
}

export const UserNoDisplayName: CopilotSeatAssignable = {
  id: 124,
  login: 'Blah124',
  avatar_url: 'https://avatars.githubusercontent.com/u/0?v=4',
}

export const Team: CopilotSeatAssignable = {
  id: 111,
  login: 'Team Blah',
  slug: 'team-blah',
  avatar_url: 'https://avatars.githubusercontent.com/u/0?v=4',
  combined_slug: 'blah/team-blah',
  member_count: 6,
  member_ids: [123, 124],
}

export const EnterpriseTeam: CopilotSeatAssignable = {
  id: 111,
  login: 'Sweet Enterprise Team',
  slug: 'sweet-enterprise-team',
  mapping_id: 123,
  member_count: 2,
  member_ids: [123, 124],
}

export const EmailInvite: CopilotSeatAssignable = {
  id: 126,
  email: 'blah@email.com',
}

export const PendingCancellationUser: CopilotSeatAssignable = {
  id: 100,
  login: 'cancelled',
  display_name: 'The Cancelled',
  avatar_url: 'https://avatars.githubusercontent.com/u/0?v=4',
}

export const UserInviteSeat: CopilotSeatAssignment = {
  assignable_type: SeatType.OrganizationInvitation,
  last_activity_at: '1969-01-01T00:00:00Z',
  assignable: {
    id: 125,
    invitee: User,
    invitee_id: 987,
    login: 'User125',
  },
}

export const ExpiredUserInviteSeat: CopilotSeatAssignment = {
  assignable_type: SeatType.OrganizationInvitation,
  last_activity_at: '1969-01-01T00:00:00Z',
  invitation_expired: true,
  assignable: {
    id: 126,
    invitee: User,
    login: 'User126',
  },
}

export const EmailInviteSeat: CopilotSeatAssignment = {
  assignable_type: SeatType.OrganizationInvitation,
  last_activity_at: '1969-01-01T00:00:00Z',
  assignable: EmailInvite,
}

export const UserSeat: CopilotSeatAssignment = {
  assignable_type: SeatType.User,
  last_activity_at: '2021-01-01T00:00:00Z',
  assignable: {
    id: 999,
    login: 'Blah999',
    display_name: 'The Blah',
    avatar_url: 'https://avatars.githubusercontent.com/u/0?v=4',
  },
}

export const PendingCancelledSeat: CopilotSeatAssignment = {
  assignable_type: SeatType.User,
  last_activity_at: '2021-01-01T00:00:00Z',
  assignable: PendingCancellationUser,
  pending_cancellation_date: '2021-02-01T00:00:00Z',
}

export const UserSeatNoDisplayName: CopilotSeatAssignment = {
  assignable_type: SeatType.User,
  last_activity_at: '2022-01-01T00:00:00Z',
  assignable: UserNoDisplayName,
}

export const TeamSeat: CopilotSeatAssignment = {
  assignable_type: SeatType.Team,
  last_activity_at: '2023-01-01T00:00:00Z',
  assignable: Team,
}

export const EnterpriseTeamSeat: CopilotSeatAssignment = {
  assignable_type: SeatType.EnterpriseTeam,
  last_activity_at: '2023-01-01T00:00:00Z',
  assignable: EnterpriseTeam,
}

export function getSeatManagementRoutePayload(): CopilotForBusinessPayload {
  return {
    public_code_suggestions_configured: true,
    policy: CopilotForBusinessSeatPolicy.EnabledForAll,
    organization: {
      name: 'test-org',
      id: 1,
      billable: true,
      has_seat: false,
      add_seat_link: null,
      copilot_enabled: true,
    },
    business: {
      name: 'test-business',
      slug: 'test-business',
    },
    seats: {
      seats: [UserSeat, TeamSeat, EmailInviteSeat, UserInviteSeat],
      count: 4,
      licenses: {
        user_ids: [UserSeat.assignable.id, ...(Team.member_ids?.filter(id => id !== undefined) ?? [])],
        team_ids: [TeamSeat.assignable.id],
        invite_user_ids: [UserInviteSeat.assignable.id],
        invite_emails: [EmailInviteSeat.assignable?.email].filter(ie => ie !== undefined),
      },
    },
    seat_breakdown: {
      seats_assigned: 3,
      seats_billed: 3,
      seats_pending: 2,
      description: '3 seats assigned (3 seats billed / 2 seats pending)',
    },
    seat_assignments: 5,
    can_add_teams: true,
    render_trial_expired_banner: false,
    members_count: 4,
    can_allow_to_assign_seats_on_business: false,
    plan_text: 'Business',
    next_billing_date: '2023-12-31T00:00:00',
    featureRequestInfo: testFeatureRequestInfo,
    render_pending_downgrade_banner: false,
    display_activity: true,
    adoption_metrics: {
      total: 10,
      active: 2,
      inactive: 3,
      dormant: 4,
    },
    render_copilot_insights_banner: false,
  }
}

export function getSeatManagementRoutePayloadWithoutSeats() {
  const payload = getSeatManagementRoutePayload()

  return {
    ...payload,
    seats: {
      seats: [],
      count: 0,
      licenses: {
        user_ids: [],
        team_ids: [],
        invite_user_ids: [],
        invite_emails: [],
      },
    },
    seat_breakdown: {
      seats_assigned: 0,
      seats_billed: 0,
      seats_pending: 0,
      description: '0 seats assigned (0 seats billed / 0 seats pending)',
    },
    seat_assignments: 0,
  }
}

export function getSeatManagementRoutePayloadWithCancelled() {
  const payload = getSeatManagementRoutePayload()

  return {
    ...payload,
    seats: {...payload.seats, ...{seats: [PendingCancelledSeat, ...payload.seats.seats], count: 5}},
  }
}

export function getSeatManagementRoutePayloadWithDisplayActivityFalse() {
  const payload = getSeatManagementRoutePayload()

  return {
    ...payload,
    display_activity: false,
  }
}

export function getSeatManagementRoutePayloadWithTrial(): CopilotForBusinessPayload {
  const startDate = new Date()
  // Not sure if this is actually when I created my test data, or if it's just the default date?
  startDate.setUTCHours(7, 0, 0, 0)

  const endDate = new Date(startDate.getDate() + 30)
  endDate.setUTCHours(7, 0, 0, 0)

  return {
    ...getSeatManagementRoutePayload(),
    business_trial: {
      started: true,
      ended: false,
      has_trial: true,
      upgradable: true,
      cancelable: true,
      days_left: 30,
      started_at: startDate.toISOString(),
      ends_at: endDate.toISOString(),
      trial_length: 30,
      active: true,
      pending: false,
      expired: false,
      copilot_plan: 'business',
      belongs_to_trial_business_account: false,
    },
  }
}

export function getSeatManagementRoutePayloadWithRequester() {
  const payload = getSeatManagementRoutePayload()

  return {
    ...payload,
    seats: {
      seats: [...payload.seats.seats],
      count: 4,
      pending_requests: getPendingRequests(),
      licenses: payload.seats.licenses,
    },
  }
}

export function getPendingRequests() {
  return {
    requesters: [requester],
    count: 1,
  }
}

export const requester: Requester = {
  id: 1,
  display_login: 'user1',
  profile_name: 'User Name',
  requested_at: '2021-01-01T00:00:00Z',
}

export const CsvUser: CSVUser = {
  id: 123,
  email: 'blah@email.com',
  email_input_csv: false,
  display_login: 'Blah',
  profile_name: 'The Blah',
  avatar: 'https://avatars.githubusercontent.com/u/0?v=4',
  is_new_user: false,
}

export const CsvUploadPayload: CSVUploadPayload = {
  new_users: 2,
  github_users: [CsvUser],
  email_users: ['newEmail@email.com'],
  found_errors: [],
  total_users: 2,
}

export const AssignableUser: UserAssignable = {
  id: 123,
  avatar_url: 'https://avatars.githubusercontent.com/u/0?v=4',
  display_login: 'Blah',
  org_member: true,
  profile_name: 'The Blah',
  type: SeatType.User,
  email: 'jean@gmail.com',
}

export const AssignableEmailUser: UserEmailAssignable = {
  id: 123,
  avatar_url: 'https://avatars.githubusercontent.com/u/0?v=4',
  display_login: 'Blah',
  org_member: true,
  profile_name: 'The Blah',
  email: 'jean@gmail.com',
  email_input_csv: true,
  type: SeatType.User,
}

export const AssignableUserWithFeatureRequest: UserAssignable = {
  ...AssignableUser,
  feature_request: {
    id: 123,
    requested_at: '2021-01-01T00:00:00Z',
  },
}

export const testFeatureRequestInfo: FeatureRequestInfo = {
  isEnterpriseRequest: false,
  showFeatureRequest: false,
  alreadyRequested: false,
  dismissed: false,
  featureName: 'copilot_for_business',
  requestPath: '/path/to/request',
  latestUsernameRequests: ['user1'],
  amountOfUserRequests: 1,
}

export function makePoliciesRoutePayload(
  overrides: RecursivePartial<CopilotForBusinessPoliciesPayload> = {},
): CopilotForBusinessPoliciesPayload {
  function aspect(name: string) {
    return {
      configurable: true,
      manages: `${name}-manages`,
      options: [
        {
          id: 'option1',
          title: `option 1 ${name}`,
          description: 'option 1 description',
          value: 'option1',
          selected: false,
        },
        {
          id: 'option2',
          title: `option 2 ${name}`,
          description: 'option 2 description',
          value: 'option2',
          selected: true,
        },
      ],
    }
  }

  return simplemerge(
    {
      org_name: 'my-org',
      editor_chat: aspect('editor_chat'),
      mobile_chat: aspect('mobile_chat'),
      snippy: aspect('snippy'),
      cli: aspect('cli'),
      copilot_for_dotcom: aspect('copilot_for_dotcom'),
      bing_github_chat: aspect('bing_github_chat'),
      editor_preview_features: aspect('editor_preview_features'),
      a_chat: aspect('a_chat'),
      a_f: aspect('a_f'),
      afos: aspect('afos'),
      al: aspect('al'),
      g_chat: aspect('g_chat'),
      g_tf: aspect('g_tf'),
      gtff: aspect('gtff'),
      o1: aspect('o1'),
      o3: aspect('o3'),
      o_ff: aspect('o_ff'),
      o_fm: aspect('o_fm'),
      o_f: aspect('o_f'),
      o_t: aspect('o_t'),
      ofo: aspect('ofo'),
      overages: aspect('overages'),
      copilot_usage_metrics_policy: aspect('copilot_usage_metrics_policy'),
      swe_agent: aspect('swe_agent'),
      mcp: aspect('mcp'),
      docsUrls: {
        generalPrivacyStatement: 'https://docs/general/privacy/statement',
      },
      desktop: aspect('desktop'),
    },
    overrides,
  )
}

// --

function simplemerge<T>(target: RecursivePartial<T>, source: RecursivePartial<T>): T {
  const output = {...target}

  for (const key of Object.keys(source) as Array<keyof T>) {
    if (source[key] instanceof Object && !Array.isArray(source[key])) {
      if (!(key in target)) {
        Object.assign(output, {[key]: source[key]})
      } else {
        // @ts-expect-error this recursive check needs additional typesafety now
        output[key] = simplemerge(
          // @ts-expect-error undefined is not checked for
          target[key],
          source[key],
        )
      }
    } else {
      Object.assign(output, {[key]: source[key]})
    }
  }

  return output as T
}
