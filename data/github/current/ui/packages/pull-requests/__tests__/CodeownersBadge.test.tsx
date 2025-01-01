import {screen} from '@testing-library/react'
import {CodeownersBadge} from '../components/CodeownersBadge'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {BASE_PAGE_DATA_URL, renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {mockCodeownersData} from '../test-utils/files-changed/codeowners-mock-data'

const defaultDiffPath = 'path/to/file'
const pullRequestBasePath = `basePageDataURL:${BASE_PAGE_DATA_URL}`
const codeownersQueryKey = [PageData.codeowners, pullRequestBasePath]

describe('CodeownersBadge', () => {
  test('renders nothing if no codeowners are detected', () => {
    const queryClient = getQueryClient()

    const codeownersData = {
      ...mockCodeownersData({}),
      isEnabled: false,
      ownershipByPath: {},
    }
    queryClient.setQueryData(codeownersQueryKey, codeownersData)

    renderWithClient(<CodeownersBadge diffPath={defaultDiffPath} pullRequestBasePath={pullRequestBasePath} />)
    expect(screen.queryByRole('link')).not.toBeInTheDocument()
  })

  test('renders expected tooltip aria label when owned by viewer only', () => {
    const viewerLogin = 'monalisa'
    const queryClient = getQueryClient()

    const codeownersData = mockCodeownersData({makeViewerCodeowner: true})
    queryClient.setQueryData(codeownersQueryKey, codeownersData)

    renderWithClient(
      <CodeownersBadge
        diffPath={defaultDiffPath}
        pullRequestBasePath={pullRequestBasePath}
        viewerLogin={viewerLogin}
      />,
    )
    expect(screen.getByRole('link', {name: 'Owned by you (from CODEOWNERS line 1)'})).toBeInTheDocument()
  })

  test('renders expected tooltip aria label when owned by viewer and others', () => {
    const viewerLogin = 'monalisa'
    const queryClient = getQueryClient()

    const codeownersData = mockCodeownersData({makeViewerCodeowner: true})
    codeownersData['ownershipByPath'][defaultDiffPath]!['owners'] = [`@${viewerLogin}`, '@octocat', '@hubot']

    queryClient.setQueryData(codeownersQueryKey, codeownersData)

    renderWithClient(
      <CodeownersBadge
        diffPath={defaultDiffPath}
        pullRequestBasePath={pullRequestBasePath}
        viewerLogin={viewerLogin}
      />,
    )

    expect(
      screen.getByRole('link', {name: 'Owned by you along with @octocat, @hubot (from CODEOWNERS line 1)'}),
    ).toBeInTheDocument()
  })

  test('renders shield icon with link if codeowners rule url is given', () => {
    const ruleUrl = '/monalisa/smile/blob/main/CODEOWNERS'
    const queryClient = getQueryClient()
    const codeownersData = mockCodeownersData({})
    codeownersData['ownershipByPath'][defaultDiffPath]!['ruleUrl'] = ruleUrl
    queryClient.setQueryData(codeownersQueryKey, codeownersData)

    renderWithClient(<CodeownersBadge diffPath={defaultDiffPath} pullRequestBasePath={pullRequestBasePath} />)

    const link = screen.getByRole('link', {name: 'Owned by @monalisa (from CODEOWNERS line 1)'})
    expect(link).toBeInTheDocument()
    expect(link).toHaveAttribute('href', ruleUrl)
  })

  // Skip until we solve for Invariant Violation raised when Tooltip component child element is non-interactive
  test.skip('renders shield icon with no link if codeowners rule url is not given', () => {
    const queryClient = getQueryClient()
    const codeownersData = mockCodeownersData({})
    codeownersData['ownershipByPath'][defaultDiffPath]!['ruleUrl'] = undefined
    queryClient.setQueryData(codeownersQueryKey, codeownersData)

    renderWithClient(<CodeownersBadge diffPath={defaultDiffPath} pullRequestBasePath={pullRequestBasePath} />)
    expect(screen.queryByRole('link')).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Owned by @monalisa (from CODEOWNERS line 1)'})).toBeInTheDocument()
  })
})
