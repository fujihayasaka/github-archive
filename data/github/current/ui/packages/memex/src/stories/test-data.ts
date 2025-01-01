import {
  addDays,
  addQuarters,
  getDaysInMonth,
  lastDayOfMonth,
  lastDayOfQuarter,
  lastDayOfYear,
  startOfMonth,
  startOfToday,
  startOfYear,
  subDays,
  subSeconds,
} from 'date-fns'
import cloneDeep from 'lodash-es/cloneDeep'
import invariant from 'tiny-invariant'

import {type MemexColumn, SystemColumnId} from '../client/api/columns/contracts/memex-column'
import type {MemexColumnData, TitleColumnData} from '../client/api/columns/contracts/storage'
import {IssueStateReason, type User} from '../client/api/common-contracts'
import type {MemexStatus} from '../client/api/memex/contracts'
import type {MemexItem} from '../client/api/memex-items/contracts'
import {type PageView, RoadmapZoomLevel, ViewTypeParam} from '../client/api/view/contracts'
import {not_typesafe_nonNullAssertion} from '../client/helpers/non-null-assertion'
import {
  CustomIterationColumnId,
  CustomReasonColumnId,
  DateDemoColumns,
  DefaultColumns,
  endDateColumn,
  EndDateColumnId,
  IterationDemoColumns,
  OnlyTitleVisibleColumns,
  P50Columns,
  P99Columns,
  PartialDataColumns,
  ReasonDemoColumns,
  RoadmapTestColumns,
  SecondaryIterationColumnId,
  SingleSelectDemoColumns,
  startDateColumn,
  StartDateColumnId,
  SubIssueDemoColumns,
  TitleColumnHiddenDefaultColumns,
  TrackedByDemoColumns,
  XssTestColumns,
} from '../mocks/data/columns'
import {generateItems, generateLeanHistoricalInsightsData} from '../mocks/data/generated'
import {createMockDraftIssue, createMockIssue, createMockRoadmapIssue} from '../mocks/data/issues'
import {getNextId} from '../mocks/data/mock-ids'
import {createMockPullRequest} from '../mocks/data/pull-requests'
import {getUser} from '../mocks/data/users'
import {autoFillViewServerProps, createView} from '../mocks/data/views'
import {deepCopy} from '../mocks/in-memory-database/utils'
import {
  ClosedIssueAsNotPlanned,
  ClosedIssueWithAllData,
  ClosedTrackedByIssue,
  DefaultClosedIssue,
  DefaultClosedPullRequest,
  DefaultDraftIssue,
  DefaultDraftPullRequest,
  DefaultMergedPullRequest,
  DefaultOpenIssue,
  DefaultOpenPullRequest,
  DefaultPullRequestFromMilestonelessRepository,
  DefaultRedactedItem,
  DefaultTrackedByIssue,
  DraftIssueLink,
  DraftIssueWithPartialColumns,
  IssueInPublicRepositoryWithCustomColumns,
  IssueInPublicRepositoryWithPartialColumns,
  IssueWithDifferentMilestone,
  IssueWithTwoAssignees,
  PullRequestWithDifferentMilestone,
  SecondIssueInPublicRepositoryWithCustomColumns,
  ThirdIssueInPublicRepositoryWithCustomColumns,
} from '../mocks/memex-items'

// This dataset is used for our most common integration tests: integrationTestsWithItems
// When adding support for a new column type, prefer updating these existing items with new column values
// rather than creating an entirely new dataset. This helps us write more consistent tests for column behavior.
const WithItems = [
  DefaultClosedIssue,
  DefaultClosedPullRequest,
  DefaultDraftIssue,
  ClosedIssueWithAllData,
  DefaultRedactedItem,
  DefaultOpenIssue,
  DefaultOpenPullRequest,
  DraftIssueLink,
]

