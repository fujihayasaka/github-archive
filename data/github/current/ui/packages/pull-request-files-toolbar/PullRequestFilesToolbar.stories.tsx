import type {Meta, StoryObj} from '@storybook/react'
import {PullRequestFilesToolbar} from './PullRequestFilesToolbar'
import {getPullRequestFilesToolbarMockData} from './test-utils/mock-data'
import {Wrapper} from '@github-ui/react-core/test-utils'
import type {DiffDelta} from '@github-ui/diff-file-tree/diff-file-tree-helpers'

const meta = {
  title: 'Pull Requests/Files Changed/PullRequestFilesToolbar',
  component: PullRequestFilesToolbar,
  decorators: [
    Story => {
      return (
        <Wrapper>
          {/* Needed to prevent accessibility issues with the expand button */}
          <div id="pr-file-tree" />
          <Story />
        </Wrapper>
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
      repository={defaultData.pullRequest.repository}
      fileFilterState={{
        filterText: '',
        fileExtensions: new Set<string>(),
        unselectedFileExtensions: new Set<string>(),
        showCodeowners: undefined,
        showDeletedFiles: undefined,
        showOnlyManifestFiles: undefined,
        showVendorFiles: undefined,
        showViewedFiles: undefined,
      }}
      setFileFilterState={() => {}}
      filteredDiffs={[] as DiffDelta[]}
    />
  ),
}
