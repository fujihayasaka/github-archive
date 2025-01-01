import type {DiffFileTreeProps} from '@github-ui/diff-file-tree/file-tree'
import type {DiffDelta} from '@github-ui/diff-file-tree/diff-file-tree-helpers'
import {noop} from '@github-ui/noop'
import type {CommitsDropdownProps} from '../components/CommitsDropdown'
import type {FileFilterProps} from '../components/FileFilter'

const commit1Oid = 'a631866b0075443de782a08024a2368296b83b9e'
const commit2Oid = 'e3884b7d64007768b0240b22dceaa8fc3537731c'
const commit3Oid = 'a9abc6e361fb2bece63858eff142ea361637aa5a'

type MockFileTreeProps = Pick<DiffFileTreeProps, 'diffs'> & {onFileSelected?(file: DiffDelta): void} & Pick<
    FileFilterProps,
    'onFileExtensionsChange' | 'unselectedFileExtensions' | 'onFilterTextChange'
  >
type MockPullRequestFileTreePageData = CommitsDropdownProps & MockFileTreeProps

export function getMockPullRequestFileTreePageData(): MockPullRequestFileTreePageData {
  return {
    ...getMockCommitsDropDownPageData(),
    ...getMockFileTreePageData(),
  }
}

export function getMockCommitsDropDownPageData(): CommitsDropdownProps {
  return {
    baseRefOid: 'abc123',
    commitOids: [commit1Oid, commit2Oid, commit3Oid],
    commits: [
      {
        actorLogin: 'monalisa',
        createdAt: new Date().toString(),
        messageHeadline: 'commit 1',
        oid: commit1Oid,
        shortOid: commit1Oid.slice(0, 7),
      },
      {
        actorLogin: 'monalisa',
        createdAt: new Date().toString(),
        messageHeadline: 'commit 2',
        oid: commit2Oid,
        shortOid: commit2Oid.slice(0, 7),
      },
      {
        actorLogin: 'monalisa',
        createdAt: new Date().toString(),
        messageHeadline: 'commit 3',
        oid: commit3Oid,
        shortOid: commit3Oid.slice(0, 7),
      },
    ],
    onRangeUpdated: noop,
  }
}

function getMockFileTreePageData(): MockFileTreeProps {
  return {
    diffs: [
      {
        changeType: 'ADDED',
        path: 'src/index.js',
        pathDigest: 'src/index.js',
      },
      {
        changeType: 'CHANGED',
        path: 'src/components/Component.js',
        pathDigest: 'src/components/Component.js',
      },
      {
        changeType: 'DELETED',
        path: 'src/components/Component.test.js',
        pathDigest: 'src/components/Component.test.js',
      },
      {
        changeType: 'RENAMED',
        path: 'src/components/Component.css',
        pathDigest: 'src/components/Component.css',
      },
    ],
    onFileSelected: noop,
    onFileExtensionsChange: noop,
    onFilterTextChange: noop,
    unselectedFileExtensions: new Set<string>(),
  }
}
