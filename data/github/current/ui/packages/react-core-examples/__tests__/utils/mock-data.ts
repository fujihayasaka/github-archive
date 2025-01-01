import {signChannel} from '@github-ui/use-alive/test-utils'

import type {Label} from '../../data-types'

const reactCoreExamplesLayoutRoute = {
  login: 'testuser',
}

export function getReactCoreExamplesLayoutRoutePayload() {
  return {
    payload: {
      reactCoreExamplesLayoutRoute,
    },
    meta: {title: null},
  }
}

export function getReactCoreExamplesRoutePayload() {
  return {
    payload: {
      reactCoreExamplesLayoutRoute,
      reactCoreExamplesIndexRoute: {},
    },
    meta: {
      title: 'React Core Examples',
    },
  }
}

export function getReactCoreExamplesDependentDataPayload() {
  return {
    payload: {
      reactCoreExamplesLayoutRoute,
      reactCoreExamplesDependentDataRoute: {
        id: '1',
        login: 'testuser',
        avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
      },
    },
    meta: {
      title: 'Dependent Data',
    },
  }
}

export function getReactCoreExamplesDependentDataDeferredPayload() {
  return {
    issues: getIssues(10, 'open'),
  }
}

export function getReactCoreExamplesEnrichedDataPayload() {
  return {
    payload: {
      reactCoreExamplesLayoutRoute,
      reactCoreExamplesEnrichedDataRoute: {
        user: {
          id: '1',
          login: 'testuser',
          avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
        },
        pulls: getPulls(10, 'open'),
      },
    },
    meta: {
      title: 'Enriched Data',
    },
  }
}

export function getReactCoreExamplesEnrichedDataDeferredPayload() {
  return {
    pulls: getPulls(10, 'open', [{id: '1', name: 'label', color: '000000'}]),
  }
}

export function getReactCoreExamplesFeatureFlagRoutePayload(isFlagEnabled = false) {
  return {
    payload: {
      reactCoreExamplesLayoutRoute,
    },
    meta: {title: 'Feature Flag'},
    appPayload: {
      enabled_features: {
        react_core_examples_feature_flag: isFlagEnabled,
      },
    },
  }
}

const reactCoreExamplesLiveDataRoute = {
  aliveChannel: signChannel('alive-channel'),
  pull: {
    id: '1',
    title: 'Test Pull',
    url: '/pull/1',
    labels: [
      {id: '1', name: 'label', nameHTML: 'label', color: '000000', url: '/label/1', description: 'label description'},
    ],
  },
}

export const getReactCoreExamplesLiveDataPayload = () => {
  return {
    payload: {
      reactCoreExamplesLayoutRoute,
      reactCoreExamplesLiveDataRoute,
    },
  }
}

const reactCoreExamplesMutationsRoute = {
  userStatus: {
    message: '🦆 When one feels like a duck, one is happy!',
  },
}

export function getReactCoreExamplesMutationsPayload() {
  return {
    payload: {
      reactCoreExamplesLayoutRoute,
      reactCoreExamplesMutationsRoute,
    },
    meta: {title: 'ReactCoreExamples Mutations'},
  }
}

const reactCoreExamplesPaginationRoute = {
  login: 'testuser',
  count: 20,
}

export function getReactCoreExamplesPaginationPayload() {
  return {
    payload: {
      reactCoreExamplesLayoutRoute,
      reactCoreExamplesPaginationRoute,
    },
    meta: {title: 'ReactCoreExamples Pagination'},
  }
}

export function getReactCoreExamplesPaginationDeferredPayload(state: 'open' | 'closed' = 'open') {
  return {
    issues: getIssues(10, state),
  }
}

export function getReactCoreExamplesSharedComponentsPayload() {
  return {
    payload: {
      reactCoreExamplesLayoutRoute,
      reactCoreExamplesSharedComponentsRoute: {
        userStatus: {
          message: '🦆 When one feels like a duck, one is happy!',
          emoji: '🦆',
          expiresAt: new Date().toISOString(),
          limitedAvailability: false,
        },
      },
    },
    meta: {title: 'ReactCoreExamples Shared Components'},
  }
}

export function getIssues(count: number, state: 'open' | 'closed') {
  return Array.from({length: count}, (_, i) => ({
    id: `${i + 1}`,
    title: `${state === 'closed' ? 'Closed' : 'Open'} Issue ${i + 1}`,
    state,
    url: `/issue/${i + 1}`,
  }))
}

export function getPulls(count: number, state: 'open' | 'closed', labels: Label[] = []) {
  return Array.from({length: count}, (_, i) => ({
    id: `${i + 1}`,
    title: `${state === 'closed' ? 'Closed' : 'Open'} Pull ${i + 1}`,
    state,
    url: `/pull/${i + 1}`,
    labels,
  }))
}
