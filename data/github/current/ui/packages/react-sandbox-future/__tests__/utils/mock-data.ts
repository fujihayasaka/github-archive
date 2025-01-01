export function getReactSandboxLayoutRoutePayload() {
  return {
    payload: {
      reactSandboxFutureLayoutRoute: {someField: 'SERVER DATA – layoutRoute', tabCounts: {'1': 1, '2': 2, '3': 3}},
    },
    meta: {title: null},
  }
}

export function getReactSandboxFutureIndexRoutePayload(leafRouteOnly: boolean) {
  const indexPayload = {
    reactSandboxFutureIndexRoute: {someField: 'SERVER DATA – indexRoute'},
  }
  const parentPayloads = leafRouteOnly ? {} : getReactSandboxLayoutRoutePayload().payload
  const titleString = 'React Sandbox Index'
  return {
    payload: {
      ...indexPayload,
      ...parentPayloads,
    },
    meta: {title: titleString},
  }
}

export function getReactSandboxFutureIdRoutePayload(id: string, leafRouteOnly: boolean) {
  const idPayload = {reactSandboxFutureIdRoute: {someField: 'SERVER DATA – idRoute'}}
  const parentPayloads = leafRouteOnly ? {} : getReactSandboxLayoutRoutePayload().payload
  const titleString = `React Sandbox ID ${id}`
  return {
    payload: {
      ...idPayload,
      ...parentPayloads,
    },
    meta: {title: titleString},
  }
}

export function getReactSandboxDeferredPayload(id: string) {
  return {
    someDeferredField: `SERVER DATA – deferred payload for ${id}`,
    deferredLoadedAt: new Date().toDateString(),
  }
}

export function getReactSandBoxDashboardPayload() {
  return {
    meta: {},
    payload: {
      reactSandboxFutureDashboardRoute: {
        user: 'testuser',
      },
    },
  }
}

type DashboardIssueArgs = {
  state?: 'open' | 'closed'
  count?: {
    open: number
    closed: number
  }
}

type DashboardDiscussionArgs = {
  open: number
  closed: number
}

export function getReactSandBoxDashboardDeferredPayload({
  openIssues = 2,
  openPulls = 2,
}: {
  openIssues: number
  openPulls: number
}) {
  return {
    tabCounts: {openIssues, openPulls},
  }
}

export function getReactSandBoxDashboardIssuesPayload(args: DashboardIssueArgs, leafRouteOnly: boolean) {
  const issuesPayload = {
    reactSandboxFutureDashboardIssuesRoute: args.count,
  }

  const parentPayloads = leafRouteOnly
    ? {}
    : {...getReactSandboxLayoutRoutePayload().payload, ...getReactSandBoxDashboardPayload().payload}
  const titleString = 'ReactSandboxFuture Dashboard Issues'

  return {
    payload: {
      ...issuesPayload,
      ...parentPayloads,
    },
    meta: {title: titleString},
  }
}

export function getReactSandBoxDashboardDiscussionsPayload(args: DashboardDiscussionArgs, leafRouteOnly: boolean) {
  const discussionsPayload = {
    reactSandboxFutureDashboardDiscussionsRoute: {open: args.open, closed: args.closed},
  }

  const parentPayloads = leafRouteOnly
    ? {}
    : {...getReactSandboxLayoutRoutePayload().payload, ...getReactSandBoxDashboardPayload().payload}
  const titleString = 'ReactSandboxFuture Dashboard Discussions'

  return {
    payload: {
      ...discussionsPayload,
      ...parentPayloads,
    },
    meta: {title: titleString},
  }
}

export function getReactSandBoxDashboardIssuesDeferredIssuesPayload(args: DashboardIssueArgs) {
  const state = args?.state ?? 'open'
  const count = args.count?.[state] ?? 0
  return {
    issues: getDashboardIssues(count, state),
  }
}

export function getDashboardIssues(count: number, state: NonNullable<DashboardIssueArgs['state']>) {
  return Array.from({length: count}, (_, i) => ({
    id: `${i + 1}`,
    title: `${state === 'closed' ? 'Closed' : 'Open'} Issue ${i + 1}`,
    state,
    url: `/issue/${i + 1}`,
  }))
}
