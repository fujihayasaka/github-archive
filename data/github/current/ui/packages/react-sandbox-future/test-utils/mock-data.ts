export function getReactSandboxFutureIndexRoutePayload() {
  return {
    payload: {
      reactSandboxFutureLayoutRoute: {
        mainQuery: {someField: 'SERVER DATA – layoutRoute', tabCounts: {'1': 1, '2': 2, '3': 3}},
      },
      reactSandboxFutureIndexRoute: {
        mainQuery: {someField: 'SERVER DATA – indexRoute'},
        title: 'React Sandbox Index',
      },
    },
  }
}

export function getReactSandboxFutureIdRoutePayload(id: string) {
  return {
    payload: {
      reactSandboxFutureLayoutRoute: {
        mainQuery: {someField: 'SERVER DATA – layoutRoute', tabCounts: {'1': 1, '2': 2, '3': 3}},
      },
      reactSandboxFutureIdRoute: {
        mainQuery: {someField: 'SERVER DATA – idRoute'},
        title: `React Sandbox ID ${id}`,
      },
    },
  }
}

export function getReactSandboxDeferredPayload(id: string) {
  return {
    someDeferredField: `SERVER DATA – deferred payload for ${id}`,
    deferredLoadedAt: new Date().toDateString(),
  }
}
