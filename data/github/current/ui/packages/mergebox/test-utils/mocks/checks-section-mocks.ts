import {StatusCheckGenerator} from '../object-generators/status-check'
import type {StatusChecksPageData} from '../../page-data/payloads/status-checks'
import {aliveChannels} from './alive-channels-mock'

/**
 * Preset states for the ChecksSection of the mergebox
 */
export const checksSectionPendingState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [{count: 1, state: 'PENDING'}],
    combinedState: 'PENDING',
  },
  statusChecks: [StatusCheckGenerator({state: 'PENDING'})],
}

export const checksSectionPendingWithFailureState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [
      {count: 1, state: 'PENDING'},
      {count: 1, state: 'FAILURE'},
      {count: 1, state: 'SUCCESS'},
    ],
    combinedState: 'PENDING_FAILED',
  },
  statusChecks: [
    StatusCheckGenerator({state: 'PENDING'}),
    StatusCheckGenerator({state: 'SUCCESS'}),
    StatusCheckGenerator({state: 'FAILURE'}),
  ],
}

export const checksSectionPendingFromQueuedState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [{count: 1, state: 'QUEUED'}],
    combinedState: 'PENDING',
  },
  statusChecks: [StatusCheckGenerator({state: 'QUEUED'})],
}

export const checksSectionPassingState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [{count: 2, state: 'SUCCESS'}],
    combinedState: 'PASSED',
  },
  statusChecks: [StatusCheckGenerator({state: 'SUCCESS'}), StatusCheckGenerator({state: 'SUCCESS'})],
}

export const checksSectionPassingWithSkippedState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [{count: 1, state: 'SKIPPED'}],
    combinedState: 'PASSED',
  },
  statusChecks: [StatusCheckGenerator({state: 'SKIPPED'})],
}

export const checksSectionFailedState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [{count: 2, state: 'FAILURE'}],
    combinedState: 'FAILED',
  },
  statusChecks: [StatusCheckGenerator({state: 'FAILURE'}), StatusCheckGenerator({state: 'FAILURE'})],
}

export const checksSectionSomeFailedState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [
      {count: 1, state: 'SUCCESS'},
      {count: 1, state: 'FAILURE'},
    ],
    combinedState: 'SOME_FAILED',
  },
  statusChecks: [StatusCheckGenerator({state: 'SUCCESS'}), StatusCheckGenerator({state: 'FAILURE'})],
}

export const checksSectionFailedTimedOutState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [{count: 1, state: 'TIMED_OUT'}],
    combinedState: 'FAILED',
  },
  statusChecks: [StatusCheckGenerator({state: 'TIMED_OUT'})],
}

export const checksSectionNoChecksState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [],
    combinedState: 'PASSED',
  },
  statusChecks: [],
}

export const checksSectionPendingAndWaitingState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [{count: 1, state: 'PENDING'}],
    combinedState: 'PENDING',
  },
  statusChecks: [
    StatusCheckGenerator({state: 'PENDING'}),
    {
      ...StatusCheckGenerator({
        state: 'EXPECTED',
        displayName: 'enterprise-results',
        description: 'Waiting for status to be reported',
        avatarUrl: '',
      }),
      targetUrl: null,
    },
  ],
}

export const checksSectionRequiredChecksFailingState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [
      {count: 1, state: 'FAILURE'},
      {count: 1, state: 'PENDING'},
    ],
    combinedState: 'PENDING',
  },
  statusChecks: [
    StatusCheckGenerator({state: 'PENDING', isRequired: false}),
    StatusCheckGenerator({state: 'FAILURE', isRequired: true}),
  ],
}

export const checksSectionNonRequiredChecksFailingState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [
      {count: 1, state: 'FAILURE'},
      {count: 1, state: 'PENDING'},
    ],
    combinedState: 'PENDING',
  },
  statusChecks: [
    StatusCheckGenerator({state: 'PENDING', isRequired: false}),
    StatusCheckGenerator({state: 'FAILURE', isRequired: false}),
  ],
}

export const checksSectionNonRequiredChecksPassingState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [{count: 2, state: 'SUCCESS'}],
    combinedState: 'PASSED',
  },
  statusChecks: [
    StatusCheckGenerator({state: 'SUCCESS', isRequired: false}),
    StatusCheckGenerator({state: 'SUCCESS', isRequired: false}),
  ],
}

export const checksSectionRequiredChecksPassingState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [
      {count: 1, state: 'SUCCESS'},
      {count: 1, state: 'SKIPPED'},
      {count: 1, state: 'NEUTRAL'},
    ],
    combinedState: 'PASSED',
  },
  statusChecks: [
    StatusCheckGenerator({state: 'SUCCESS', isRequired: true}),
    StatusCheckGenerator({state: 'NEUTRAL', isRequired: true}),
    StatusCheckGenerator({state: 'SKIPPED', isRequired: true}),
  ],
}

export const checksSectionRequiredChecksPassingStateNonRequiredFailing: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [
      {count: 1, state: 'SKIPPED'},
      {count: 1, state: 'PENDING'},
      {count: 1, state: 'FAILURE'},
    ],
    combinedState: 'SOME_FAILED',
  },
  statusChecks: [
    StatusCheckGenerator({state: 'SUCCESS', isRequired: true}),
    StatusCheckGenerator({state: 'PENDING', isRequired: false}),
    StatusCheckGenerator({state: 'FAILURE', isRequired: false}),
  ],
}

