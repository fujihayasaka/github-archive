import type {OrgCustomPropertiesListPagePayload} from '@github-ui/custom-properties-types'
import {mockFetch} from '@github-ui/mock-fetch'
import {screen, waitFor, within} from '@testing-library/react'

import {
  renderPropertyDefinitionsComponent,
  renderPropertyDefinitionsComponentAtEnterpriseLevel,
} from '../../test-utils/Render'
import {OrgCustomPropertiesListPage} from '../OrgCustomPropertiesListPage'

// Mock the following properties to avoid focus errors for ListView
beforeAll(() => {
  Object.defineProperties(HTMLElement.prototype, {
    offsetHeight: {get: () => 42},
    offsetWidth: {get: () => 42},
    getClientRects: {get: () => () => [42]},
    offsetParent: {get: () => true},
  })
})

const routePayload: OrgCustomPropertiesListPagePayload = {
  ownDefinitionsCount: 2,
  activeTab: 'properties',
  definitions: [
    {
      propertyName: 'definitionA',
      valueType: 'single_select',
      description: null,
      allowedValues: ['red', 'green', 'blue'],
      required: false,
      defaultValue: null,
      valuesEditableBy: 'org_actors',
      regex: null,
      sourceType: 'org',
    },
    {
      propertyName: 'definitionB',
      valueType: 'string',
      required: true,
      defaultValue: 'default',
      description: null,
      allowedValues: null,
      valuesEditableBy: 'org_actors',
      regex: null,
      sourceType: 'business',
    },
  ],
  permissions: 'all',
  totalCount: 2,
  pageCount: 1,
  business: {
    name: 'GitHub',
    slug: 'github',
  },
}

jest.useFakeTimers()

describe('OrgCustomPropertiesListPage', () => {
  it('renders correctly', () => {
    renderPropertyDefinitionsComponent(<OrgCustomPropertiesListPage />, {
      routePayload,
    })

    const listItems = within(screen.getByTestId('list-view-items')).getAllByRole('listitem')

    expect(listItems[0]?.textContent).toContain('definitionA')
    expect(listItems[0]?.textContent).toContain('Single select')

    expect(listItems[1]?.textContent).toContain('definitionB')
    expect(listItems[1]?.textContent).toContain('Text')
  })

  it('renders empty state', () => {
    renderPropertyDefinitionsComponent(<OrgCustomPropertiesListPage />, {
      routePayload: {
        definitions: [],
        permissions: 'all',
      },
    })

    expect(screen.getByText('No properties have been found')).toBeInTheDocument()
  })

  it('renders managed by badge for enterprise properties at the org level', () => {
    renderPropertyDefinitionsComponent(<OrgCustomPropertiesListPage />, {
      routePayload,
    })

    expect(screen.getByTestId('definitionB-managed-by-label')).toHaveTextContent('Managed by GitHub')
    expect(screen.queryByTestId('definitionA-managed-by-label')).not.toBeInTheDocument()
  })

  it('does not render managed by labels for enterprise level', () => {
    renderPropertyDefinitionsComponentAtEnterpriseLevel(<OrgCustomPropertiesListPage />, {
      routePayload,
    })

    expect(screen.queryByTestId('definitionA-managed-by-label')).not.toBeInTheDocument()
    expect(screen.queryByTestId('definitionB-managed-by-label')).not.toBeInTheDocument()
  })

  it('can filter', async () => {
    const routeMock = mockFetch.mockRoute(/custom-properties/)

    const {user} = renderPropertyDefinitionsComponentAtEnterpriseLevel(<OrgCustomPropertiesListPage />, {
      routePayload,
      appPayload: {['enabled_features']: {['enterprise_custom_properties_list']: true}},
    })

    const input = screen.getByRole('combobox', {name: 'Filter properties'})
    await user.type(input, 'term{Enter}')

    await waitFor(() =>
      expect(routeMock).toHaveBeenCalledWith(
        '/enterprises/acme-corp/settings/custom-properties?page=1&q=term',
        expect.any(Object),
      ),
    )
  })

  it('can paginate', async () => {
    const routeMock = mockFetch.mockRoute(/custom-properties/)

    const {user} = renderPropertyDefinitionsComponentAtEnterpriseLevel(<OrgCustomPropertiesListPage />, {
      routePayload: {
        ...routePayload,
        pageCount: 2,
      },
      appPayload: {['enabled_features']: {['enterprise_custom_properties_list']: true}},
    })

    const page1 = screen.getByLabelText('Page 1')
    const page2 = screen.getByLabelText('Page 2...')
    expect(page1).toBeInTheDocument()
    expect(page2).toBeInTheDocument()

    await user.click(page2)

    await waitFor(() =>
      expect(routeMock).toHaveBeenCalledWith(
        '/enterprises/acme-corp/settings/custom-properties?page=2&q=',
        expect.any(Object),
      ),
    )
  })

  it('hides filter and pagination if FF is disabled', async () => {
    renderPropertyDefinitionsComponentAtEnterpriseLevel(<OrgCustomPropertiesListPage />, {
      routePayload: {
        ...routePayload,
        definitions: Array.from({length: 32}, (_, i) => ({
          propertyName: `definition-${i}`,
          valueType: 'string',
          required: false,
          valuesEditableBy: 'org_actors',
          sourceType: 'org',
        })),
      },
      appPayload: {['enabled_features']: {['enterprise_custom_properties_list']: false}},
    })

    expect(screen.queryByLabelText('Pagination')).not.toBeInTheDocument()
    expect(screen.queryByRole('combobox', {name: 'Filter properties'})).not.toBeInTheDocument()

    expect(within(screen.getByTestId('list-view-items')).getAllByRole('listitem')).toHaveLength(32)
  })

  it('announces list total count', async () => {
    renderPropertyDefinitionsComponent(<OrgCustomPropertiesListPage />, {routePayload})

    await jest.runOnlyPendingTimersAsync()
    expect(screen.getByTestId('sr-message')).toHaveTextContent('2 properties found.')
  })
})
