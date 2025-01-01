import type {SubmoduleDiff, SummaryDelta} from '../types'

const mockSubmoduleSummaries: SummaryDelta[] = [
  createSummaryDelta(5, 7, 'CHANGELOG.md', 'MODIFIED'),
  createSummaryDelta(5, 7, 'CONTRIBUTING.md', 'MODIFIED'),
  createSummaryDelta(5, 7, 'README.md', 'MODIFIED'),
  createSummaryDelta(0, 7, 'lib/github-ui.js', 'REMOVED'),
  createSummaryDelta(5, 0, 'lib/github-ui.css', 'ADDED'),
  createSummaryDelta(9877, 4832, 'src/components/GameBoard.js', 'MODIFIED'),
  createSummaryDelta(
    25,
    47,
    'src/graphql/queries/that-reall-long-filename-it-would-wrap-definitely-anditsokthatitwraps-because-we-are-aligning-t-top.ts',
    'MODIFIED',
  ),
  createSummaryDelta(5, 7, 'src/components/Tile.js', 'MODIFIED'),
]

export const mockSubmodule: SubmoduleDiff = {
  basePath: 'illuminati',
  submoduleUrl: 'http://www.github.com/monalisa/illuminati', // can also be a gist, wiki, or non-GitHub URL
  contentsUrl: 'http://www.github.com/monalisa/illuminati', // can also be a gist, wiki, tree, or non-GitHub URL
  changedFiles: mockSubmoduleSummaries.length,
  newCommitOid: 'd552450188b7d9171d36327d8b7bd725e20a54cb',
  oldCommitOid: 'e1da9b0583d7d3fbc0676aa832808d91e49a03f2',
  summary: mockSubmoduleSummaries,
  status: 'MODIFIED',
}

export const mockSubmoduleWithoutSummaries: SubmoduleDiff = {
  ...mockSubmodule,
  summary: [],
  changedFiles: undefined,
}

function createSummaryDelta(linesAdded: number, linesDeleted: number, path: string, status: string): SummaryDelta {
  return {
    linesAdded,
    linesDeleted,
    path,
    pathDigest: `mockdigest${path}`,
    status,
  }
}