export const allRequiredChecksSuccessful: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [
      {count: 1, state: 'SKIPPED'},
      {count: 2, state: 'SUCCESS'},
      {count: 1, state: 'NEUTRAL'},
    ],
    combinedState: 'PASSED',
  },
  statusChecks: [
    StatusCheckGenerator({state: 'SUCCESS', isRequired: true}),
    StatusCheckGenerator({state: 'SUCCESS', isRequired: false}),
    StatusCheckGenerator({state: 'SKIPPED', isRequired: false}),
    StatusCheckGenerator({state: 'NEUTRAL', isRequired: false}),
  ],
}

export const checksSectionNonRequiredChecksPassingSkippedNeutralState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [
      {count: 2, state: 'SUCCESS'},
      {count: 1, state: 'SKIPPED'},
      {count: 2, state: 'NEUTRAL'},
    ],
    combinedState: 'PASSED',
  },
  statusChecks: [
    StatusCheckGenerator({state: 'SUCCESS', isRequired: false}),
    StatusCheckGenerator({state: 'SUCCESS', isRequired: false}),
    StatusCheckGenerator({state: 'SKIPPED', isRequired: false}),
    StatusCheckGenerator({state: 'NEUTRAL', isRequired: false}),
    StatusCheckGenerator({state: 'NEUTRAL', isRequired: false}),
  ],
}

export const checksSectionWithMultipleOfEveryState: StatusChecksPageData = {
  aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
  statusRollup: {
    summary: [
      {count: 2, state: 'ACTION_REQUIRED'},
      {count: 2, state: 'CANCELLED'},
      {count: 2, state: 'COMPLETED'},
      {count: 2, state: 'ERROR'},
      {count: 2, state: 'EXPECTED'},
      {count: 2, state: 'FAILURE'},
      {count: 2, state: 'IN_PROGRESS'},
      {count: 4, state: 'NEUTRAL'},
      {count: 2, state: 'PENDING'},
      {count: 2, state: 'QUEUED'},
      {count: 2, state: 'REQUESTED'},
      {count: 4, state: 'SKIPPED'},
      {count: 2, state: 'STALE'},
      {count: 2, state: 'STARTUP_FAILURE'},
      {count: 2, state: 'SUCCESS'},
      {count: 2, state: 'TIMED_OUT'},
      {count: 2, state: 'WAITING'},
    ],
    combinedState: 'FAILED',
  },
  statusChecks: [
    StatusCheckGenerator({state: 'ACTION_REQUIRED'}),
    StatusCheckGenerator({state: 'ACTION_REQUIRED'}),
    StatusCheckGenerator({state: 'CANCELLED'}),
    StatusCheckGenerator({state: 'CANCELLED'}),
    StatusCheckGenerator({state: 'COMPLETED'}),
    StatusCheckGenerator({state: 'COMPLETED'}),
    StatusCheckGenerator({state: 'ERROR'}),
    StatusCheckGenerator({state: 'ERROR'}),
    StatusCheckGenerator({state: 'EXPECTED'}),
    StatusCheckGenerator({state: 'EXPECTED'}),
    StatusCheckGenerator({state: 'FAILURE'}),
    StatusCheckGenerator({state: 'FAILURE'}),
    StatusCheckGenerator({state: 'IN_PROGRESS'}),
    StatusCheckGenerator({state: 'IN_PROGRESS'}),
    StatusCheckGenerator({state: 'NEUTRAL'}),
    StatusCheckGenerator({state: 'NEUTRAL'}),
    StatusCheckGenerator({state: 'NEUTRAL'}),
    StatusCheckGenerator({state: 'NEUTRAL'}),
    StatusCheckGenerator({state: 'PENDING'}),
    StatusCheckGenerator({state: 'PENDING'}),
    StatusCheckGenerator({state: 'QUEUED'}),
    StatusCheckGenerator({state: 'QUEUED'}),
    StatusCheckGenerator({state: 'REQUESTED'}),
    StatusCheckGenerator({state: 'REQUESTED'}),
    StatusCheckGenerator({state: 'SKIPPED'}),
    StatusCheckGenerator({state: 'SKIPPED'}),
    StatusCheckGenerator({state: 'SKIPPED'}),
    StatusCheckGenerator({state: 'SKIPPED'}),
    StatusCheckGenerator({state: 'STALE'}),
    StatusCheckGenerator({state: 'STALE'}),
    StatusCheckGenerator({state: 'STARTUP_FAILURE'}),
    StatusCheckGenerator({state: 'STARTUP_FAILURE'}),
    StatusCheckGenerator({state: 'SUCCESS'}),
    StatusCheckGenerator({state: 'SUCCESS'}),
    StatusCheckGenerator({state: 'TIMED_OUT'}),
    StatusCheckGenerator({state: 'TIMED_OUT'}),
    StatusCheckGenerator({state: 'WAITING'}),
    StatusCheckGenerator({state: 'WAITING'}),
  ],
}
