import type {Meta, StoryObj} from '@storybook/react'
import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {FilesPageInfoProvider} from '../../contexts/FilesPageInfoContext'
import {SpoofedCommitWarning} from '../SpoofedCommitWarning'
import type {RefInfo} from '@github-ui/repos-types'
import {createRepository} from '@github-ui/current-repository/test-helpers'

const meta = {
  title: 'Apps/Code View Shared/SpoofedCommitWarning',
  component: SpoofedCommitWarning,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof SpoofedCommitWarning>

export default meta

type Story = StoryObj<typeof SpoofedCommitWarning>

const defaultArgs = {
  refInfo: {
    name: 'main',
    listCacheKey: 'key',
    refType: 'branch',
    canEdit: true,
    currentOid: '1234',
  } as RefInfo,
  repo: createRepository({
    id: 1,
    name: 'test-repo',
    ownerLogin: 'owner',
    defaultBranch: 'main',
    createdAt: '2021-10-01T00:00:00Z',
    currentUserCanPush: true,
    isFork: false,
    isEmpty: false,
    ownerAvatar: 'www.github.com/avatar',
    public: true,
    private: false,
    isOrgOwned: false,
  }),
  path: '/test/path',
  commitCount: '1',
}

export const Default: Story = {
  render: () => (
    <CurrentRepositoryProvider repository={defaultArgs.repo}>
      <FilesPageInfoProvider
        refInfo={defaultArgs.refInfo}
        path={defaultArgs.path}
        action="tree"
        copilotAccessAllowed={false}
      >
        <SpoofedCommitWarning />
      </FilesPageInfoProvider>
    </CurrentRepositoryProvider>
  ),
}
