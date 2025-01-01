import type {Meta, StoryObj} from '@storybook/react'
import {PullRequestFileTree} from './PullRequestFileTree'
import {getMockFileTreePageData} from '../../test-utils/files-changed/file-tree-mock-data'
import {DiffFileTreeAxeRules} from '@github-ui/diff-file-tree/storybook-helper'
import {defaultMockFileFilterProps, TestFileFilterComponent} from '../../test-utils/files-changed/file-filter-mock-data'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'

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

const defaultData = getMockFileTreePageData()

export const Default: Story = {
  render: () => (
    <Wrapper>
      <PageDataContextProvider basePageDataUrl="">
        <PullRequestFileTree
          filteredDiffs={defaultData.filteredDiffs}
          fileFilter={<TestFileFilterComponent {...defaultMockFileFilterProps} />}
        />
      </PageDataContextProvider>
    </Wrapper>
  ),
}
