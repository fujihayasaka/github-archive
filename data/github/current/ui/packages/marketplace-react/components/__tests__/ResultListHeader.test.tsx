import {screen} from '@testing-library/react'
import {getIndexRoutePayload} from '@github-ui/marketplace-common/mock-data'
import type {IndexPayload} from '@github-ui/marketplace-common'
import {renderWithFilterContext} from '@github-ui/marketplace-common/test-utils'
import {ResultListHeader} from '../ResultListHeader'

jest.mock('@github-ui/use-navigate')

const renderComponent = (searchResults: IndexPayload['searchResults']) => {
  renderWithFilterContext(<ResultListHeader categories={getIndexRoutePayload().categories} />, {searchResults})
}

describe('ResultListHeader', () => {
  beforeEach(() => {
    const {useSearchParams} = jest.requireMock('@github-ui/use-navigate')
    useSearchParams.mockImplementation(() => [new URLSearchParams(), jest.fn()])
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  test('Renders the search heading when searching', () => {
    const {useSearchParams} = jest.requireMock('@github-ui/use-navigate')
    const params = new URLSearchParams()
    params.set('query', 'something sort:created-desc')
    useSearchParams.mockImplementation(() => [params, jest.fn()])
    renderComponent(getIndexRoutePayload().searchResults)

    expect(screen.getByTestId('heading-text')).toHaveTextContent('Search results for “something”')
    expect(screen.getByTestId('detail-text')).toHaveTextContent('10 results')
  })

  test('Renders the copilot heading when copilot_app is in the params', () => {
    const {useSearchParams} = jest.requireMock('@github-ui/use-navigate')
    const params = new URLSearchParams()
    params.set('copilot_app', 'true')
    useSearchParams.mockImplementation(() => [params, jest.fn()])
    renderComponent(getIndexRoutePayload().searchResults)

    expect(screen.getByTestId('heading-text')).toHaveTextContent('Copilot Extensions')
    expect(screen.getByTestId('detail-text')).toHaveTextContent(
      'Extend Copilot capabilities using third party tools, services, and data',
    )
  })

  test('Renders the models heading when models type is in the params', () => {
    const {useSearchParams} = jest.requireMock('@github-ui/use-navigate')
    const params = new URLSearchParams()
    params.set('type', 'models')
    useSearchParams.mockImplementation(() => [params, jest.fn()])
    renderComponent(getIndexRoutePayload().searchResults)

    expect(screen.getByTestId('heading-text')).toHaveTextContent('Models')
    expect(screen.getByTestId('detail-text')).toHaveTextContent(
      'Create applications with GitHub powered by AI Models. Free to use, quick personal setup, and seamless model switching to help you build AI products using the latest models.',
    )
  })

  test('Renders the category heading when a category and app type is in the params', () => {
    const {useSearchParams} = jest.requireMock('@github-ui/use-navigate')
    const params = new URLSearchParams()
    params.set('category', 'mock-category')
    params.set('type', 'apps')
    useSearchParams.mockImplementation(() => [params, jest.fn()])
    renderComponent(getIndexRoutePayload().searchResults)

    expect(screen.getByTestId('heading-text')).toHaveTextContent('Mock Category apps')
    expect(screen.getByTestId('detail-text')).toHaveTextContent('This is a description') // From the category mock
  })

  test('Renders the action category heading when a category and action type is in the params', () => {
    const {useSearchParams} = jest.requireMock('@github-ui/use-navigate')
    const params = new URLSearchParams()
    params.set('category', 'mock-category')
    params.set('type', 'actions')
    useSearchParams.mockImplementation(() => [params, jest.fn()])
    renderComponent(getIndexRoutePayload().searchResults)

    expect(screen.getByTestId('heading-text')).toHaveTextContent('Mock Category actions')
    expect(screen.getByTestId('detail-text')).toHaveTextContent('This is a description') // From the category mock
  })

  test('Renders the action heading when the app type is in the params', () => {
    const {useSearchParams} = jest.requireMock('@github-ui/use-navigate')
    const params = new URLSearchParams()
    params.set('type', 'apps')
    useSearchParams.mockImplementation(() => [params, jest.fn()])
    renderComponent(getIndexRoutePayload().searchResults)

    expect(screen.getByTestId('heading-text')).toHaveTextContent('Apps')
    expect(screen.getByTestId('detail-text')).toHaveTextContent(
      'Build on your workflow with apps that integrate with GitHub',
    )
  })

  test('Renders the action heading when the action type is in the params', () => {
    const {useSearchParams} = jest.requireMock('@github-ui/use-navigate')
    const params = new URLSearchParams()
    params.set('type', 'actions')
    useSearchParams.mockImplementation(() => [params, jest.fn()])
    renderComponent(getIndexRoutePayload().searchResults)

    expect(screen.getByTestId('heading-text')).toHaveTextContent('Actions')
    expect(screen.getByTestId('detail-text')).toHaveTextContent('Automate your workflow from idea to production')
  })
})
