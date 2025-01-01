import {BASE_PAGE_DATA_URL, renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import CommandLineInstructionsDialog, {type CommandLineInstructionsDialogProps} from '../CommandLineInstructionsDialog'
import {screen} from '@testing-library/react'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {mockFetch} from '@github-ui/mock-fetch'
import {
  defaultMergeInstructionsApiResponse,
  httpPushProtocol,
  noHeadRepositoryMergeInstructionsApiResponse,
  sshPushProtocol,
} from '../../../../../test-utils/mocks/merge-instructions-mock'

afterEach(() => jest.clearAllMocks())

const mergeInstructionsPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.mergeInstructions}`

describe('CommandLineInstructionsDialog', () => {
  const defaultProps: CommandLineInstructionsDialogProps = {
    baseRefName: 'main',
    conflictsCondition: {result: 'PASSED'},
    headRepository: {ownerLogin: 'wiseguy', name: 'source'},
    isCrossRepo: false,
    onClose: jest.fn(),
    returnFocusRef: {current: null},
  }

  describe('when the merge instructions page data is not available', () => {
    test('renders the fallback', async () => {
      jest.spyOn(console, 'error').mockImplementation()
      mockFetch.mockRouteOnce(mergeInstructionsPageDataRoute, {}, {status: 404, ok: false})
      renderWithClient(<CommandLineInstructionsDialog {...defaultProps} />)

      expect(await screen.findByText('Merging via command line')).toBeInTheDocument()
      expect(screen.getByText('Unable to load the merge instructions')).toBeInTheDocument()
    })
  })

  describe('when the merge instructions page data is available', () => {
    test('when there are no conflicts or the conflicts status is unknown, renders the correct instructions', async () => {
      mockFetch.mockRouteOnce(mergeInstructionsPageDataRoute, defaultMergeInstructionsApiResponse)
      renderWithClient(<CommandLineInstructionsDialog {...defaultProps} />)

      expect(await screen.findByText('Merging via command line')).toBeInTheDocument()
      expect(
        screen.getByText(/Clone the repository or update your local repository with the latest changes./),
      ).toBeInTheDocument()
      expect(screen.getByText(/Switch to the base branch of the pull request./)).toBeInTheDocument()
      expect(screen.getByText(/Merge the head branch into the base branch./)).toBeInTheDocument()
      expect(screen.getByText(/Push the changes./)).toBeInTheDocument()
    })

    test('when there are conflicts, renders the correct instructions', async () => {
      const props: CommandLineInstructionsDialogProps = {
        ...defaultProps,
        conflictsCondition: {result: 'FAILED'},
      }
      mockFetch.mockRouteOnce(mergeInstructionsPageDataRoute, defaultMergeInstructionsApiResponse)
      renderWithClient(<CommandLineInstructionsDialog {...props} />)

      expect(await screen.findByText(/Checkout via the command line/)).toBeInTheDocument()
      expect(screen.getByText(/Switch to the head branch of the pull request./)).toBeInTheDocument()
      expect(screen.getByText(/Merge the base branch into the head branch./)).toBeInTheDocument()
      expect(screen.getByText(/Fix the conflicts and commit the result./)).toBeInTheDocument()
      expect(screen.getByText(/Resolving a merge conflict using the command line/)).toBeInTheDocument()
      expect(screen.getByText(/Push the changes./)).toBeInTheDocument()
    })

    test('when the shell safe branch names include placeholders, renders documentation link', async () => {
      mockFetch.mockRouteOnce(mergeInstructionsPageDataRoute, {
        ...defaultMergeInstructionsApiResponse,
        shellSafeNamesIncludePlaceholders: true,
      })

      renderWithClient(<CommandLineInstructionsDialog {...defaultProps} />)

      expect(
        await screen.findByText('Learn about dealing with special characters on the command line.'),
      ).toBeInTheDocument()
    })

    test('when the shell safe branch names do not include placeholders, does not render documentation link', async () => {
      mockFetch.mockRouteOnce(mergeInstructionsPageDataRoute, defaultMergeInstructionsApiResponse)

      renderWithClient(<CommandLineInstructionsDialog {...defaultProps} />)

      expect(await screen.findByText('Merging via command line')).toBeInTheDocument()
      expect(screen.queryByText('Learn about dealing with special characters on the command line.')).toBeNull()
    })

    test('when the head repository is cross-repository, renders the correct instructions', async () => {
      mockFetch.mockRouteOnce(mergeInstructionsPageDataRoute, defaultMergeInstructionsApiResponse)
      const props = {
        ...defaultProps,
        isCrossRepo: true,
      }

      renderWithClient(<CommandLineInstructionsDialog {...props} />)

      expect(await screen.findByText('Merging via command line')).toBeInTheDocument()
      expect(
        screen.getByText('From your project repository, check out a new branch and test the changes.'),
      ).toBeInTheDocument()
    })

    test('sets the initially selected protocol from the API', async () => {
      mockFetch.mockRouteOnce(mergeInstructionsPageDataRoute, {
        ...defaultMergeInstructionsApiResponse,
        pushProtocols: [
          {...sshPushProtocol, isDefault: false},
          {...httpPushProtocol, isDefault: true},
        ],
      })

      renderWithClient(<CommandLineInstructionsDialog {...defaultProps} />)

      expect(await screen.findByText('Merging via command line')).toBeInTheDocument()
      // The URL for the default protocol should be in the text input
      expect(screen.getByDisplayValue('http://github.localhost/wiseguy/source.git')).toBeInTheDocument()
    })

    test('selecting a different protocol displays the correct clone url', async () => {
      mockFetch.mockRouteOnce(mergeInstructionsPageDataRoute, defaultMergeInstructionsApiResponse)

      const {user} = renderWithClient(<CommandLineInstructionsDialog {...defaultProps} />)

      expect(await screen.findByText('Merging via command line')).toBeInTheDocument()
      // The URL for the default protocol should be in the text input
      expect(screen.getByDisplayValue('ssh://git@localhost:3035/wiseguy/source.git')).toBeInTheDocument()

      const httpsButton = screen.getByRole('button', {name: 'HTTPS'})

      await user.click(httpsButton)

      expect(screen.getByDisplayValue('http://github.localhost/wiseguy/source.git')).toBeInTheDocument()
    })

    test('selecting a different protocol (either SSH or HTTP) makes a request to persist the preference', async () => {
      mockFetch.mockRouteOnce(mergeInstructionsPageDataRoute, defaultMergeInstructionsApiResponse)

      const {user} = renderWithClient(<CommandLineInstructionsDialog {...defaultProps} />)

      expect(await screen.findByText('Merging via command line')).toBeInTheDocument()
      // The URL for the default protocol should be in the text input
      expect(screen.getByDisplayValue('ssh://git@localhost:3035/wiseguy/source.git')).toBeInTheDocument()

      const httpsButton = screen.getByRole('button', {name: 'HTTPS'})

      await user.click(httpsButton)

      expect(screen.getByDisplayValue('http://github.localhost/wiseguy/source.git')).toBeInTheDocument()
      const httpProtocol = defaultMergeInstructionsApiResponse.pushProtocols.find(p => p.protocol === 'HTTP')
      expect(httpProtocol).toBeDefined()
      const calls = mockFetch.calls()
      const initialFetchUrl = calls[0][0]
      const setProtocolFetchUrl = calls[1][0]
      expect(initialFetchUrl).toBe(mergeInstructionsPageDataRoute)
      expect(setProtocolFetchUrl).toBe(httpProtocol?.stickyUrl)
    })

    test('only shows available protocols - ssh is not available', async () => {
      mockFetch.mockRouteOnce(mergeInstructionsPageDataRoute, {
        ...defaultMergeInstructionsApiResponse,
        pushProtocols: [
          {...sshPushProtocol, isAvailable: false, isDefault: false},
          {...httpPushProtocol, isDefault: true},
        ],
      })

      renderWithClient(<CommandLineInstructionsDialog {...defaultProps} />)

      expect(await screen.findByText('Merging via command line')).toBeInTheDocument()

      expect(screen.getByRole('button', {name: 'HTTPS'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Patch'})).toBeInTheDocument()
      expect(screen.queryByRole('button', {name: 'SSH'})).not.toBeInTheDocument()
    })

    test('only shows available protocols - only patch is available', async () => {
      mockFetch.mockRouteOnce(mergeInstructionsPageDataRoute, {
        ...defaultMergeInstructionsApiResponse,
        pushProtocols: [
          {...sshPushProtocol, isAvailable: false, isDefault: false},
          {...httpPushProtocol, isAvailable: false, isDefault: true},
        ],
      })

      renderWithClient(<CommandLineInstructionsDialog {...defaultProps} />)

      expect(await screen.findByText('Merging via command line')).toBeInTheDocument()

      expect(screen.getByRole('button', {name: 'Patch'})).toBeInTheDocument()
      expect(screen.queryByRole('button', {name: 'HTTPS'})).not.toBeInTheDocument()
      expect(screen.queryByRole('button', {name: 'SSH'})).not.toBeInTheDocument()
    })

    test('if there is no head repository, only the patch options and url are shown', async () => {
      mockFetch.mockRouteOnce(mergeInstructionsPageDataRoute, noHeadRepositoryMergeInstructionsApiResponse)

      const props = {
        ...defaultProps,
        headRepository: null,
      }

      renderWithClient(<CommandLineInstructionsDialog {...props} />)

      expect(await screen.findByText('Merging via command line')).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Patch'})).toBeInTheDocument()
      expect(screen.queryByRole('button', {name: 'HTTPS'})).not.toBeInTheDocument()
      expect(screen.queryByRole('button', {name: 'SSH'})).not.toBeInTheDocument()
    })
  })
})
