import type {BusinessCustomPropertiesDefinitionsPagePayload} from '@github-ui/custom-properties-types'
import {mockFetch} from '@github-ui/mock-fetch'
import {screen, waitFor} from '@testing-library/react'

import {sampleOrgSource} from '../../test-utils/mock-data'
import {renderPropertyDefinitionsComponentAtEnterpriseLevel} from '../../test-utils/Render'
import {BusinessCustomPropertiesPage} from '../BusinessCustomPropertiesPage'

const routePayload: BusinessCustomPropertiesDefinitionsPagePayload = {
  currentQ: '',
  ownDefinitionsCount: 1,
  definitions: [
    {
      propertyName: 'album',
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
  totalCount: 1_000,
  pageCount: 2,
}

const fetchedPayload = {
  ...routePayload,
  definitions: [
    {
      ...routePayload.definitions[0],
      propertyName: 'fetched_property',
    },
  ],
}

const appPayload = {
  ['enabled_features']: {['enterprise_custom_properties_list']: true},
}

describe('BusinessCustomPropertiesPage', () => {
  beforeEach(() => {
    jest.spyOn(console, 'error').mockImplementation((message: string) => {
      // * Because Filter is asynchronous, there are console errors that are thrown, but expected. This will rethrow
      // * any errors that are not related to the async nature of the component.
      if (!message.includes?.('wrapped in act(')) {
        // eslint-disable-next-line no-console
        console.error(message)
      }
    })
  })

  afterEach(() => {
    jest.restoreAllMocks()
  })

  it('fetches with query on filter submit', async () => {
    const {user} = renderPropertyDefinitionsComponentAtEnterpriseLevel(<BusinessCustomPropertiesPage />, {
      routePayload,
      appPayload,
    })

    const routeMock = mockFetch.mockRouteOnce('/enterprises/acme-corp/settings/custom-properties?page=1&q=env', {
      payload: fetchedPayload,
    })

    const filterTextInput = screen.getByRole('combobox', {name: 'Filter properties'})

    await user.type(filterTextInput, 'env{enter}')

    await waitFor(() => expect(routeMock).toHaveBeenCalled())
    await screen.findByText('fetched_property')
  })

  it('syncs q with the payload', async () => {
    renderPropertyDefinitionsComponentAtEnterpriseLevel(<BusinessCustomPropertiesPage />, {
      routePayload: {...routePayload, currentQ: 'value from payload'},
      appPayload,
    })

    const filterTextInput = screen.getByRole('combobox', {name: 'Filter properties'})
    await waitFor(() => expect(filterTextInput).toHaveValue('value from payload'))
  })

  it('renders pagination and total count', async () => {
    const routeMock = mockFetch.mockRouteOnce('/enterprises/acme-corp/settings/custom-properties?page=2&q=', {
      payload: fetchedPayload,
    })

    const {user} = renderPropertyDefinitionsComponentAtEnterpriseLevel(<BusinessCustomPropertiesPage />, {
      routePayload,
      appPayload,
    })

    expect(screen.getByText('1,000 properties')).toBeInTheDocument()
    expect(screen.getByLabelText('Pagination')).toBeInTheDocument()
    expect(screen.getByText('album')).toBeInTheDocument()

    await user.click(screen.getByLabelText('Next Page'))

    await waitFor(() => expect(routeMock).toHaveBeenCalled())
    await screen.findByText('fetched_property')
  })

  it('hides pagination if there is only one page', async () => {
    renderPropertyDefinitionsComponentAtEnterpriseLevel(<BusinessCustomPropertiesPage />, {
      routePayload: {...routePayload, pageCount: 1},
      appPayload,
    })

    expect(screen.queryByLabelText('Pagination')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Next Page')).not.toBeInTheDocument()
  })

  it('hides pagination if `enterprise_custom_properties_list` FF is disabled', async () => {
    renderPropertyDefinitionsComponentAtEnterpriseLevel(<BusinessCustomPropertiesPage />, {routePayload})

    expect(screen.getByText('1,000 properties')).toBeInTheDocument()
    expect(screen.queryByLabelText('Pagination')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Next Page')).not.toBeInTheDocument()
  })

  it('announces list total count', async () => {
    renderPropertyDefinitionsComponentAtEnterpriseLevel(<BusinessCustomPropertiesPage />, {routePayload})

    await waitFor(() => {
      expect(screen.getByTestId('sr-message')).toHaveTextContent('1000 properties found.')
    })
  })
})
