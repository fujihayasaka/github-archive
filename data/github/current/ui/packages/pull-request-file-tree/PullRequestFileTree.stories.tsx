import type {Meta, StoryObj} from '@storybook/react'
import {PullRequestFileTree} from './PullRequestFileTree'
import {getMockPullRequestFileTreePageData} from './test-utils/mock-data'
import {DiffFileTreeAxeRules} from '@github-ui/diff-file-tree/storybook-helper'
import type {DiffDelta} from '@github-ui/diff-file-tree/diff-file-tree-helpers'

const meta = {
  title: 'Pull Requests/Files Changed/PullRequestFileTree',
  component: PullRequestFileTree,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    a11y: {
      config: {
        rules: DiffFileTreeAxeRules,
      },
    },
  },
} satisfies Meta<typeof PullRequestFileTree>

export default meta

type Story = StoryObj<typeof PullRequestFileTree>

const defaultData = getMockPullRequestFileTreePageData()

export const Default: Story = {
  render: () => (
    <PullRequestFileTree
      baseRefOid={defaultData.baseRefOid}
      commits={defaultData.commits}
      diffs={defaultData.diffs}
      ownerLogin={defaultData.ownerLogin}
      pathName={defaultData.pathName}
      pullRequestNumber={defaultData.pullRequestNumber}
      pullRequestId={defaultData.pullRequestId}
      repositoryName={defaultData.repositoryName}
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
      filteredDiffs={defaultData.diffs as DiffDelta[]}
    />
  ),
}
