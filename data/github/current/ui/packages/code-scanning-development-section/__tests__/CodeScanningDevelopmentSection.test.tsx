import {screen, waitFor, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {http, HttpResponse} from 'msw'
import {CodeScanningDevelopmentSection} from '../CodeScanningDevelopmentSection'
import {
  foundBranch,
  foundPullRequest,
  getCodeScanningDevelopmentSectionProps,
  linkedPullRequest,
  queryToFind,
} from '../test-utils/mock-data'
import {setupServer} from './server'

const {server} = setupServer()

describe('CodeScanningDevelopmentSection', () => {
  describe('Without alert links', () => {
    test('Renders the section title and a description placeholder when the user has readonly permissions', () => {
      const props = getCodeScanningDevelopmentSectionProps()
      render(<CodeScanningDevelopmentSection {...props} />)

      expect(screen.getByText('Development')).toBeInTheDocument()
      expect(screen.getByText('No linked branches or pull requests.')).toBeInTheDocument()
      expect(screen.queryByTestId('development-section-commit-autofix-button')).not.toBeInTheDocument()
    })

    test('Renders the section title and a description placeholder when has readonly permissions and there is a suggested fix', () => {
      const props = getCodeScanningDevelopmentSectionProps({
        hasSuggestedFix: true,
        alertTitle: 'alert-title',
      })
      render(<CodeScanningDevelopmentSection {...props} />)

      expect(screen.getByText('Development')).toBeInTheDocument()
      expect(screen.getByText('No linked branches or pull requests.')).toBeInTheDocument()
      expect(screen.queryByTestId('development-section-commit-autofix-button')).not.toBeInTheDocument()
    })

    test('Renders the section title and a description placeholder when the alert is closed and the user has readonly permissions', () => {
      const props = getCodeScanningDevelopmentSectionProps({isAlertClosed: true})
      render(<CodeScanningDevelopmentSection {...props} />)

      expect(screen.getByText('Development')).toBeInTheDocument()
      expect(screen.getByText('No linked branches or pull requests.')).toBeInTheDocument()
      expect(screen.queryByTestId('development-section-commit-autofix-button')).not.toBeInTheDocument()
    })

    test('Renders the commit autofix to branch link if there is a suggested fix and the user has repository-write permissions', () => {
      const props = getCodeScanningDevelopmentSectionProps({
        hasSuggestedFix: true,
        pushableByUser: true,
        alertTitle: 'alert-title',
      })
      render(<CodeScanningDevelopmentSection {...props} />)

      expect(screen.getByText('Development')).toBeInTheDocument()
      expect(screen.getByTestId('development-section-commit-autofix-button')).toBeInTheDocument()
    })

    test('Renders the create branch link if user has repository-write permissions', () => {
      const props = getCodeScanningDevelopmentSectionProps({
        pushableByUser: true,
      })
      render(<CodeScanningDevelopmentSection {...props} />)

      expect(screen.getByText('Development')).toBeInTheDocument()
      expect(screen.getByTestId('development-section-create-branch-button')).toBeInTheDocument()
    })

    test('Renders the button to open the pull requests and branches picker', () => {
      const props = getCodeScanningDevelopmentSectionProps({
        pushableByUser: true,
      })
      render(<CodeScanningDevelopmentSection {...props} />)

      expect(screen.getByText('Development')).toBeInTheDocument()
      expect(screen.getByTestId('development-section-picker-button')).toBeInTheDocument()
    })

    test('Renders the button to open the pull requests and branches picker when the alert is closed', () => {
      const props = getCodeScanningDevelopmentSectionProps({
        pushableByUser: true,
        isAlertClosed: true,
      })
      render(<CodeScanningDevelopmentSection {...props} />)

      expect(screen.getByText('Development')).toBeInTheDocument()
      expect(screen.getByTestId('development-section-picker-button')).toBeInTheDocument()
    })
  })

  describe('With alert links', () => {
    test('Renders the section title and a list of alert links', () => {
      const props = getCodeScanningDevelopmentSectionProps({withAlertLinks: true})
      render(<CodeScanningDevelopmentSection {...props} />)

      expect(screen.getByText('Development')).toBeInTheDocument()
      expect(screen.getByTestId('development-section-alert-links')).toBeInTheDocument()
      expect(screen.getByText('fix-alert-1')).toBeInTheDocument()
      expect(screen.getByText('Fix alert 1')).toBeInTheDocument()
      expect(screen.getByTestId('development-section-pull-request-description')).toBeInTheDocument()
      expect(screen.getByTestId('development-section-branch-description')).toBeInTheDocument()
    })

    test('Renders alert links if there are any when the alert is closed', () => {
      const props = getCodeScanningDevelopmentSectionProps({
        withAlertLinks: true,
        isAlertClosed: true,
      })
      render(<CodeScanningDevelopmentSection {...props} />)

      expect(screen.getByText('Development')).toBeInTheDocument()
      expect(screen.getByTestId('development-section-alert-links')).toBeInTheDocument()
      expect(screen.getByText('fix-alert-1')).toBeInTheDocument()
      expect(screen.getByText('Fix alert 1')).toBeInTheDocument()
      expect(screen.getByTestId('development-section-pull-request-description')).toBeInTheDocument()
      expect(screen.getByTestId('development-section-branch-description')).toBeInTheDocument()
    })
  })

  describe('Search to find and link pull request', () => {
    test('find without free text', async () => {
      const requestSpy = jest.fn()
      server.use(
        http.get('*', ({request}) => {
          requestSpy(request.url)
        }),
      )

      const props = getCodeScanningDevelopmentSectionProps()
      const {user} = render(<CodeScanningDevelopmentSection {...props} />)
      await user.click(screen.getByText('Development'))

      expect(screen.getByText('Link a branch or pull request')).toBeInTheDocument()
      expect(screen.getByPlaceholderText('Search pull requests')).toBeInTheDocument()
      expect(screen.getByText(foundPullRequest.title)).toBeInTheDocument()
      expect(screen.getByText(foundBranch.name)).toBeInTheDocument()
      expect(requestSpy).toHaveBeenCalledTimes(1)
      expect(requestSpy).toHaveBeenNthCalledWith(1, expect.stringMatching(/\?query=$/))

      await user.type(screen.getByPlaceholderText('Search pull requests'), queryToFind.pull_request)
      await waitFor(() => {
        expect(requestSpy).toHaveBeenCalledTimes(2)
      })

      expect(screen.getByText(foundPullRequest.title)).toBeInTheDocument()
      expect(screen.queryByText(foundBranch.name)).not.toBeInTheDocument()
      expect(requestSpy).toHaveBeenNthCalledWith(2, expect.stringMatching(/\?query=title$/))
    })

    test('always show initially selected items alongside search results', async () => {
      const requestSpy = jest.fn()
      server.use(
        http.get('*', ({request}) => {
          requestSpy(request.url)
        }),
      )

      const props = getCodeScanningDevelopmentSectionProps({withAlertLinks: true})
      const {user} = render(<CodeScanningDevelopmentSection {...props} />)
      await user.click(screen.getByText('Development'))

      // Because the previously selected pull request is in the list below the picker,
      // we need this container to be able to look for the pull request title,
      // and only find it *once*.
      const dialog = screen.getByRole('dialog')
      expect(screen.getByText('Link a branch or pull request')).toBeInTheDocument()
      // The initially selected pull request
      expect(within(dialog).getByText('Fix alert 1')).toBeInTheDocument()
      // The possibly suggestions
      expect(screen.getByText('Suggestions')).toBeInTheDocument()
      expect(screen.getByText('Some PR Title')).toBeInTheDocument()
      expect(screen.getByText('Some Branch Name')).toBeInTheDocument()

      // Search such that "Some PR Title" should only be found
      await user.type(screen.getByPlaceholderText('Search pull requests'), 'title')
      await waitFor(() => {
        expect(requestSpy).toHaveBeenCalledTimes(2)
      })
      expect(within(dialog).getByText('Fix alert 1')).toBeInTheDocument()
      expect(screen.getByText('Some PR Title')).toBeInTheDocument()
      expect(screen.queryByText('Some Branch Name')).not.toBeInTheDocument()
    })

    test('groups of selected and suggestions', async () => {
      const props = getCodeScanningDevelopmentSectionProps({withAlertLinks: true})
      const {user} = render(<CodeScanningDevelopmentSection {...props} />)
      await user.click(screen.getByText('Development'))

      const dialog = screen.getByRole('dialog')
      expect(within(dialog).getByText('Fix alert 1')).toBeInTheDocument()
      expect(screen.getByText('Suggestions')).toBeInTheDocument()
      expect(screen.getByText('Some PR Title')).toBeInTheDocument()
      expect(screen.getByText('Some Branch Name')).toBeInTheDocument()

      // Search such that nothing will be found
      await user.type(screen.getByPlaceholderText('Search pull requests'), 'blablabla')
      await waitFor(() => {
        expect(screen.queryByText('Suggestions')).not.toBeInTheDocument()
      })
      expect(within(dialog).getByText('Fix alert 1')).toBeInTheDocument()
    })

    test('coping with server error on search', async () => {
      const props = getCodeScanningDevelopmentSectionProps()
      server.use(
        http.get(props.linkableItemsSearchPath, () => {
          return HttpResponse.text('Unicorn love', {status: 500})
        }),
      )

      const {user} = render(<CodeScanningDevelopmentSection {...props} />)
      await user.click(screen.getByText('Development'))

      expect(screen.getByText('Link a branch or pull request')).toBeInTheDocument()
      await user.type(screen.getByPlaceholderText('Search pull requests'), queryToFind.error)
      await waitFor(() => {
        expect(screen.getByText('Search error')).toBeInTheDocument()
      })
      expect(screen.getByText(/Try a moment later/)).toBeInTheDocument()
    })

    test('selecting a pull request choice and trigger the mutation', async () => {
      const props = getCodeScanningDevelopmentSectionProps()
      server.use(
        http.patch(props.updateAlertLinksPath, async () => {
          return HttpResponse.json({
            data: {
              message: 'Thanks!',
              linked_branches: [],
              linked_pull_requests: [linkedPullRequest],
            },
          })
        }),
      )
      const {user} = render(<CodeScanningDevelopmentSection {...props} />)

      expect(screen.queryByTestId('development-section-branch-item')).not.toBeInTheDocument()
      expect(screen.queryByTestId('development-section-pull-request-item')).not.toBeInTheDocument()

      await user.click(screen.getByText('Development'))

      expect(screen.getByText('Link a branch or pull request')).toBeInTheDocument()

      // expect that there are no selected items
      const foundPrTitle = foundPullRequest.title
      const allOptions = await screen.findAllByRole('option')
      expect(allOptions).toHaveLength(2)
      expect(allOptions[0]).toHaveAttribute('aria-selected', 'false')
      expect(allOptions[1]).toHaveAttribute('aria-selected', 'false')

      user.click(screen.getByRole('option', {name: new RegExp(foundPrTitle, 'i')}))
      // we've selected the pull request, now when we click to close the dialog
      // we should trigger the mutation
      await user.click(screen.getByText('Development'))
      expect(screen.queryByTestId('development-section-branch-item')).not.toBeInTheDocument()
      const linkedPrs = await screen.findAllByTestId('development-section-pull-request-item')
      expect(linkedPrs).toHaveLength(1)

      expect(screen.getByText(linkedPullRequest.title)).toBeInTheDocument()
    })

    test('coping with server error on mutation', async () => {
      const props = getCodeScanningDevelopmentSectionProps()
      server.use(
        http.patch(props.updateAlertLinksPath, () => {
          return HttpResponse.text('Unicorn love', {status: 500})
        }),
      )

      const {user} = render(<CodeScanningDevelopmentSection {...props} />)
      await user.click(screen.getByText('Development'))

      user.click(screen.getByRole('option', {name: new RegExp(foundPullRequest.title, 'i')}))

      await user.click(screen.getByText('Development'))
      await waitFor(() => {
        expect(screen.getByText('Save error')).toBeInTheDocument()
      })
    })
  })
})