// This dataset is used for the default memex story that renders in local development.
// When adding support for a new column type, it is recommended to update these items with new column values
// so that they can be easily tested in local development.
export const InitialItems = [
  createMockIssue({
    isOpen: true,
    issueNumber: 1176,
    title: 'Produce ag-Grid staging demo',
    priority: 2,
    virtualPriority: '0.199',
    assignees: ['mattpage', 'keisaacson'],
    status: 'In Progress',
    stage: 'In Progress',
    impact: 'High',
    tracks: {total: 6, completed: 2, percent: 33},
    subIssuesProgress: {id: 1, total: 6, completed: 2, percentCompleted: 33},
    parentIssueId: 1,
  }),

  createMockIssue({
    isOpen: true,
    issueNumber: 1175,
    title: 'Detail the work required to integrate with ag-Grid ',
    priority: 0,
    virtualPriority: '0',
    assignees: ['maxbeizer', 'shiftkey'],
    status: 'In Progress',
    stage: 'In Progress',
    impact: 'High',
    tracks: {total: 12, completed: 3, percent: 25},
    parentIssueId: 2,
  }),

  createMockPullRequest({
    isOpen: false,
    issueNumber: 1171,
    title: 'Don’t wrap Memex’s SelectMenu.Filter in a React.forwardRef',
    priority: 1,
    virtualPriority: '0.1',
    assignees: ['katestud', 'keisaacson', 'smockle'],
    status: 'Backlog',
    stage: 'Up Next',
    impact: 'Low',
    repositoryId: 3,
    milestoneId: 9,
    teamId: 2,
    labelIds: [22],
  }),

  createMockIssue({
    isOpen: true,
    issueNumber: 1173,
    title: 'UndoStore should be paused when new item row is focused',
    priority: 0,
    virtualPriority: '0',
    assignees: ['maxbeizer', 'olivia', 'iansan5653'],
    status: 'Backlog',
    stage: 'On Hold',
    impact: 'Low',
    repositoryId: 1,
    milestoneId: 2,
    teamId: 1,
    labelIds: [24],
    tracks: {total: 5, completed: 1, percent: 20},
    parentIssueId: 3,
  }),

  createMockPullRequest({
    isOpen: false,
    issueNumber: 1194,
    title: 'Fix cell size issues',
    priority: 0,
    virtualPriority: '0',
    assignees: [],
    status: 'Ready',
    stage: 'Up Next',
    impact: 'Medium',
    repositoryId: 3,
    milestoneId: 8,
  }),

  createMockIssue({
    isOpen: true,
    issueNumber: 1172,
    title: 'Store cell data in columnar rather than row-oriented fashion',
    priority: 0,
    virtualPriority: '0',
    assignees: [],
    status: 'Ready',
    stage: 'Up Next',
    impact: 'Medium',
    tracks: {total: 6, completed: 3, percent: 50},
  }),

  DefaultClosedIssue,
  createMockIssue({
    isOpen: true,
    issueNumber: 1170,
    title: 'Add color and name_html to serialized output of allowed values for a single select column',
    priority: 0,
    virtualPriority: '0',
    assignees: [],
    status: 'Ready',
    stage: 'Up Next',
    impact: 'Low',
  }),

  createMockIssue({
    isOpen: false,
    issueNumber: 1136,
    title: 'Increase specificity of return type of IReversibleOperation',
    priority: 0,
    virtualPriority: '0',
    assignees: ['lerebear'],
    status: 'Ready',
    stage: 'Up Next',
    impact: 'Low',
  }),

  createMockPullRequest({
    isOpen: false,
    issueNumber: 1190,
    title: 'Add Other Cell Renderers',
    priority: 0,
    virtualPriority: '0',
    assignees: ['mattpage'],
    status: 'Ready',
    stage: 'Closed',
    impact: 'Medium',
    isDraft: false,
    isMerged: true,
  }),

  createMockIssue({
    isOpen: true,
    issueNumber: 1150,
    title: 'Enable closing ColumnConfigurationMenu when clicking outside of the menu',
    priority: 0,
    virtualPriority: '0',
    assignees: [],
    status: 'Ready',
    stage: 'Up Next',
    impact: 'Low',
    repositoryId: 1,
    milestoneId: 2,
    teamId: 1,
    labelIds: [23],
    estimate: 0,
    stateReason: IssueStateReason.Reopened,
  }),

  createMockIssue({
    isOpen: true,
    issueNumber: 1145,
    title: 'Extract useUndoStore to encapsulate usage of the UndoStore',
    priority: 0,
    virtualPriority: '0',
    assignees: ['t-hugs'],
    status: 'Backlog',
    stage: 'On Hold',
    impact: 'Medium',
  }),

  createMockPullRequest({
    isOpen: false,
    issueNumber: 1155,
    title: 'run CI workflow for all pull requests, not just ones targeting main',
    priority: 0,
    virtualPriority: '0',
    assignees: ['lerebear'],
    status: 'Ready',
    stage: 'Up Next',
    impact: 'High',
    isDraft: false,
    isMerged: true,
  }),

  createMockIssue({
    isOpen: true,
    issueNumber: 3900,
    title: 'Persist column width per view rather than per project',
    priority: 2,
    virtualPriority: '0.199',
    assignees: ['jayspadie'],
    status: 'Ready',
    stage: 'Up Next',
    impact: 'Low',
  }),

  createMockIssue({
    isOpen: true,
    issueNumber: 1144,
    title: 'New column menu appears out of bounds once horizontal scrolling is introduced',
    priority: 0,
    virtualPriority: '0',
    assignees: [],
    status: 'Ready',
    stage: 'Up Next',
    impact: 'Medium',
    repositoryId: 3,
    milestoneId: 8,
  }),

  createMockIssue({
    isOpen: false,
    issueNumber: 1146,
    title: 'Use more efficient array operation in UndoStore',
    priority: 0,
    virtualPriority: '0',
    assignees: ['maxbeizer', 'iulia-b'],
    status: 'Backlog',
    stage: 'On Hold',
    impact: 'Medium',
    repositoryId: 2,
    milestoneId: 6,
    teamId: 1,
    labelIds: [24],
    estimate: 0,
    stateReason: IssueStateReason.NotPlanned,
  }),

  createMockIssue({
    isOpen: false,
    issueNumber: 1141,
    title: 'Skip unperformable operations in the UndoStore.',
    priority: 0,
    virtualPriority: '0',
    assignees: ['lerebear'],
    status: 'Backlog',
    stage: 'On Hold',
    impact: 'Medium',
  }),

  DefaultOpenIssue,
  createMockPullRequest({
    isOpen: true,
    issueNumber: 1183,
    title: 'Change theme to Balham',
    priority: 0,
    virtualPriority: '0',
    assignees: ['emplums'],
    status: 'Backlog',
    stage: 'On Hold',
    impact: 'Medium',
    isDraft: false,
    isMerged: false,
    repositoryId: 1,
    milestoneId: 4,
    teamId: 2,
    labelIds: [33],
  }),

  createMockIssue({
    isOpen: false,
    issueNumber: 1135,
    title: 'Add integration tests for undo/redo functionality',
    priority: 0,
    virtualPriority: '0',
    assignees: ['maxbeizer'],
    status: 'Backlog',
    stage: 'On Hold',
    impact: 'Medium',
    repositoryId: 1,
    milestoneId: 2,
    teamId: 1,
    labelIds: [23],
  }),

  createMockIssue({
    isOpen: false,
    issueNumber: 1133,
    title: 'Allow setting of single select column type value in MemexProjectItems#update',
    priority: 0,
    virtualPriority: '0',
    assignees: ['katestud'],
    status: 'In Progress',
    stage: 'In Progress',
    impact: 'Medium',
  }),

  createMockPullRequest({
    isOpen: true,
    issueNumber: 1193,
    title: 'Remove Duplicate Grid Options',
    priority: 0,
    virtualPriority: '0',
    assignees: ['keisaacson'],
    status: 'In Progress',
    stage: 'In Progress',
    impact: 'Medium',
  }),

  createMockIssue({
    isOpen: false,
    issueNumber: 1179,
    title: 'remove column duplication',
    priority: 0,
    virtualPriority: '0',
    assignees: ['emplums'],
    status: 'Backlog',
    stage: 'On Hold',
    impact: 'Medium',
    repositoryId: 1,
    milestoneId: 2,
    teamId: 2,
    labelIds: [23],
  }),

  DefaultOpenPullRequest,
  DefaultClosedPullRequest,
  createMockIssue({
    isOpen: false,
    issueNumber: 1165,
    title: 'set a lower timeout for the integration tests',
    priority: 0,
    virtualPriority: '0',
    assignees: ['shiftkey'],
    status: 'Ready',
    stage: 'Up Next',
    impact: 'Low',
    repositoryId: 1,
    milestoneId: 2,
    teamId: 2,
    labelIds: [22],
  }),

  DefaultMergedPullRequest,
  DefaultDraftPullRequest,
  createMockDraftIssue({
    title: {
      raw: 'Implement draft issue editor http://example.com',
      html: 'Implement draft issue editor <a href="http://example.com">http://example.com</a>',
    },

    priority: 0,
    virtualPriority: '0',
    status: 'Ready',
    stage: 'Up Next',
    impact: 'Medium',
  }),

  DefaultRedactedItem,
  createMockIssue({
    isOpen: true,
    issueNumber: 1162,
    title: 'Add novelty-aardvarks-reviewers as codeowners.',
    priority: 1,
    virtualPriority: '0.1',
    assignees: ['lerebear'],
    status: 'Backlog',
    stage: 'On Hold',
    impact: 'High',
    repositoryId: 1,
    milestoneId: 3,
    teamId: 1,
    labelIds: [24],
  }),
]

