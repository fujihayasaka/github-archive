import type {Meta} from '@storybook/react'

import {IssueRow} from './IssueRow'
import {IssueRowExampleWithOverrides} from './IssueRow.stories.helpers'

const meta = {
  title: 'ListViewItemsIssuesPrs',
  component: IssueRow,
} satisfies Meta<typeof IssueRow>

export default meta

export const IssueRowExample = IssueRowExampleWithOverrides()
