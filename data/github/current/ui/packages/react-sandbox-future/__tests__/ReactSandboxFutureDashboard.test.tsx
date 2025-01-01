import {render} from '@github-ui/react-core/future/test-utils/render'
import {screen, within} from '@testing-library/react'
import {http, HttpResponse} from 'msw'

import {reactSandboxFutureApp} from '../react-sandbox-future'
import {
  getReactSandBoxDashboardDiscussionsPayload,
  getReactSandBoxDashboardIssuesDeferredIssuesPayload,
  getReactSandBoxDashboardIssuesPayload,
} from './utils/mock-data'
import {setupServer} from './utils/mock-server/server'

const {server} = setupServer()

describe('ReactSandboxFuture Dashboard', () => {
  describe('Navigate issues via searchParams', () => {
    test('navigating between open and closed issues', async () => {
      const {user, router} = render(reactSandboxFutureApp, '/_react_sandbox_future/dashboard/issues', {
        embeddedData: getReactSandBoxDashboardIssuesPayload({state: 'open', count: {open: 2, closed: 2}}, false),
      })

      // Verify initial state (open)
      expect(await screen.findByText('Issues for testuser')).toBeInTheDocument()
      const issueNav = await screen.findByTestId('issues-nav')
      const issueTable = await screen.findByTestId('issue-table')

      expect(within(issueNav).getByRole('link', {name: 'Open Issues (2)', current: 'page'})).toBeInTheDocument()
      expect(within(issueNav).getByRole('link', {name: 'Closed Issues (2)', current: false})).toBeInTheDocument()
      expect(within(issueTable).getAllByText(/Open Issue/)).toHaveLength(2)
      expect(within(issueTable).queryAllByText(/Closed Issue/)).toHaveLength(0)
      expect(document.title).toBe('ReactSandboxFuture Dashboard Issues')
      expect(router.state.location?.pathname).toBe('/_react_sandbox_future/dashboard/issues')
      expect(router.state.location?.search).toBe('')

      // Navigate to closed issues
      await user.click(within(issueNav).getByRole('link', {name: 'Closed Issues (2)'}))

      // Verify closed issues are shown
      expect(
        await within(issueNav).findByRole('link', {name: 'Closed Issues (2)', current: 'page'}),
      ).toBeInTheDocument()
      expect(await within(issueNav).findByRole('link', {name: 'Open Issues (2)', current: false})).toBeInTheDocument()
      expect(within(issueTable).getAllByText(/Closed Issue/)).toHaveLength(2)
      expect(within(issueTable).queryAllByText(/Open Issue/)).toHaveLength(0)
      expect(document.title).toBe('ReactSandboxFuture Dashboard Issues')
      expect(router.state.location?.pathname).toBe('/_react_sandbox_future/dashboard/issues')
      expect(router.state.location?.search).toBe('?state=closed&ignore=true')

      // // Navigate back to open issues
      await user.click(within(issueNav).getByRole('link', {name: 'Open Issues (2)'}))

      // // Verify open issues are shown again
      expect(await within(issueNav).findByRole('link', {name: 'Open Issues (2)', current: 'page'})).toBeInTheDocument()
      expect(within(issueNav).getByRole('link', {name: 'Closed Issues (2)', current: false})).toBeInTheDocument()
      expect(within(issueTable).getAllByText(/Open Issue/)).toHaveLength(2)
      expect(within(issueTable).queryAllByText(/Closed Issue/)).toHaveLength(0)
      expect(document.title).toBe('ReactSandboxFuture Dashboard Issues')
      expect(router.state.location?.pathname).toBe('/_react_sandbox_future/dashboard/issues')
      expect(router.state.location?.search).toBe('?state=open&ignore=true')
    })
  })

  describe('deferred issue error handling', () => {
    const getError = http.get('/_react_sandbox_future/dashboard/issues/deferred', () => {
      return HttpResponse.error()
    })
    const getSuccess = http.get('/_react_sandbox_future/dashboard/issues/deferred', () => {
      const response = getReactSandBoxDashboardIssuesDeferredIssuesPayload({
        state: 'open',
        count: {open: 2, closed: 2},
      })
      return HttpResponse.json(response)
    })

    it('shows an error dialog when there is a server error', async () => {
      server.use(getError)
      const {user} = render(reactSandboxFutureApp, '/_react_sandbox_future/dashboard/issues', {
        embeddedData: getReactSandBoxDashboardIssuesPayload({state: 'open', count: {open: 2, closed: 2}}, false),
      })

      expect(await screen.findByText('Issues for testuser')).toBeInTheDocument()
      const issueTable = await screen.findByTestId('issue-table')

      expect(await screen.findByText('There was a problem loading issues')).toBeInTheDocument()
      expect(within(issueTable).getAllByText('Loading')).toHaveLength(2)

      await user.click(screen.getByText('Dismiss'))

      expect(screen.queryByText('There was a problem loading issues')).not.toBeInTheDocument()
    })

    it('shows an error dialog again with new error', async () => {
      server.use(getError)
      const {user} = render(reactSandboxFutureApp, '/_react_sandbox_future/dashboard/issues', {
        embeddedData: getReactSandBoxDashboardIssuesPayload({state: 'open', count: {open: 2, closed: 2}}, false),
      })

      expect(await screen.findByText('Issues for testuser')).toBeInTheDocument()
      const dashboardNav = await screen.findByTestId('dashboard-nav')

      expect(await screen.findByText('There was a problem loading issues')).toBeInTheDocument()

      await user.click(screen.getByText('Dismiss'))

      expect(screen.queryByText('There was a problem loading issues')).not.toBeInTheDocument()

      await user.click(within(dashboardNav).getByRole('link', {name: 'Issues (2)'}))

      expect(await screen.findByText('There was a problem loading issues')).toBeInTheDocument()
    })

    it('refetches the issues', async () => {
      server.use(getError)
      const {user} = render(reactSandboxFutureApp, '/_react_sandbox_future/dashboard/issues', {
        embeddedData: getReactSandBoxDashboardIssuesPayload({state: 'open', count: {open: 2, closed: 2}}, false),
      })

      expect(await screen.findByText('Issues for testuser')).toBeInTheDocument()
      const issueTable = await screen.findByTestId('issue-table')

      expect(await screen.findByText('There was a problem loading issues')).toBeInTheDocument()

      server.use(getSuccess)
      await user.click(screen.getByText('Retry'))

      expect(await within(issueTable).findAllByText(/Open Issue/)).toHaveLength(2)
    })
  })

  describe('discussions', () => {
    it('shows discussions', async () => {
      const payload = getReactSandBoxDashboardDiscussionsPayload({open: 2, closed: 2}, false)
      render(reactSandboxFutureApp, '/_react_sandbox_future/dashboard/discussions', {
        embeddedData: payload,
      })

      expect(await screen.findByText('Discussions')).toBeInTheDocument()
    })
  })
})