type IntegrationTestStoryData = {
  items: Array<MemexItem>
  columns: Array<MemexColumn>
  views: Array<PageView>
}

const createStoryDataFromColumns = (columns: Array<MemexColumn>) => ({
  columns,
  views: autoFillViewServerProps([
    createView({
      name: '',
      filter: '',
      layout: ViewTypeParam.Table,
      groupBy: [],
      verticalGroupBy: [],
      sortBy: [],
      priority: null,
      visibleFields: columns.filter(c => c.defaultColumn).map(c => c.databaseId),
      aggregationSettings: {hideItemsCount: false, sum: []},
      layoutSettings: {},
      sliceBy: {},
      sliceValue: null,
    }),
  ]),
})

export const withItemsData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(DefaultColumns),
  items: [...WithItems],
}

export const withBoardViewData: IntegrationTestStoryData = {
  columns: DefaultColumns,
  views: autoFillViewServerProps([
    createView({
      name: 'Project Board',
      filter: '',
      layout: ViewTypeParam.Board,
      groupBy: [],
      verticalGroupBy: [],
      sortBy: [],
      priority: null,
      visibleFields: DefaultColumns.filter(c => c.defaultColumn).map(c => c.databaseId),
      aggregationSettings: {
        hideItemsCount: false,
        sum: [],
      },
      layoutSettings: {},
      sliceBy: {},
      sliceValue: null,
    }),
  ]),
  items: [DefaultDraftIssue, ...InitialItems],
}

export const withCustomMilestoneData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(DefaultColumns),
  items: [
    DefaultClosedIssue,
    DefaultClosedPullRequest,
    DefaultDraftIssue,
    ClosedIssueWithAllData,
    DefaultRedactedItem,
    DefaultOpenIssue,
    DefaultOpenPullRequest,
    DraftIssueLink,
    IssueWithDifferentMilestone,
    PullRequestWithDifferentMilestone,
  ],
}

export const withCustomAssigneeData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(DefaultColumns),
  items: [
    ClosedIssueWithAllData,
    IssueWithDifferentMilestone,
    PullRequestWithDifferentMilestone,
    IssueWithTwoAssignees,
    DefaultOpenPullRequest,
  ],
}

export const withItemsWithoutMilestonesData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(DefaultColumns),
  items: [DefaultPullRequestFromMilestonelessRepository],
}

export const allItemsHaveMilestonesData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(DefaultColumns),
  items: [DefaultOpenIssue, DefaultClosedIssue, DefaultOpenPullRequest],
}

export const withCustomItemsData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(SingleSelectDemoColumns),
  items: [
    IssueInPublicRepositoryWithCustomColumns,
    SecondIssueInPublicRepositoryWithCustomColumns,
    ThirdIssueInPublicRepositoryWithCustomColumns,
  ],
}

export const withPartialItemsData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(PartialDataColumns),
  items: [IssueInPublicRepositoryWithPartialColumns, DraftIssueWithPartialColumns],
}

export const withTitleColumnHidden: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(TitleColumnHiddenDefaultColumns),
  items: [
    DefaultClosedIssue,
    DefaultClosedPullRequest,
    DefaultDraftIssue,
    ClosedIssueWithAllData,
    DefaultRedactedItem,
    DefaultOpenIssue,
    DefaultOpenPullRequest,
    DraftIssueLink,
  ],
}

export const withOnlyTitleColumnData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(OnlyTitleVisibleColumns),
  items: [
    DefaultClosedIssue,
    DefaultClosedPullRequest,
    DefaultDraftIssue,
    ClosedIssueWithAllData,
    DefaultRedactedItem,
    DefaultOpenIssue,
    DefaultOpenPullRequest,
    DraftIssueLink,
  ],
}

