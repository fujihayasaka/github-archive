import type {CommitsDropdownProps} from '../components/CommitsDropdown'
import type {FileTreePayload} from '../page-data/payloads/file-tree'

const commit1Oid = 'a631866b0075443de782a08024a2368296b83b9e'
const commit2Oid = 'e3884b7d64007768b0240b22dceaa8fc3537731c'
const commit3Oid = 'a9abc6e361fb2bece63858eff142ea361637aa5a'

export function getMockPullRequestFileTreePageData(): FileTreePayload {
  return {
    ...getMockCommitsDropDownPageData(),
    ...getMockFileTreePageData(),
    ownerLogin: 'test-user',
    pathName: '/test-user/test-repo/pull/1',
    pullRequestId: 'PR_kw1ag',
    pullRequestNumber: 1,
    repositoryName: 'test-repo',
  }
}

export function getMockCommitsDropDownPageData(): Omit<CommitsDropdownProps, 'onRangeUpdated'> {
  return {
    baseRefOid: 'abc123',
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
  }
}

export function getMockFileTreePageData(): Pick<FileTreePayload, 'diffs'> {
  return {
    diffs: [
      {
        changeType: 'ADDED',
        path: 'src/index.js',
        pathDigest: 'bfe9874d239014961b1ae4e89875a6155667db834a410aaaa2ebe3cf89820556',
        highestAnnotationLevel: 'NOTICE',
        totalCommentsCount: 0,
      },
      {
        changeType: 'CHANGED',
        path: 'src/components/Component.js',
        pathDigest: 'ade8d717547a7b8930387d20811fcd361704eeef10ad72c5a1943d1131489952',
        highestAnnotationLevel: 'WARNING',
        totalCommentsCount: 1,
      },
      {
        changeType: 'DELETED',
        path: 'src/components/Component.test.js',
        pathDigest: '221956e3d9c5227b4ee6c22d56600f77c760fb1cb3666cbcc1376a97d12005c1',
        highestAnnotationLevel: 'FAILURE',
        totalCommentsCount: 2,
      },
      {
        changeType: 'RENAMED',
        path: 'src/components/Component.css',
        pathDigest: 'ea53a51cd6735cfd06295de5c4f44da72e2f02da92bfc8afd8728357d6022bfc',
        highestAnnotationLevel: 'NOTICE',
        totalCommentsCount: 0,
      },
    ],
  }
}

export function getMockSpecialFileTreePageData(): Pick<FileTreePayload, 'diffs'> {
  return {
    diffs: [
      {
        changeType: 'ADDED',
        isCodeowner: true,
        path: 'src/index.js',
        pathDigest: 'bfe9874d239014961b1ae4e89875a6155667db834a410aaaa2ebe3cf89820556',
      },
      {
        changeType: 'CHANGED',
        path: 'src/components/Component.js',
        pathDigest: 'ade8d717547a7b8930387d20811fcd361704eeef10ad72c5a1943d1131489952',
      },
      {
        changeType: 'DELETED',
        isVendored: true,
        path: 'src/components/Component.test.js',
        pathDigest: '221956e3d9c5227b4ee6c22d56600f77c760fb1cb3666cbcc1376a97d12005c1',
      },
      {
        changeType: 'RENAMED',
        isManifestFile: true,
        path: 'src/components/Component.css',
        pathDigest: 'ea53a51cd6735cfd06295de5c4f44da72e2f02da92bfc8afd8728357d6022bfc',
      },
    ],
  }
}
