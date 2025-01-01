import {render} from '@github-ui/react-core/future/test-utils/render'
import {beforeEach, describe, expect, it} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {http, HttpResponse, msw} from '@github-ui/tests/msw'
import {screen, within} from '@testing-library/react'

import {reactCoreExamplesApp} from '../react-core-examples'
import {handlers} from './utils/handlers'
import {getReactCoreExamplesPaginationDeferredPayload, getReactCoreExamplesPaginationPayload} from './utils/mock-data'

describe('ReactCoreExamplesApp Pagination', () => {
  beforeEach(() => {
    msw.use(...handlers)
  })

  it('display issues', async () => {
    const {router} = render(reactCoreExamplesApp, '/_react_core_examples/pagination', {
      embeddedData: getReactCoreExamplesPaginationPayload(),
    })

    const issueNav = await screen.findByTestId('issues-nav')
    const issueTable = await screen.findByTestId('issue-table')
    expect(await within(issueNav).findByRole('link', {name: 'Open Issues (20)'})).toBeInTheDocument()
    expect(within(issueTable).getAllByText(/Open Issue/)).toHaveLength(10)
    expect(router.state.location?.search).toBe('')
  })

  describe('deferred issue error handling', () => {
    const getError = http.get('/_react_core_examples/pagination/deferred', () => {
      return HttpResponse.error()
    })
    const getSuccess = http.get('/_react_core_examples/pagination/deferred', () => {
      const response = getReactCoreExamplesPaginationDeferredPayload()
      return HttpResponse.json(response)
    })

    it('shows an error dialog when there is a server error', async () => {
      msw.use(getError)
      render(reactCoreExamplesApp, '/_react_core_examples/pagination', {
        embeddedData: getReactCoreExamplesPaginationPayload(),
      })

      const issueTable = await screen.findByTestId('issue-table')

      expect(await screen.findByText('There was a problem loading items')).toBeInTheDocument()
      expect(within(issueTable).getAllByText('Loading')).toHaveLength(2)

      await userEvent.click(screen.getByText('Dismiss'))

      expect(screen.queryByText('There was a problem loading items')).not.toBeInTheDocument()
    })

    it('re-fetches the issues', async () => {
      msw.use(getError)
      render(reactCoreExamplesApp, '/_react_core_examples/pagination', {
        embeddedData: getReactCoreExamplesPaginationPayload(),
      })

      const issueTable = await screen.findByTestId('issue-table')

      expect(await screen.findByText('There was a problem loading items')).toBeInTheDocument()

      msw.use(getSuccess)
      await userEvent.click(screen.getByText('Retry'))

      expect(await within(issueTable).findAllByText(/Open Issue/)).toHaveLength(10)
    })
  })

  describe('pagination', () => {
    it('shows the pagination component', async () => {
      const embeddedData = getReactCoreExamplesPaginationPayload()
      const openIssueCount = embeddedData.payload.reactCoreExamplesPaginationRoute.count
      const pageSize = 10
      const pageCount = Math.ceil(openIssueCount / pageSize)
      render(reactCoreExamplesApp, '/_react_core_examples/pagination', {embeddedData})

      const pagination = await screen.findByTestId('pagination')

      expect(await within(pagination).findByRole('link', {name: 'Page 1', current: 'page'})).toBeInTheDocument()
      expect(within(pagination).getAllByRole('link', {name: /Page \d/})).toHaveLength(pageCount)

      await userEvent.click(within(pagination).getByRole('link', {name: 'Page 2', current: false}))
      expect(await within(pagination).findByRole('link', {name: 'Page 2', current: 'page'})).toBeInTheDocument()
    })
  })
})