export const withDateColumnsData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(DateDemoColumns),
  items: [
    createMockIssue({
      isOpen: true,
      issueNumber: 1179,
      title: 'Remove column duplication',
      priority: 0,
      virtualPriority: '0',
      assignees: ['emplums'],
      status: 'Backlog',
      stage: 'On Hold',
      impact: 'Medium',
      repositoryId: 1,
      milestoneId: 4,
      teamId: 2,
      labelIds: [23],
    }),

    createMockIssue({
      isOpen: true,
      issueNumber: 1135,
      title: 'Add integration tests for undo/redo functionality',
      priority: 0,
      virtualPriority: '0',
      assignees: ['maxbeizer'],
      status: 'Backlog',
      stage: 'On Hold',
      impact: 'Medium',
      repositoryId: 1,
      milestoneId: 4,
      teamId: 1,
      labelIds: [23],
      estimate: 1,
      dueDate: new Date('2021-01-01').toISOString(),
    }),

    createMockIssue({
      isOpen: true,
      issueNumber: 1234,
      title: 'Searching for the `github` repo in a memex does not return `github/github` as a result',
      priority: 0,
      virtualPriority: '0',
      assignees: ['lerebear'],
      status: 'Backlog',
      stage: 'On Hold',
      impact: 'Medium',
      repositoryId: 2,
      milestoneId: 6,
      teamId: 2,
      labelIds: [25, 32],
    }),

    createMockIssue({
      isOpen: true,
      issueNumber: 1235,
      title:
        "As a user, I want to be able to 'Group By' different values so that I can easily plan in the Table Layout",
      priority: 0,
      virtualPriority: '0',
      assignees: [],
      status: 'Backlog',
      stage: 'On Hold',
      impact: 'Medium',
      repositoryId: 1,
      milestoneId: 4,
      teamId: 2,
      labelIds: [32],
    }),

    createMockIssue({
      isOpen: true,
      issueNumber: 1236,
      title: 'Refetch repo suggestions after an item is added to the table',
      priority: 0,
      virtualPriority: '0',
      assignees: [],
      status: 'Backlog',
      stage: 'On Hold',
      impact: 'Medium',
      repositoryId: 1,
      milestoneId: 3,
      teamId: 2,
      labelIds: [32],
    }),
  ],
}

export const withManyItemsData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(DefaultColumns),
  items: generateItems({count: 1000, columns: DefaultColumns}),
}

export const P_50_REACT_PROFILER_ID = 'p50'
const FIXED_RANDOM_NUMBER_SEED = 1616548276

export const p50Data: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(P50Columns),
  items: generateItems({count: 100, columns: P50Columns, seed: FIXED_RANDOM_NUMBER_SEED}),
}

export const p99Data: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(P99Columns),
  items: generateItems({count: 1000, columns: P99Columns, seed: FIXED_RANDOM_NUMBER_SEED}),
}
export const getMWLData: () => IntegrationTestStoryData = () => {
  const data = {
    ...createStoryDataFromColumns(DefaultColumns),
    items: generateItems({count: 1000, columns: DefaultColumns, seed: FIXED_RANDOM_NUMBER_SEED, includeEmpty: true}),
  }
  const baseView = data.views[0]
  invariant(baseView, 'Base view must exist')
  data.views = [
    ...data.views,
    {
      ...baseView,
      id: 2,
      name: 'Issues only',
      number: 2,
      groupBy: [],
      verticalGroupBy: [],
      sortBy: [],
      sliceBy: {},
      filter: 'is:issue',
    },
    {
      ...baseView,
      id: 3,
      name: 'Sorted by Status',
      number: 3,
      groupBy: [],
      verticalGroupBy: [],
      sortBy: [
        [not_typesafe_nonNullAssertion(DefaultColumns.find(column => column.id === 'Status')).databaseId, 'asc'],
      ],
      sliceBy: {},
      filter: '',
    },
    {
      ...baseView,
      id: 4,
      name: 'Grouped by Status',
      number: 4,
      groupBy: [not_typesafe_nonNullAssertion(DefaultColumns.find(column => column.id === 'Status')).databaseId],
      verticalGroupBy: [],
      sortBy: [],
      sliceBy: {},
      filter: '',
    },
    {
      ...baseView,
      id: 5,
      name: 'Grouped by Team',
      number: 5,
      groupBy: [not_typesafe_nonNullAssertion(DefaultColumns.find(column => column.name === 'Team')).databaseId],
      verticalGroupBy: [],
      sortBy: [],
      sliceBy: {},
      filter: '',
    },
  ]

  return data
}

export const getSavedViewsInitialData = () => {
  const data = {
    ...createStoryDataFromColumns(DefaultColumns),
    items: generateItems({count: 100, columns: P50Columns, seed: FIXED_RANDOM_NUMBER_SEED}),
  }

  const baseView = data.views[0]
  invariant(baseView, 'Base view must exist')
  data.views = [
    ...data.views,
    {
      id: 2,
      name: 'View 2',
      layout: ViewTypeParam.Table,
      number: 2,
      groupBy: [not_typesafe_nonNullAssertion(DefaultColumns.find(column => column.id === 'Status')).databaseId],
      verticalGroupBy: [],
      sortBy: [
        [not_typesafe_nonNullAssertion(DefaultColumns.find(column => column.id === 'Status')).databaseId, 'desc'],
      ],
      visibleFields: [
        ...baseView.visibleFields.slice(1, 2),
        ...baseView.visibleFields.slice(0, 1),
        ...baseView.visibleFields.slice(2),
      ],

      filter: '',
      priority: null,
      aggregationSettings: {hideItemsCount: false, sum: []},
      createdAt: new Date(2021, 5, 15).toISOString(),
      updatedAt: new Date(2021, 5, 15).toISOString(),
      layoutSettings: {},
      sliceBy: {},
      sliceValue: null,
    },

    {
      id: 3,
      name: 'View 3',
      layout: ViewTypeParam.Board,
      number: 3,
      groupBy: [not_typesafe_nonNullAssertion(DefaultColumns.find(column => column.id === 'Status')).databaseId],
      verticalGroupBy: [],
      sortBy: [],
      visibleFields: baseView.visibleFields,
      filter: '',
      priority: null,
      aggregationSettings: {
        hideItemsCount: false,
        sum: [],
      },
      createdAt: new Date(2021, 5, 15).toISOString(),
      updatedAt: new Date(2021, 5, 15).toISOString(),
      layoutSettings: {},
      sliceBy: {},
      sliceValue: null,
    },
  ]

  return data
}

