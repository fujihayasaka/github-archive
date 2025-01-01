import type {Meta, StoryObj} from '@storybook/react'
import {PullRequestFilesToolbar} from './PullRequestFilesToolbar'
import {getPullRequestFilesToolbarMockData} from '../../test-utils/files-changed/toolbar-mock-data'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {defaultMockFileFilterProps, TestFileFilterComponent} from '../../test-utils/files-changed/file-filter-mock-data'

const meta = {
  title: 'Pull Requests/Files Changed/PullRequestFilesToolbar',
  component: PullRequestFilesToolbar,
  decorators: [
    Story => {
      return (
        <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
          <Wrapper>
            {/* Needed to prevent accessibility issues with the expand button */}
            <div id="pr-file-tree" />
            <Story />
          </Wrapper>
        </PageDataContextProvider>
      )
    },
  ],
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof PullRequestFilesToolbar>

export default meta

type Story = StoryObj<typeof PullRequestFilesToolbar>

const defaultData = getPullRequestFilesToolbarMockData()

export const Default: Story = {
  render: () => (
    <PullRequestFilesToolbar
      {...defaultData}
      fileFilter={<TestFileFilterComponent {...defaultMockFileFilterProps} />}
    />
  ),
}
