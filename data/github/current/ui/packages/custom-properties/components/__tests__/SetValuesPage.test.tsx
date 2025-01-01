import type {OrgCustomPropertiesSetValuesPagePayload} from '@github-ui/custom-properties-types'
import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, expectMockFetchCalledWith, mockFetch} from '@github-ui/mock-fetch'
import {screen, waitFor, within} from '@testing-library/react'

import {sampleOrgSource, sampleRepos} from '../../test-utils/mock-data'
import {renderPropertyDefinitionsComponent} from '../../test-utils/Render'
import {SetValuesPage} from '../SetValuesPage'

jest.mock('@github-ui/sudo', () => ({
  __esModule: true,
  default: async () => true,
}))

jest.setTimeout(10_000)

describe('SetValuesPage', () => {
  it('renders empty experience', async () => {
    setupExpectedAsyncErrorHandler()

    renderSetValuesPage('?tab=set-values&q=chess', {
      ...samplePayload,
      repositories: [],
      repositoryCount: 0,
      pageCount: 1,
    })

    const searchInput = screen.getByRole('combobox')
    await waitFor(() => expect(searchInput).toHaveValue('chess'))

    expect(screen.getByText('No repositories matched your search.')).toBeInTheDocument()
  })

  it('updates to new query', async () => {
    const reposPropertiesEndpoint = '/organizations/acme/settings/custom-properties/list-repos-values?q=find%3Aa&page=1'
    const endpointMock = mockFetch.mockRouteOnce(reposPropertiesEndpoint, {
      pageCount: 1,
      repositoryCount: 0,
      repositories: [],
    })

    const {user} = renderSetValuesPage()

    expect(screen.getByText('33 repositories')).toBeInTheDocument()

    const searchInput = screen.getByRole('combobox')
    await user.click(searchInput)
    await user.paste('find:a')
    expect(searchInput).toHaveValue('find:a')
    await user.keyboard('{Enter}')

    await waitFor(() => expect(endpointMock).toHaveBeenCalledTimes(1))

    expect(window.location.search).toEqual('?tab=set-values&q=find%3Aa')
  })

  it('edit properties with multiple selected repos. selected repos data is updated after edit.', async () => {
    const {user} = renderSetValuesPage()

    mockFetch.mockRoute('/organizations/acme/settings/custom-properties/values')
    mockFetch.mockRouteOnce('/organizations/acme/settings/custom-properties/list-repos-values?q=&page=1', {
      pageCount: 1,
      repositoryCount: 2,
      repositories: newValueRepos,
    })

    expect(screen.queryByRole('button', {name: 'Edit properties'})).not.toBeInTheDocument()

    const counterLabel = screen.getByText(`0 of 2 selected`)
    expect(counterLabel).toBeInTheDocument()

    await user.click(screen.getByLabelText('Select: maximum-effort'))
    expect(counterLabel).toHaveTextContent('1 of 2 selected')

    await user.click(screen.getByLabelText('Select: holly'))
    expect(counterLabel).toHaveTextContent('2 of 2 selected')

    await user.click(screen.getByRole('button', {name: 'Edit properties'}))

    expect(screen.queryAllByText('Set properties on 2 selected repositories')).toHaveLength(2)

    const environmentElement = screen.getByLabelText('environment')
    expect(environmentElement.getAttribute('placeholder')).toEqual('(Mixed)')

    await user.type(environmentElement, 'new_value')

    await user.click(screen.getByText('Save'))
    await screen.findByText('Properties updated successfully.')

    expectMockFetchCalledWith('/organizations/acme/settings/custom-properties/values', {
      repoIds: [0, 1],
      properties: {environment: 'new_value'},
    })

    await waitFor(() =>
      expectMockFetchCalledTimes('/organizations/acme/settings/custom-properties/list-repos-values?q=&page=1', 1),
    )

    await user.click(screen.getByRole('button', {name: 'Edit properties'}))

    expect(screen.getByLabelText('environment')).toHaveValue('new_value')
  })

  it('renders flash banner on edit success and clears when editing repo', async () => {
    mockFetch.mockRouteOnce('/organizations/acme/settings/custom-properties/list-repos-values?page=1', {
      pageCount: 1,
      repositoryCount: 1,
      repositories: sampleRepos,
    })

    mockFetch.mockRouteOnce('/organizations/acme/settings/custom-properties/values')

    const {user} = renderSetValuesPage()

    const repo = sampleRepos[0]!
    await user.click(screen.getByRole('button', {name: `Edit ${repo.name}'s properties`}))
    await user.type(screen.getByLabelText('something'), '2.0')
    await user.click(screen.getByText('Save'))

    await screen.findByText('Properties updated successfully.')
    expectMockFetchCalledWith(
      '/organizations/acme/settings/custom-properties/values',
      {
        repoIds: [repo.id],
        properties: {something: '2.0'},
      },
      'equal',
    )

    await user.click(screen.getByRole('button', {name: `Edit ${repo.name}'s properties`}))
    expect(screen.queryByText('Properties updated successfully.')).not.toBeInTheDocument()
  })

  it('renders flash banner on edit failure', async () => {
    mockFetch.mockRouteOnce('/organizations/acme/settings/custom-properties/list-repos-values?page=1', {
      pageCount: 1,
      repositoryCount: 1,
      repositories: sampleRepos,
    })

    mockFetch.mockRouteOnce('/organizations/acme/settings/custom-properties/values', undefined, {
      ok: false,
      json: () => Promise.resolve({error: 'something went wrong'}),
    })

    const {user} = renderSetValuesPage()

    const repo = sampleRepos[0]!
    await user.click(screen.getByRole('button', {name: `Edit ${repo.name}'s properties`}))
    await user.type(screen.getByLabelText('something'), '2.0')
    await user.click(screen.getByRole('button', {name: 'Save'}))

    await screen.findByText('something went wrong')
    expectMockFetchCalledWith(
      '/organizations/acme/settings/custom-properties/values',
      {
        repoIds: [repo.id],
        properties: {something: '2.0'},
      },
      'equal',
    )
  })

  describe('properties editing page', () => {
    it('all properties are rendered with editable controls', async () => {
      const {user} = renderSetValuesPage()

      await user.click(screen.getByLabelText("Edit maximum-effort's properties"))

      const editingForm = screen.getByTestId('properties-editing-page')
      expect(editingForm).toBeInTheDocument()
      expect(within(editingForm).queryAllByTestId('readonly-property-name')).toHaveLength(0)
      expect(within(editingForm).getAllByTestId('property-name')).toHaveLength(samplePayload.definitions.length)
    })

    it('dismissed page on breadcrumb click', async () => {
      const {user} = renderSetValuesPage()

      await user.click(screen.getByLabelText("Edit maximum-effort's properties"))

      expect(screen.getByTestId('properties-editing-page')).toBeInTheDocument()
      await user.click(screen.getByRole('link', {name: 'Custom properties'}))

      expect(screen.queryByTestId('properties-editing-page')).not.toBeInTheDocument()
    })

    it('when edit page is open, focus is set on the go-back link', async () => {
      const {user} = renderSetValuesPage()

      await user.click(screen.getByLabelText("Edit maximum-effort's properties"))

      expect(screen.getByTestId('properties-editing-page')).toBeInTheDocument()
      expect(screen.getByRole('link', {name: 'Custom properties'})).toHaveFocus()
    })
  })

  describe('list interactions', () => {
    it('selects / deselect all repos on the page', async () => {
      const {user} = renderSetValuesPage()

      const selectAllCheckbox = within(screen.getByTestId('list-view-select-all-container')).getByRole('checkbox')
      await user.click(selectAllCheckbox)
      expect(screen.getByText('2 of 2 selected')).toBeInTheDocument()

      await user.click(selectAllCheckbox)
      await waitFor(() => expect(screen.queryByText(/3 of 3 selected/)).not.toBeInTheDocument())
    })

    it('renders header checkbox in indeterminate state if not all repos are selected', async () => {
      const {user} = renderSetValuesPage()

      await user.click(screen.getByLabelText(`Select: maximum-effort`))
      expect(screen.getByText('1 of 2 selected')).toBeInTheDocument()

      const selectAllCheckbox = within(screen.getByTestId('list-view-select-all-container')).getByRole('checkbox')
      expect(selectAllCheckbox).toBePartiallyChecked()
    })
  })
})

const samplePayload: OrgCustomPropertiesSetValuesPagePayload = {
  ownDefinitionsCount: 2,
  activeTab: 'set-values',
  definitions: [
    {
      propertyName: 'something',
      valueType: 'string',
      required: false,
      defaultValue: null,
      description: 'a test description',
      allowedValues: null,
      valuesEditableBy: 'org_actors',
      regex: null,
      source: sampleOrgSource,
    },
    {
      propertyName: 'environment',
      valueType: 'string',
      description: null,
      required: false,
      defaultValue: null,
      allowedValues: null,
      valuesEditableBy: 'org_actors',
      regex: null,
      source: sampleOrgSource,
    },
  ],
  pageCount: 1,
  repositoryCount: 33,
  repositories: sampleRepos.slice(0, 2),
  permissions: 'all',
}

const newValueRepos = sampleRepos
  .slice(0, 2)
  .map(repo => ({...repo, properties: {...repo.properties, environment: 'new_value'}}))

function renderSetValuesPage(search = '?tab=set-values', routePayload = samplePayload) {
  return renderPropertyDefinitionsComponent(<SetValuesPage />, {
    search,
    routePayload,
  })
}
