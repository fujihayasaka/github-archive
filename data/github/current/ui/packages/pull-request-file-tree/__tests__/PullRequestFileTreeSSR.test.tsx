/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getMockPullRequestFileTreePageData} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders pull-request-file-tree partial with SSR', async () => {
  const mockData = getMockPullRequestFileTreePageData()
  const view = await serverRenderReact({
    name: 'pull-request-file-tree',
    data: {props: {}},
  })

  const directoriesAndFilePaths = mockData.diffs.flatMap(diff => diff.path.split('/'))
  const expectedFileTreeItems = new Set<string>(directoriesAndFilePaths)

  // verify ssr was able to render content
  for (const expectedFileTreeItem of expectedFileTreeItems) {
    expect(view).toMatch(expectedFileTreeItem)
  }
})
