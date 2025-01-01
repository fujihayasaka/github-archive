// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {FilesPageInfoProvider} from '@github-ui/code-view-shared/contexts/FilesPageInfoContext'
import {CurrentTreeProvider} from '@github-ui/code-view-shared/contexts/CurrentTreeContext'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import type {StoryFn} from '@storybook/react'
import type {RefInfo} from '@github-ui/repos-types'
import type {DirectoryItem} from '@github-ui/code-view-types'
import {FileQueryProvider} from '@github-ui/code-view-shared/contexts/FileQueryContext'

export function currentRepositoryDecorator(Story: StoryFn) {
  return (
    <CurrentRepositoryProvider repository={repository}>
      <Story />
    </CurrentRepositoryProvider>
  )
}

export function fileQueryDecorator(Story: StoryFn) {
  return (
    <FileQueryProvider>
      <Story />
    </FileQueryProvider>
  )
}

export function filesPageInfoDecorator(Story: StoryFn) {
  return (
    <FilesPageInfoProvider refInfo={refInfo} path={'/test/path'} action="tree" copilotAccessAllowed={false}>
      <Story />
    </FilesPageInfoProvider>
  )
}

export function currentTreeDecorator(Story: StoryFn) {
  return (
    <CurrentTreeProvider payload={payload}>
      <Story />
    </CurrentTreeProvider>
  )
}

const repository = createRepository({
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
})

const refInfo: RefInfo = {
  name: 'main',
  listCacheKey: 'key',
  refType: 'branch',
  canEdit: true,
  currentOid: '1234',
}

const payload = {
  items: [
    {
      name: 'folder',
      contentType: 'directory',
      path: '/test/path/folder',
    } as DirectoryItem,
    {
      name: 'file',
      contentType: 'file',
      path: '/test/path/file',
    } as DirectoryItem,
  ],
  readme: undefined,
  totalCount: 2,
  showBranchInfobar: false,
}
