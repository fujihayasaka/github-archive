import type {PullRequestRuleMetadata, RequiredReviewer} from '../RequiredReviewers'

// Helpers for required reviewers
const mockRequiredReviewerIds = ['T_101', 'T_102', 'T_103', 'T_104'] as string[]
export const mockRequiredReviewers = [
  {
    reviewer_id: mockRequiredReviewerIds[0],
    minimum_approvals: 3,
    file_patterns: ['**/*.md'],
  },
  {
    reviewer_id: mockRequiredReviewerIds[1],
    minimum_approvals: 4,
    file_patterns: ['db/**'],
  },
  {
    reviewer_id: mockRequiredReviewerIds[3],
    minimum_approvals: 1,
    file_patterns: ['*'],
  },
] as RequiredReviewer[]

export const mockRequiredReviewerMetadata = {
  requiredReviewers: {
    [mockRequiredReviewerIds[0] as string]: {
      id: 1,
      globalRelayId: mockRequiredReviewerIds[0],
      type: 'Team',
      name: 'repos',
    },
    [mockRequiredReviewerIds[1] as string]: {
      id: 2,
      globalRelayId: mockRequiredReviewerIds[1],
      type: 'Team',
      name: 'databases',
    },
    [mockRequiredReviewerIds[3] as string]: {
      id: 4,
      globalRelayId: mockRequiredReviewerIds[3],
      type: 'Team',
      name: 'GitAuth',
    },
  },
} as PullRequestRuleMetadata

export const mockRequiredReviewersWithMissingTeam = [
  ...mockRequiredReviewers.slice(0, 2),
  {
    reviewer_id: mockRequiredReviewerIds[2],
    minimum_approvals: 2,
    file_patterns: ['**/*.md', '**/*.js'],
  },
  mockRequiredReviewers[2],
]

export const mockRequiredReviewerMetadataWithMissingTeam = {
  requiredReviewers: {
    ...mockRequiredReviewerMetadata.requiredReviewers,
    [mockRequiredReviewerIds[2] as string]: {
      id: null,
      globalRelayId: mockRequiredReviewerIds[2],
      type: null,
      name: null,
    },
  },
}

// Suggestions to return in reviewer select panel
export const mockRequiredReviewerSuggestions = [
  ...Object.values(mockRequiredReviewerMetadata.requiredReviewers).map(reviewer => ({
    ...reviewer,
    global_relay_id: reviewer.globalRelayId,
    preferredAvatarUrl: '',
  })),
  {
    id: 5,
    global_relay_id: 'T_105',
    type: 'Team',
    name: 'Security',
  },
  {
    id: 6,
    global_relay_id: 'T_106',
    type: 'Team',
    name: 'pull-requests',
  },
]

export const requiredReviewerField = {
  name: 'required_reviewers',
  display_name: 'Required review by specific teams',
  description:
    'A collection of reviewers and associated file patterns. Each reviewer has a list of file patterns which determine the files that reviewer is required to review.',
  type: 'array',
  required: false,
  beta: true,
  content_type: 'object',
  content_object: {
    name: 'required_reviewer_configuration',
    fields: [
      {
        type: 'string',
        name: 'reviewer_id',
        display_name: 'Reviewer ID',
        description: 'Node ID of the team which must review changes to matching files.',
        required: true,
        beta: false,
      },
      {
        name: 'minimum_approvals',
        display_name: 'Minimum approvals',
        description:
          'Minimum number of approvals required from the specified team. If set to zero, the team will be added to the pull request but approval is optional.',
        type: 'integer',
        required: true,
        beta: false,
        default_value: 0,
      },
      {
        type: 'array',
        content_type: 'string',
        name: 'file_patterns',
        display_name: 'File patterns',
        description:
          'Pull requests which change matching files must be approved by the specified team. File patterns use the same syntax as `.gitignore` files.',
        content_object: undefined,
        required: true,
        beta: false,
      },
    ],
  },
}