/** Helper function to merge additional values into a given project item */
function addColumnValues(item: MemexItem, values: Array<MemexColumnData>): MemexItem {
  const newItem = cloneDeep(item)
  newItem.memexProjectColumnValues.push(...values)
  return newItem
}

export const withIterationFieldData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(IterationDemoColumns),
  items: [
    addColumnValues(DefaultClosedIssue, [{memexProjectColumnId: CustomIterationColumnId, value: {id: 'iteration-4'}}]),
    addColumnValues(DefaultClosedPullRequest, [{memexProjectColumnId: CustomIterationColumnId, value: null}]),
    addColumnValues(DefaultDraftIssue, [{memexProjectColumnId: CustomIterationColumnId, value: {id: 'iteration-4'}}]),
    addColumnValues(ClosedIssueWithAllData, [{memexProjectColumnId: CustomIterationColumnId, value: null}]),
    DefaultRedactedItem,
    addColumnValues(DefaultOpenIssue, [{memexProjectColumnId: CustomIterationColumnId, value: {id: 'iteration-5'}}]),
    addColumnValues(DefaultOpenPullRequest, [{memexProjectColumnId: CustomIterationColumnId, value: null}]),
    addColumnValues(DraftIssueLink, [{memexProjectColumnId: CustomIterationColumnId, value: {id: 'iteration-4'}}]),
    addColumnValues(DefaultTrackedByIssue, [
      {memexProjectColumnId: CustomIterationColumnId, value: {id: 'iteration-0'}},
    ]),
  ],
}

export const withSubIssuesData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(SubIssueDemoColumns),
  items: [],
}

export const withReasonFieldData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(ReasonDemoColumns),
  items: [
    addColumnValues(DefaultClosedIssue, [
      {memexProjectColumnId: CustomReasonColumnId, value: {raw: 'customer-request', html: 'customer-request'}},
    ]),

    DefaultClosedPullRequest,
    addColumnValues(DefaultDraftIssue, [
      {memexProjectColumnId: CustomReasonColumnId, value: {raw: 'customer-request', html: 'customer-request'}},
    ]),

    ClosedIssueWithAllData,
    ClosedIssueAsNotPlanned,
    DefaultRedactedItem,
    addColumnValues(DefaultOpenIssue, [
      {memexProjectColumnId: CustomReasonColumnId, value: {raw: 'tech-debt', html: 'tech-debt'}},
    ]),

    DefaultOpenPullRequest,
    addColumnValues(DraftIssueLink, [
      {memexProjectColumnId: CustomReasonColumnId, value: {raw: 'tech-debt', html: 'tech-debt'}},
    ]),
  ],
}

export const withTrackedByFieldData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(TrackedByDemoColumns),
  items: [
    DefaultTrackedByIssue,
    DefaultClosedIssue,
    ClosedTrackedByIssue,
    DefaultClosedPullRequest,
    DefaultDraftIssue,
    ClosedIssueWithAllData,
    DefaultRedactedItem,
    DefaultOpenIssue,
    DefaultOpenPullRequest,
    DraftIssueLink,
  ],
}

export const withXssTestColumnData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(XssTestColumns),
  items: [
    DefaultClosedIssue,
    DefaultClosedPullRequest,
    DefaultDraftIssue,
    ClosedIssueWithAllData,
    DefaultRedactedItem,
    DefaultOpenIssue,
    DefaultOpenPullRequest,
    DraftIssueLink,
  ],
}

export const withNewProject: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(DefaultColumns),
  items: [],
}

/** Turns the given project item into an archived item */
const itemWithArchived = (
  item: MemexItem,
  {
    archivedAt,
    archivedBy,
  }: {
    /**
     * When the value is explicitly null, no user will be set,
     * otherwise a default user will be given if none is provided
     */
    archivedBy?: User | null
    archivedAt?: string
  } = {},
): MemexItem => {
  const archivedOpts: MemexItem['archived'] = {
    archivedAt: archivedAt ?? new Date().toISOString(),
  }

  if (archivedBy !== null) {
    archivedOpts.archivedBy = getUser('dmarcey')
  }

  return {
    ...item,
    archived: archivedOpts,
  }
}

type DuplicateItemOptions = {title?: string; id?: number}
/**
 * Duplicates an existing memex item, and allows some properties to be changed
 * in the newly duplicated item.
 */
const duplicateItem = <Item extends MemexItem = MemexItem>(
  item: Item,
  {title, id}: DuplicateItemOptions = {},
): Item => {
  const newId = id ?? getNextId()
  const clonedItem = deepCopy(item)
  const newItem: Item = {
    ...clonedItem,
    id: newId,
    content: {
      ...clonedItem.content,
    },
  }

  if (title) {
    const {value} = newItem.memexProjectColumnValues.find(
      col => col.memexProjectColumnId === SystemColumnId.Title,
    ) as TitleColumnData
    value.title = {raw: title, html: title}
  }

  return newItem
}

