import {act, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PullRequestHeaderSummary, type PullRequestHeaderSummaryProps} from '../components/PullRequestHeaderSummary'
import {getHeaderPageData} from '../test-utils/header-mock-data'
import {SearchIndex} from '@github-ui/ref-selector/search-index'

afterEach(() => {
  // restore the spy created with spyOn
  jest.restoreAllMocks()
})

function PullRequestHeaderSummaryTestComponent(props: PullRequestHeaderSummaryProps) {
  return (
    <PageDataContextProvider basePageDataUrl={`${BASE_PAGE_DATA_URL}/commits`}>
      <PullRequestHeaderSummary {...props} />
    </PageDataContextProvider>
  )
}

describe('Pull Request Header Summary', () => {
  test('renders pull request author', () => {
    const {
      repository: {ownerLogin, name},
      pullRequest: {author, baseBranch, commitsCount, state, headBranch, headRepositoryName, headRepositoryOwnerLogin},
    } = getHeaderPageData()

    render(
      <PullRequestHeaderSummaryTestComponent
        author={author.login}
        baseBranch={baseBranch}
        baseRepositoryOwnerLogin={ownerLogin}
        baseRepositoryName={name}
        commitsCount={commitsCount}
        headBranch={headBranch}
        headRepositoryOwnerLogin={headRepositoryOwnerLogin}
        headRepositoryName={headRepositoryName}
        state={state}
      />,
    )

    const authorLink = screen.getByRole('link', {name: author.login})
    expect(authorLink).toHaveAttribute('href', `/${author.login}`)
  })

  test('renders pull request branch info', () => {
    const {
      repository: {ownerLogin, name},
      pullRequest: {author, baseBranch, commitsCount, state, headBranch, headRepositoryName, headRepositoryOwnerLogin},
    } = getHeaderPageData()

    render(
      <PullRequestHeaderSummaryTestComponent
        author={author.login}
        baseBranch={baseBranch}
        baseRepositoryOwnerLogin={ownerLogin}
        baseRepositoryName={name}
        commitsCount={commitsCount}
        headBranch={headBranch}
        headRepositoryOwnerLogin={headRepositoryOwnerLogin}
        headRepositoryName={headRepositoryName}
        state={state}
      />,
    )

    expect(screen.getByRole('link', {name: baseBranch})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: headBranch})).toBeInTheDocument()
    // Base branch selector should be hidden by default
    expect(screen.queryByRole('button', {name: `${baseBranch} branch`})).not.toBeInTheDocument()
    expect(screen.getByText(`wants to merge ${commitsCount} commit into`, {exact: false})).toBeInTheDocument()
  })

  test('uses plural form of "commit" when there are multiple commits', () => {
    const {
      repository: {ownerLogin, name},
      pullRequest: {author, baseBranch, headBranch, headRepositoryName, headRepositoryOwnerLogin, state},
    } = getHeaderPageData()

    render(
      <PullRequestHeaderSummaryTestComponent
        author={author.login}
        baseBranch={baseBranch}
        baseRepositoryOwnerLogin={ownerLogin}
        baseRepositoryName={name}
        commitsCount={2}
        headBranch={headBranch}
        headRepositoryOwnerLogin={headRepositoryOwnerLogin}
        headRepositoryName={headRepositoryName}
        state={state}
      />,
    )

    expect(screen.getByText('2 commits into', {exact: false})).toBeInTheDocument()
  })

  test('renders message when PR is merged with no merger', () => {
    const {
      repository: {ownerLogin, name},
      pullRequest: {author, baseBranch, commitsCount, headBranch, headRepositoryName, headRepositoryOwnerLogin},
    } = getHeaderPageData()

    render(
      <PullRequestHeaderSummaryTestComponent
        author={author.login}
        baseBranch={baseBranch}
        baseRepositoryOwnerLogin={ownerLogin}
        baseRepositoryName={name}
        commitsCount={commitsCount}
        headBranch={headBranch}
        headRepositoryOwnerLogin={headRepositoryOwnerLogin}
        headRepositoryName={headRepositoryName}
        state="MERGED"
      />,
    )

    expect(screen.getByText(`${commitsCount} commit merged into`, {exact: false})).toBeInTheDocument()
  })

  test('renders message when PR is merged with merger', () => {
    const {
      repository: {ownerLogin, name},
      pullRequest: {author, baseBranch, commitsCount, headBranch, headRepositoryName, headRepositoryOwnerLogin},
    } = getHeaderPageData()

    render(
      <PullRequestHeaderSummaryTestComponent
        author={author.login}
        baseBranch={baseBranch}
        baseRepositoryOwnerLogin={ownerLogin}
        baseRepositoryName={name}
        commitsCount={commitsCount}
        headBranch={headBranch}
        headRepositoryOwnerLogin={headRepositoryOwnerLogin}
        headRepositoryName={headRepositoryName}
        mergedBy="monalisa"
        state="MERGED"
      />,
    )

    expect(screen.getByText('monalisa')).toBeInTheDocument()
    expect(screen.getByText(`merged ${commitsCount} commit into`, {exact: false})).toBeInTheDocument()
  })

  test('adds repository owner names to the branch names when they differ from the base repository', () => {
    const {
      repository: {ownerLogin, name},
      pullRequest: {author, baseBranch, commitsCount, headBranch, headRepositoryName, state},
    } = getHeaderPageData()

    render(
      <PullRequestHeaderSummaryTestComponent
        author={author.login}
        baseBranch={baseBranch}
        baseRepositoryOwnerLogin={ownerLogin}
        baseRepositoryName={name}
        commitsCount={commitsCount}
        headBranch={headBranch}
        headRepositoryOwnerLogin="different-owner"
        headRepositoryName={headRepositoryName}
        state={state}
      />,
    )

    expect(screen.getByText(`${ownerLogin}:${baseBranch}`)).toBeInTheDocument()
    expect(screen.getByText(`different-owner:${headBranch}`)).toBeInTheDocument()
  })

  test('adds repository name to the head branch when the repoository is an advisory repo', () => {
    const {
      repository: {ownerLogin, name},
      pullRequest: {author, baseBranch, commitsCount, headBranch, headRepositoryName, headRepositoryOwnerLogin, state},
    } = getHeaderPageData()

    render(
      <PullRequestHeaderSummaryTestComponent
        author={author.login}
        baseBranch={baseBranch}
        baseRepositoryOwnerLogin={ownerLogin}
        baseRepositoryName={name}
        commitsCount={commitsCount}
        headBranch={headBranch}
        headRepositoryOwnerLogin={headRepositoryOwnerLogin}
        headRepositoryName={headRepositoryName}
        isInAdvisoryRepo
        state={state}
      />,
    )

    expect(screen.getByText(baseBranch)).toBeInTheDocument()
    expect(screen.getByText(`${headRepositoryName}:${headBranch}`)).toBeInTheDocument()
  })

  test('adds repository owner and name to the head branch when the repoository is an advisory repo and the owner differs', () => {
    const {
      repository: {ownerLogin, name},
      pullRequest: {author, baseBranch, commitsCount, headBranch, headRepositoryName, state},
    } = getHeaderPageData()

    render(
      <PullRequestHeaderSummaryTestComponent
        author={author.login}
        baseBranch={baseBranch}
        baseRepositoryOwnerLogin={ownerLogin}
        baseRepositoryName={name}
        commitsCount={commitsCount}
        headBranch={headBranch}
        headRepositoryOwnerLogin="different-owner"
        headRepositoryName={headRepositoryName}
        isInAdvisoryRepo
        state={state}
      />,
    )

    expect(screen.getByText(`${ownerLogin}:${baseBranch}`)).toBeInTheDocument()
    expect(screen.getByRole('link', {name: `different-owner/${headRepositoryName}:${headBranch}`})).toBeInTheDocument()
  })

  test('if no head repository owner is provided branch text shows owner and head branch and title says repository has been deleted', () => {
    const {
      repository: {ownerLogin, name},
      pullRequest: {author, baseBranch, commitsCount, headBranch, state},
    } = getHeaderPageData()

    render(
      <PullRequestHeaderSummaryTestComponent
        author={author.login}
        baseBranch={baseBranch}
        baseRepositoryOwnerLogin={ownerLogin}
        baseRepositoryName={name}
        headRepositoryName={undefined}
        headRepositoryOwnerLogin="different-owner"
        commitsCount={commitsCount}
        headBranch={headBranch}
        state={state}
      />,
    )

    expect(screen.getByText(`different-owner:${headBranch}`)).toBeInTheDocument()
    expect(screen.getByText(`different-owner:${headBranch}`)).toHaveAttribute(
      'title',
      'This repository has been deleted',
    )
  })

  test('if no head repository owner or name is provided branch text states the repo is unknown and title says repository has been deleted', () => {
    const {
      repository: {ownerLogin, name},
      pullRequest: {author, baseBranch, commitsCount, headBranch, state},
    } = getHeaderPageData()

    render(
      <PullRequestHeaderSummaryTestComponent
        author={author.login}
        baseBranch={baseBranch}
        baseRepositoryOwnerLogin={ownerLogin}
        baseRepositoryName={name}
        headRepositoryName={undefined}
        headRepositoryOwnerLogin={undefined}
        commitsCount={commitsCount}
        headBranch={headBranch}
        state={state}
      />,
    )

    expect(screen.getByText('unknown repository')).toBeInTheDocument()
    expect(screen.getByText('unknown repository')).toHaveAttribute('title', 'This repository has been deleted')
  })

  test('renders button for copying head branch name to clipboard', async () => {
    const {
      repository: {ownerLogin, name},
      pullRequest: {author, baseBranch, commitsCount, headBranch, headRepositoryName, headRepositoryOwnerLogin, state},
    } = getHeaderPageData()

    const {user} = render(
      <PullRequestHeaderSummaryTestComponent
        author={author.login}
        baseBranch={baseBranch}
        baseRepositoryOwnerLogin={ownerLogin}
        baseRepositoryName={name}
        commitsCount={commitsCount}
        headBranch={headBranch}
        headRepositoryOwnerLogin={headRepositoryOwnerLogin}
        headRepositoryName={headRepositoryName}
        state={state}
      />,
    )

    const copyButton = screen.getByLabelText('Copy head branch name to clipboard', {selector: 'button'})
    await user.click(copyButton)

    await expect(navigator.clipboard.readText()).resolves.toEqual(headBranch)
  })

  describe('changing the base branch', () => {
    // Mock the base branch selector
    beforeEach(() => {
      jest.spyOn(SearchIndex.prototype, 'render').mockImplementation(function (this: SearchIndex) {
        void act(() => this.selector.render())
      })

      jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(function (this: SearchIndex) {
        this.knownItems = ['main', 'current-branch', 'another-branch']
        this.isLoading = false
        this.render()
        return Promise.resolve()
      })
    })

    test('renders base branch selector', () => {
      const {
        pullRequest: {
          author,
          baseBranch,
          commitsCount,
          headBranch,
          headRepositoryOwnerLogin,
          headRepositoryName,
          state,
        },
        repository: {
          defaultBranch: baseRepositoryDefaultBranch,
          name: baseRepositoryName,
          ownerLogin: baseRepositoryOwnerLogin,
        },
        user: {canChangeBase},
      } = getHeaderPageData()

      render(
        <PullRequestHeaderSummaryTestComponent
          author={author.login}
          baseBranch={baseBranch}
          baseRepositoryDefaultBranch={baseRepositoryDefaultBranch}
          baseRepositoryName={baseRepositoryName}
          baseRepositoryOwnerLogin={baseRepositoryOwnerLogin}
          canChangeBase={canChangeBase}
          commitsCount={commitsCount}
          headBranch={headBranch}
          headRepositoryOwnerLogin={headRepositoryOwnerLogin}
          headRepositoryName={headRepositoryName}
          isEditing
          state={state}
        />,
      )
      // Base branch should be rendered as select menu
      expect(screen.getByRole('button', {name: `${baseBranch} branch`})).toBeInTheDocument()
      // Base branch should not be rendered as a link
      expect(screen.queryByRole('link', {name: baseBranch})).not.toBeInTheDocument()
    })

    test('renders confirmation dialog when new base branch is selected', async () => {
      const {
        pullRequest: {
          author,
          baseBranch,
          commitsCount,
          headBranch,
          headRepositoryOwnerLogin,
          headRepositoryName,
          state,
        },
        repository: {
          defaultBranch: baseRepositoryDefaultBranch,
          name: baseRepositoryName,
          ownerLogin: baseRepositoryOwnerLogin,
        },
        user: {canChangeBase},
      } = getHeaderPageData()

      render(
        <PullRequestHeaderSummaryTestComponent
          author={author.login}
          baseBranch={baseBranch}
          baseRepositoryDefaultBranch={baseRepositoryDefaultBranch}
          baseRepositoryName={baseRepositoryName}
          baseRepositoryOwnerLogin={baseRepositoryOwnerLogin}
          canChangeBase={canChangeBase}
          commitsCount={commitsCount}
          headBranch={headBranch}
          headRepositoryOwnerLogin={headRepositoryOwnerLogin}
          headRepositoryName={headRepositoryName}
          isEditing
          state={state}
        />,
      )

      // Open base branch dropdown
      const refSelectorButton = screen.getByRole('button', {name: `${baseBranch} branch`})
      act(() => refSelectorButton.click())

      // Select a new base branch
      const newBaseBranch = screen.getByText('another-branch')
      act(() => newBaseBranch.click())

      // Confirmation dialog appears
      expect(screen.getByRole('button', {name: 'Change base'})).toBeInTheDocument()
    })

    test('does not render base branch selector when base branch is not updateable', () => {
      const {
        pullRequest: {
          author,
          baseBranch,
          commitsCount,
          headBranch,
          headRepositoryOwnerLogin,
          headRepositoryName,
          state,
        },
        repository: {
          defaultBranch: baseRepositoryDefaultBranch,
          name: baseRepositoryName,
          ownerLogin: baseRepositoryOwnerLogin,
        },
      } = getHeaderPageData()

      render(
        <PullRequestHeaderSummaryTestComponent
          author={author.login}
          baseBranch={baseBranch}
          baseRepositoryDefaultBranch={baseRepositoryDefaultBranch}
          baseRepositoryName={baseRepositoryName}
          baseRepositoryOwnerLogin={baseRepositoryOwnerLogin}
          canChangeBase={false}
          commitsCount={commitsCount}
          headBranch={headBranch}
          headRepositoryOwnerLogin={headRepositoryOwnerLogin}
          headRepositoryName={headRepositoryName}
          isEditing
          state={state}
        />,
      )
      // Base branch should not be rendered as select menu
      expect(screen.queryByRole('button', {name: `${baseBranch} branch`})).not.toBeInTheDocument()
      // Base branch should be rendered as a link
      expect(screen.getByRole('link', {name: baseBranch})).toBeInTheDocument()
    })
  })
})
