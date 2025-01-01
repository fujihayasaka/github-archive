import type {PullRequestFileTreeProps} from '../../components/file-tree/PullRequestFileTree'

export function getMockFileTreePageData(): Pick<PullRequestFileTreeProps, 'filteredDiffs'> {
  return {
    filteredDiffs: [
      {
        changeType: 'ADDED',
        path: 'src/index.js',
        pathDigest: 'bfe9874d239014961b1ae4e89875a6155667db834a410aaaa2ebe3cf89820556',
        highestAnnotationLevel: 'NOTICE',
        totalCommentsCount: 0,
        linesChanged: 0,
        linesAdded: 0,
        linesDeleted: 0,
      },
      {
        changeType: 'CHANGED',
        path: 'src/components/Component.js',
        pathDigest: 'ade8d717547a7b8930387d20811fcd361704eeef10ad72c5a1943d1131489952',
        highestAnnotationLevel: 'WARNING',
        totalCommentsCount: 1,
        linesChanged: 0,
        linesAdded: 0,
        linesDeleted: 0,
      },
      {
        changeType: 'DELETED',
        path: 'src/components/Component.test.js',
        pathDigest: '221956e3d9c5227b4ee6c22d56600f77c760fb1cb3666cbcc1376a97d12005c1',
        highestAnnotationLevel: 'FAILURE',
        totalCommentsCount: 2,
        linesChanged: 0,
        linesAdded: 0,
        linesDeleted: 0,
      },
      {
        changeType: 'RENAMED',
        path: 'src/components/Component.css',
        pathDigest: 'ea53a51cd6735cfd06295de5c4f44da72e2f02da92bfc8afd8728357d6022bfc',
        highestAnnotationLevel: 'NOTICE',
        totalCommentsCount: 0,
        linesChanged: 0,
        linesAdded: 0,
        linesDeleted: 0,
      },
    ],
  }
}

export function getMockSpecialFileTreePageData(): Pick<PullRequestFileTreeProps, 'filteredDiffs'> {
  return {
    filteredDiffs: [
      {
        changeType: 'ADDED',
        highestAnnotationLevel: 'NOTICE',
        isCodeowner: true,
        path: 'src/index.js',
        pathDigest: 'bfe9874d239014961b1ae4e89875a6155667db834a410aaaa2ebe3cf89820556',
        totalCommentsCount: 0,
        linesChanged: 0,
        linesAdded: 0,
        linesDeleted: 0,
      },
      {
        changeType: 'CHANGED',
        highestAnnotationLevel: 'WARNING',
        isVendored: true,
        path: 'vendor/components/Component.js',
        pathDigest: 'ade8d717547a7b8930387d20811fcd361704eeef10ad72c5a1943d1131489952',
        totalCommentsCount: 1,
        linesChanged: 0,
        linesAdded: 0,
        linesDeleted: 0,
      },
      {
        changeType: 'DELETED',
        highestAnnotationLevel: 'FAILURE',
        path: 'src/components/Component.test.js',
        pathDigest: '221956e3d9c5227b4ee6c22d56600f77c760fb1cb3666cbcc1376a97d12005c1',
        totalCommentsCount: 2,
        linesChanged: 0,
        linesAdded: 0,
        linesDeleted: 0,
      },
      {
        changeType: 'RENAMED',
        isManifestFile: true,
        path: 'package-lock.json',
        pathDigest: 'ea53a51cd6735cfd06295de5c4f44da72e2f02da92bfc8afd8728357d6022bfc',
        totalCommentsCount: 0,
        linesChanged: 0,
        linesAdded: 0,
        linesDeleted: 0,
      },
    ],
  }
}