const itemsWithArchivedVersions = (
  item: MemexItem,
  opts: DuplicateItemOptions,
  archiveOpts: Parameters<typeof itemWithArchived>[1] = {},
): Array<MemexItem> => {
  return [
    duplicateItem(item, opts),
    itemWithArchived(
      duplicateItem(item, {
        ...opts,
        ...(opts.title && {title: `${opts.title} (ARCHIVE)`}),
      }),

      archiveOpts,
    ),
  ]
}

export const withArchivedItemsData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(DefaultColumns),
  items: [
    ...generateItems({count: 4000, columns: DefaultColumns}).map((item, index) =>
      itemWithArchived(duplicateItem(item, {title: `Archived item ${item.id}`}), {
        archivedAt: subSeconds(subDays(new Date(), 10), index * 10).toISOString(),
      }),
    ),

    ...itemsWithArchivedVersions(
      DefaultClosedIssue,
      {
        title: 'Closed issue with some long text to make the title text longer and eventually wrap',
      },

      {archivedAt: subSeconds(new Date(), 1).toISOString()},
    ),

    ...itemsWithArchivedVersions(
      DefaultClosedPullRequest,
      {title: 'Improve the archived items page'},
      {archivedAt: subSeconds(new Date(), 2).toISOString()},
    ),

    ...itemsWithArchivedVersions(
      DefaultDraftIssue,
      {title: 'This is a draft issue'},
      {archivedAt: subSeconds(new Date(), 3).toISOString()},
    ),

    ...itemsWithArchivedVersions(
      DefaultOpenIssue,
      {title: 'Issues with loading archived items'},
      {archivedAt: subSeconds(new Date(), 4).toISOString()},
    ),

    ...itemsWithArchivedVersions(
      DefaultOpenPullRequest,
      {title: '[experiment] improve performance of archiving'},
      {archivedAt: subSeconds(new Date(), 5).toISOString()},
    ),

    ...itemsWithArchivedVersions(
      DraftIssueLink,
      {title: 'Idea to improve archive page'},
      {archivedAt: subSeconds(new Date(), 6).toISOString()},
    ),

    ...itemsWithArchivedVersions(
      ClosedIssueWithAllData,
      {title: 'Closed issue with all data'},
      {archivedAt: subSeconds(new Date(), 7).toISOString()},
    ),

    ...itemsWithArchivedVersions(
      ClosedIssueAsNotPlanned,
      {title: 'Closed issue as not planned'},
      {archivedAt: subSeconds(new Date(), 8).toISOString()},
    ),

    itemWithArchived(duplicateItem(DefaultRedactedItem), {
      archivedBy: null,
      archivedAt: subSeconds(new Date(), 9).toISOString(),
    }),

    itemWithArchived(duplicateItem(DefaultRedactedItem), {archivedAt: subSeconds(new Date(), 10).toISOString()}),
    itemWithArchived(duplicateItem(DefaultOpenIssue, {title: 'This was archived without an actor'}), {
      archivedBy: null,
      archivedAt: subSeconds(new Date(), 11).toISOString(),
    }),
  ],
}

const today = startOfToday()
const firstDay = startOfMonth(today)
const lastDay = lastDayOfMonth(today)
const firstDayYear = startOfYear(today)
const lastDayYear = lastDayOfYear(today)
const daysInMonth = getDaysInMonth(today)

/** Turns the given project item into an archived item */
const itemWithStartAndEndDate = (
  item: MemexItem,
  {
    startDate,
    endDate,
  }: {
    startDate?: string | Date
    endDate?: string | Date
  } = {},
): MemexItem => {
  const {memexProjectColumnValues, ...rest} = item
  const projectColumnValues = memexProjectColumnValues.filter(
    columnData =>
      !new Array<number | SystemColumnId>(StartDateColumnId, EndDateColumnId).includes(columnData.memexProjectColumnId),
  )

  if (startDate) {
    projectColumnValues.push({
      memexProjectColumnId: StartDateColumnId,
      value: {
        value: typeof startDate === 'string' ? startDate : startDate.toISOString(),
      },
    })
  }

  if (endDate) {
    projectColumnValues.push({
      memexProjectColumnId: EndDateColumnId,
      value: {
        value: typeof endDate === 'string' ? endDate : endDate.toISOString(),
      },
    })
  }

  return {
    ...rest,
    memexProjectColumnValues: projectColumnValues,
  }
}

