import type {Meta, StoryObj} from '@storybook/react'

import {createSecurityCampaignAlert, getAssignee, getAutofixValidationCheck} from '../../test-utils/mock-data'
import {AlertsList, type AlertsListProps} from '../AlertsList'
import {AlertsListItems} from '../AlertsListItems'
import {AlertListItem} from '../AlertListItem'
import {AutofixValidationCheckStatus, AutofixValidationType} from '../../types/autofix-validation-check'

const meta = {
  title: 'Apps/Security Campaigns/Alerts List',
  component: AlertsList,
} satisfies Meta<typeof AlertsList>

export default meta
type Story = StoryObj<typeof AlertsList>

const defaultArgs: Omit<AlertsListProps, 'children'> = {
  openCount: 353_358,
  closedCount: 1_954_674,
  nextCursor: 'nextpage',
  prevCursor: '',
  isLoading: false,
  isError: false,
  showLimitedAlertsWarning: false,
  query: 'is:open',
  onStateFilterChange: () => {},
  showStateFilters: true,
  onCursorChange: () => {},
  setSelectedItems: () => {},
}

const defaultRender = (
  args: AlertsListProps,
  alerts = [
    createSecurityCampaignAlert({number: 1, title: 'Test alert 1'}),
    createSecurityCampaignAlert({number: 2, title: 'Test alert 2'}),
  ],
) => {
  return (
    <AlertsList {...args}>
      <AlertsListItems
        alerts={alerts}
        query={args.query}
        isLoading={args.isLoading}
        isError={args.isError}
        renderAlert={props => <AlertListItem alert={props} />}
      />
    </AlertsList>
  )
}

export const Default: Story = {
  args: defaultArgs,
  render: args => defaultRender(args),
}

export const WithLimitedAlertsWarning: Story = {
  args: {
    ...defaultArgs,
    showLimitedAlertsWarning: true,
  },
  render: args => defaultRender(args),
}

export const SinglePage: Story = {
  args: {
    ...defaultArgs,
    nextCursor: '',
    prevCursor: '',
  },
  render: args => defaultRender(args),
}

export const SinglePageWithLimitedAlertsWarning: Story = {
  args: {
    ...defaultArgs,
    nextCursor: '',
    prevCursor: '',
    showLimitedAlertsWarning: true,
  },
  render: args => defaultRender(args),
}

export const WithAutofixValidationChecks: Story = {
  args: {
    ...defaultArgs,
  },
  render: args =>
    defaultRender(args, [
      createSecurityCampaignAlert({
        number: 1,
        title: 'Test alert 1',
        hasSuggestedFix: true,
        autofixValidationChecks: [
          getAutofixValidationCheck({
            validationType: AutofixValidationType.Llm,
          }),
          getAutofixValidationCheck({
            validationType: AutofixValidationType.CodeQL,
          }),
          getAutofixValidationCheck({
            validationType: AutofixValidationType.Linter,
          }),
        ],
      }),
      createSecurityCampaignAlert({
        number: 2,
        title: 'Test alert 2',
        hasSuggestedFix: true,
        autofixValidationChecks: [
          getAutofixValidationCheck({
            validationType: AutofixValidationType.Llm,
          }),
          getAutofixValidationCheck({
            validationType: AutofixValidationType.CodeQL,
          }),
          getAutofixValidationCheck({
            validationType: AutofixValidationType.Linter,
            status: AutofixValidationCheckStatus.Failed,
          }),
        ],
      }),
      createSecurityCampaignAlert({
        number: 3,
        title: 'Test alert 3',
        hasSuggestedFix: true,
        autofixValidationChecks: [
          getAutofixValidationCheck({
            validationType: AutofixValidationType.Llm,
          }),
          getAutofixValidationCheck({
            validationType: AutofixValidationType.CodeQL,
          }),
          getAutofixValidationCheck({
            validationType: AutofixValidationType.Linter,
            status: AutofixValidationCheckStatus.Pending,
          }),
        ],
      }),
    ]),
}

export const WithAssignees: Story = {
  args: {
    ...defaultArgs,
  },
  render: args =>
    defaultRender(args, [
      createSecurityCampaignAlert({
        number: 1,
        title: 'Test alert 1',
        assignees: [
          getAssignee(),
          getAssignee({
            id: 15,
            login: 'octocat',
            name: null,
            avatarUrl: 'https://avatars.githubusercontent.com/u/15?v=4',
            profilePath: '/octocat',
          }),
          getAssignee({
            id: 300,
            login: 'octodog',
            name: null,
            avatarUrl: 'https://avatars.githubusercontent.com/u/300?v=4',
            profilePath: '/octodog',
          }),
          getAssignee({
            id: 3789,
            login: 'Copilot',
            name: null,
            avatarUrl: 'https://avatars.githubusercontent.com/u/3789?v=4',
            profilePath: '/apps/copilot-swe-agent',
            isCopilot: true,
          }),
          getAssignee({
            id: 9023,
            login: 'octoarrow',
            name: null,
            avatarUrl: 'https://avatars.githubusercontent.com/u/9023?v=4',
            profilePath: '/octoarrow',
          }),
        ],
      }),
      createSecurityCampaignAlert({
        number: 2,
        title: 'Test alert 2',
        assignees: [getAssignee()],
      }),
      createSecurityCampaignAlert({
        number: 3,
        title: 'Test alert 3',
        assignees: [
          getAssignee({
            id: 3789,
            login: 'Copilot',
            name: null,
            avatarUrl: 'https://avatars.githubusercontent.com/u/3789?v=4',
            profilePath: '/apps/copilot-swe-agent',
            isCopilot: true,
          }),
        ],
      }),
      createSecurityCampaignAlert({
        number: 4,
        title: 'Test alert 4',
        assignees: [
          getAssignee({
            id: 3789,
            login: 'Copilot',
            name: null,
            avatarUrl: 'https://avatars.githubusercontent.com/u/3789?v=4',
            profilePath: '/apps/copilot-swe-agent',
            isCopilot: true,
          }),
          getAssignee(),
        ],
      }),
    ]),
}
