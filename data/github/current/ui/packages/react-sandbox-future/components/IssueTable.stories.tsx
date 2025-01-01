import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {getDashboardIssues} from '../__tests__/utils/mock-data'
import {IssueTable} from './IssueTable'

type IssueTableProps = React.ComponentProps<typeof IssueTable>

const args = {
  issues: [...getDashboardIssues(3, 'open'), ...getDashboardIssues(3, 'closed')],
  isPending: false,
  isError: false,
} satisfies IssueTableProps

const meta = {
  title: 'Apps/React Sandbox Future/IssueTable',
  component: IssueTable,
  args,
  decorators: [storyWrapper()],
} satisfies Meta<typeof IssueTable>

export default meta

export const Empty = {args: {issues: []}}
export const Error = {args: {isError: true}}
export const Example = {}
export const Loading = {args: {isPending: true}}