export const withRoadmapData: IntegrationTestStoryData = {
  columns: RoadmapTestColumns,
  views: autoFillViewServerProps([
    createView({
      name: 'Roadmap',
      filter: '',
      layout: ViewTypeParam.Roadmap,
      groupBy: [],
      verticalGroupBy: [],
      sortBy: [],
      priority: null,
      visibleFields: [
        ...RoadmapTestColumns.filter(c => c.defaultColumn).map(c => c.databaseId),
        not_typesafe_nonNullAssertion(RoadmapTestColumns.find(c => c.id === SystemColumnId.Milestone)).databaseId,
      ],
      aggregationSettings: {
        hideItemsCount: false,
        sum: [],
      },
      layoutSettings: {
        roadmap: {
          dateFields: [startDateColumn.databaseId, endDateColumn.databaseId],
          zoomLevel: RoadmapZoomLevel.Month,
        },
      },
      sliceBy: {},
      sliceValue: null,
    }),
  ]),
  items: [
    createMockRoadmapIssue({
      issueNumber: 1341,
      priority: 100,
      virtualPriority: '0.19876',
      title: 'Whole year',
      startDate: firstDayYear,
      endDate: lastDayYear,
    }),
    createMockRoadmapIssue({
      issueNumber: 1341,
      priority: 100,
      virtualPriority: '0.19876',
      title: 'Q1',
      startDate: firstDayYear,
      endDate: lastDayOfQuarter(firstDayYear),
    }),
    createMockRoadmapIssue({
      issueNumber: 1341,
      priority: 100,
      virtualPriority: '0.19876',
      title: 'Q2',
      startDate: addQuarters(firstDayYear, 1),
      endDate: lastDayOfQuarter(addQuarters(firstDayYear, 1)),
    }),
    createMockRoadmapIssue({
      issueNumber: 1341,
      priority: 100,
      virtualPriority: '0.19876',
      title: 'Q3',
      startDate: addQuarters(firstDayYear, 2),
      endDate: lastDayOfQuarter(addQuarters(firstDayYear, 2)),
    }),
    createMockRoadmapIssue({
      issueNumber: 1341,
      priority: 100,
      virtualPriority: '0.19876',
      title: 'Q4',
      startDate: addQuarters(firstDayYear, 3),
      endDate: lastDayOfQuarter(addQuarters(firstDayYear, 3)),
    }),
    createMockRoadmapIssue({
      issueNumber: 1340,
      priority: 100,
      virtualPriority: '0.19876',
      title: 'Whole month',
      startDate: firstDay,
      endDate: lastDay,
    }),
    createMockRoadmapIssue({
      issueNumber: 8342,
      priority: 102,
      virtualPriority: '0.1987654',
      title: 'Today',
      startDate: today,
    }),
    createMockRoadmapIssue({
      issueNumber: 2453,
      priority: 101,
      virtualPriority: '0.198765',
      title: 'First day',
      startDate: firstDay,
    }),
    createMockRoadmapIssue({
      issueNumber: 8342,
      priority: 102,
      virtualPriority: '0.1987654',
      title: 'Last day',
      startDate: lastDay,
    }),
    createMockRoadmapIssue({
      issueNumber: 8342,
      priority: 102,
      virtualPriority: '0.1987654',
      title: 'Target day',
      endDate: addDays(today, 7),
      dueDate: addDays(today, 7),
    }),
    createMockRoadmapIssue({
      issueNumber: 8342,
      priority: 102,
      virtualPriority: '0.1987654',
      title: 'Same day',
      startDate: today,
      endDate: today,
    }),
    createMockRoadmapIssue({
      issueNumber: 9932,
      priority: 103,
      virtualPriority: '0.19876543',
      title: 'Week 1',
      startDate: firstDay,
      endDate: addDays(firstDay, 7),
    }),
    createMockRoadmapIssue({
      issueNumber: 7745,
      priority: 104,
      virtualPriority: '0.198765432',
      title: 'Week 2',
      startDate: addDays(firstDay, 7),
      endDate: addDays(firstDay, 14),
    }),
    createMockRoadmapIssue({
      issueNumber: 2352,
      priority: 105,
      virtualPriority: '0.1987654321',
      title: 'Week 3',
      startDate: addDays(firstDay, 14),
      endDate: addDays(firstDay, 21),
    }),
    createMockRoadmapIssue({
      issueNumber: 9345,
      priority: 106,
      virtualPriority: '0.19876543219',
      title: 'Week 4',
      startDate: addDays(firstDay, 21),
      endDate: addDays(firstDay, 28),
    }),
    createMockRoadmapIssue({
      issueNumber: 9933,
      priority: 103,
      virtualPriority: '0.198765432',
      title: 'This Week',
      startDate: today,
      endDate: addDays(today, 7),
    }),
    createMockRoadmapIssue({
      issueNumber: 9933,
      priority: 103,
      virtualPriority: '0.198765432',
      title: 'Reversed',
      startDate: addDays(today, 7),
      endDate: today,
    }),
    createMockRoadmapIssue({
      issueNumber: 9345,
      priority: 110,
      virtualPriority: '0.198765499999',
      title: 'First half',
      startDate: firstDay,
      endDate: addDays(firstDay, Math.floor(daysInMonth / 2)),
    }),
    createMockRoadmapIssue({
      issueNumber: 9345,
      priority: 111,
      virtualPriority: '0.19876549999999',
      title: 'Second half',
      startDate: addDays(firstDay, Math.floor(daysInMonth / 2) + 1),
      endDate: lastDay,
    }),
    ...generateItems({
      count: 28,
      columns: RoadmapTestColumns.filter(c => c.id !== CustomIterationColumnId && c.id !== SecondaryIterationColumnId),
    }).map((item, index) =>
      itemWithStartAndEndDate(item, {
        startDate: addDays(firstDay, index),
        endDate: addDays(firstDay, index),
      }),
    ),
    ...generateItems({
      count: 28,
      columns: RoadmapTestColumns.filter(c => c.id !== CustomIterationColumnId && c.id !== SecondaryIterationColumnId),
    }).map((item, index) =>
      itemWithStartAndEndDate(item, {
        startDate: firstDay,
        endDate: addDays(firstDay, index),
      }),
    ),
    ...generateItems({
      count: 28,
      columns: RoadmapTestColumns.filter(c => c.id !== CustomIterationColumnId && c.id !== SecondaryIterationColumnId),
    }).map((item, index) =>
      itemWithStartAndEndDate(item, {
        startDate: addDays(firstDay, index),
        endDate: lastDay,
      }),
    ),
  ],
}

export const withInsightsData: IntegrationTestStoryData = {
  ...createStoryDataFromColumns(DefaultColumns),
  items: generateLeanHistoricalInsightsData({columns: DefaultColumns}),
}

