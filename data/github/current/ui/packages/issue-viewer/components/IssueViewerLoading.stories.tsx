import type {Meta} from '@storybook/react'
import {IssueViewerLoading} from './IssueViewerLoading'
import {ISSUE_VIEWER_DEFAULT_CONFIG} from './OptionConfig'

const meta = {
  title: 'IssueViewer/IssueViewerLoading',
  component: IssueViewerLoading,
  argTypes: {},
} satisfies Meta<typeof IssueViewerLoading>

export default meta

export const IssueViewerExample = {
  args: {},
  render: () => <IssueViewerLoading optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG} />,
}
