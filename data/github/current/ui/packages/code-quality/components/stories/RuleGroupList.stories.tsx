import type {Meta} from '@storybook/react'
import {RuleGroupList, type RuleGroupListProps} from '../RuleGroupList'
import {http, HttpResponse} from 'msw'
import {getRuleFilesResponse, getRuleGroupsResponse} from '../../test-utils/mock-data'

const meta = {
  title: 'Apps/Code Quality/Rule Group List',
  component: RuleGroupList,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    msw: {
      handlers: [
        http.get('/:owner/:repo/security/quality/rules', () => {
          return HttpResponse.json(getRuleGroupsResponse())
        }),
        http.get('/:owner/:repo/security/quality/rules/:ruleId/files', () => {
          return HttpResponse.json(getRuleFilesResponse())
        }),
      ],
    },
  },
  argTypes: {},
} satisfies Meta<typeof RuleGroupList>

export default meta

const defaultArgs: RuleGroupListProps = {
  owner: 'octodemo',
  repo: 'repo1',
  findingsCount: 60,
}

export const Default = {
  args: defaultArgs,
  render: (args: RuleGroupListProps) => <RuleGroupList {...args} />,
}

export const RulesGroupListLoading = {
  args: defaultArgs,
  parameters: {
    msw: {
      handlers: [
        http.get('/:owner/:repo/security/quality/rules', () => {
          return new Promise(() => {})
        }),
      ],
    },
  },
  render: (args: RuleGroupListProps) => <RuleGroupList {...args} />,
}

export const RulesGroupListError = {
  args: defaultArgs,
  parameters: {
    msw: {
      handlers: [
        http.get('/:owner/:repo/security/quality/rules', () => {
          return HttpResponse.json({message: 'An error occurred'}, {status: 500})
        }),
      ],
    },
  },
  render: (args: RuleGroupListProps) => <RuleGroupList {...args} />,
}