export const withStatusUpdateData: {
  statuses: Array<MemexStatus>
} = {
  statuses: [
    {
      id: 10,
      creator: getUser('dmarcey'),
      updatedAt: '2023-10-31',
      statusValue: {
        status: {
          id: 'c77b75a3',
          name: 'Complete',
          nameHtml: 'Complete',
          color: 'PURPLE',
          description: 'This project is complete.',
          descriptionHtml: 'This project is complete.',
        },
        statusId: '459eafad',
        startDate: '2023-10-31',
        targetDate: '2023-11-14',
      },
      body: 'Mission accomplished! Project successfully completed!',
      bodyHtml: 'Mission accomplished! Project successfully completed!',
      userHidden: false,
    },
    {
      id: 9,
      creator: getUser('dmarcey'),
      updatedAt: '2023-10-31',
      statusValue: {
        status: {
          id: '459eafad',
          name: 'On track',
          nameHtml: 'On track',
          color: 'GREEN',
          description: 'This project is on track with no risks.',
          descriptionHtml: 'This project is on track with no risks.',
        },
        statusId: '459eafad',
        startDate: '2023-10-31',
        targetDate: '2023-11-14',
      },
      body: 'Making steady progress and staying on track!',
      bodyHtml: 'Making steady progress and staying on track!',
      userHidden: false,
    },
    {
      id: 8,
      creator: getUser('dmarcey'),
      updatedAt: '2023-10-31',
      statusValue: {
        status: {
          id: '04201a9a',
          name: 'Off track',
          nameHtml: 'Off track',
          color: 'RED',
          description: 'This project is off track and needs attention.',
          descriptionHtml: 'This project is off track and needs attention.',
        },
        statusId: '459eafad',
        startDate: '2023-10-31',
        targetDate: '2023-11-14',
      },
      body: 'Taking a detour, but working hard to get back on track.',
      bodyHtml: 'Taking a detour, but working hard to get back on track.',
      userHidden: false,
    },
    {
      id: 7,
      creator: getUser('dmarcey'),
      updatedAt: '2023-10-31',
      statusValue: {
        status: {
          id: '366655d6',
          name: 'At risk',
          nameHtml: 'At risk',
          color: 'YELLOW',
          description: 'This project is at risk and encountering some challenges.',
          descriptionHtml: 'This project is at risk and encountering some challenges.',
        },
        statusId: '459eafad',
        startDate: '2023-10-31',
        targetDate: '2023-11-14',
      },
      body: 'Facing uncertainty, but staying strong and determined in the face of challenges.',
      bodyHtml: 'Facing uncertainty, but staying strong and determined in the face of challenges.',
      userHidden: false,
    },
    {
      id: 6,
      creator: getUser('dmarcey'),
      updatedAt: '2023-10-31',
      statusValue: {
        status: {
          id: '459eafad',
          name: 'On track',
          nameHtml: 'On track',
          color: 'GREEN',
          description: 'This project is on track with no risks.',
          descriptionHtml: 'This project is on track with no risks.',
        },
        statusId: '459eafad',
        startDate: '2023-10-31',
        targetDate: '2023-11-14',
      },
      body: 'Hello World!',
      bodyHtml: 'Hello World!',
      userHidden: false,
    },
    {
      id: 5,
      creator: getUser('shiftkey'),
      updatedAt: '2023-10-31',
      statusValue: {
        status: {
          id: 'c77b75a3',
          name: 'Complete',
          nameHtml: 'Complete',
          color: 'PURPLE',
          description: 'This project is complete.',
          descriptionHtml: 'This project is complete.',
        },
        statusId: '459eafad',
        startDate: '2023-10-31',
        targetDate: '2023-11-14',
      },
      body: 'Mission accomplished! Project successfully completed!',
      bodyHtml: 'Mission accomplished! Project successfully completed!',
      userHidden: false,
    },
    {
      id: 4,
      creator: getUser('shiftkey'),
      updatedAt: '2023-10-31',
      statusValue: {
        status: {
          id: '459eafad',
          name: 'On track',
          nameHtml: 'On track',
          color: 'GREEN',
          description: 'This project is on track with no risks.',
          descriptionHtml: 'This project is on track with no risks.',
        },
        statusId: '459eafad',
        startDate: '2023-10-31',
        targetDate: '2023-11-14',
      },
      body: 'Making steady progress and staying on track!',
      bodyHtml: 'Making steady progress and staying on track!',
      userHidden: false,
    },
    {
      id: 3,
      creator: getUser('shiftkey'),
      updatedAt: '2023-10-31',
      statusValue: {
        status: {
          id: '04201a9a',
          name: 'Off track',
          nameHtml: 'Off track',
          color: 'RED',
          description: 'This project is off track and needs attention.',
          descriptionHtml: 'This project is off track and needs attention.',
        },
        statusId: '459eafad',
        startDate: '2023-10-31',
        targetDate: '2023-11-14',
      },
      body: 'Taking a detour, but working hard to get back on track.',
      bodyHtml: 'Taking a detour, but working hard to get back on track.',
      userHidden: false,
    },
    {
      id: 2,
      creator: getUser('shiftkey'),
      updatedAt: '2023-10-31',
      statusValue: {
        status: {
          id: '366655d6',
          name: 'At risk',
          nameHtml: 'At risk',
          color: 'YELLOW',
          description: 'This project is at risk and encountering some challenges.',
          descriptionHtml: 'This project is at risk and encountering some challenges.',
        },
        statusId: '459eafad',
        startDate: '2023-10-31',
        targetDate: '2023-11-14',
      },
      body: 'Facing uncertainty, but staying strong and determined in the face of challenges.',
      bodyHtml: 'Facing uncertainty, but staying strong and determined in the face of challenges.',
      userHidden: false,
    },
    {
      id: 1,
      creator: getUser('shiftkey'),
      updatedAt: '2023-10-31',
      statusValue: {
        status: {
          id: '459eafad',
          name: 'On track',
          nameHtml: 'On track',
          color: 'GREEN',
          description: 'This project is on track with no risks.',
          descriptionHtml: 'This project is on track with no risks.',
        },
        statusId: '459eafad',
        startDate: '2023-10-31',
        targetDate: '2023-11-14',
      },
      body: 'Hello World!',
      bodyHtml: 'Hello World!',
      userHidden: false,
    },
  ],
}
