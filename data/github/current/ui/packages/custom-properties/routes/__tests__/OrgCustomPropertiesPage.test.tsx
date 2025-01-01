import type {
  OrgCustomPropertiesListPagePayload,
  OrgCustomPropertiesSetValuesPagePayload,
  OrgEditPermissions,
  PropertyDefinition,
} from '@github-ui/custom-properties-types'
import {screen} from '@testing-library/react'

import {sampleRepos} from '../../test-utils/mock-data'
import {renderPropertyDefinitionsComponent} from '../../test-utils/Render'
import {OrgCustomPropertiesPage} from '../OrgCustomPropertiesPage'

let paramsMock = new URLSearchParams()
jest.mock('react-router-dom', () => {
  const originalModule = jest.requireActual('react-router-dom')
  return {
    ...originalModule,
    useSearchParams: jest.fn().mockImplementation(() => {
      return [paramsMock, jest.fn()]
    }),
  }
})

const sampleStringDefinition: PropertyDefinition = {
  propertyName: ``,
  valueType: 'string',
  description: null,
  required: false,
  defaultValue: null,
  allowedValues: null,
  valuesEditableBy: 'org_actors',
  regex: null,
  sourceType: 'org',
}

const baseRoutePayload: {
  definitions: PropertyDefinition[]
  permissions: OrgEditPermissions
  ownDefinitionsCount: number
} = {
  ownDefinitionsCount: 2,
  definitions: [
    {
      ...sampleStringDefinition,
      propertyName: 'album',
    },
    {
      ...sampleStringDefinition,
      propertyName: 'band',
    },
  ],
  permissions: 'all',
}

const listRoutePayload: OrgCustomPropertiesListPagePayload = {
  ...baseRoutePayload,
  activeTab: 'properties',
  totalCount: baseRoutePayload.definitions.length,
  pageCount: 1,
}

const setValuesRoutePayload: OrgCustomPropertiesSetValuesPagePayload = {
  ...baseRoutePayload,
  activeTab: 'set-values',
  repositories: sampleRepos,
  repositoryCount: sampleRepos.length,
  pageCount: 1,
}

beforeEach(() => {
  paramsMock = new URLSearchParams()
})

describe('CustomPropertiesSchemaPage', () => {
  it('shows definitions limit banner if limit is reached', async () => {
    const payload: OrgCustomPropertiesListPagePayload = {
      ...listRoutePayload,
      ownDefinitionsCount: 100,
      totalCount: 100,
    }

    renderPropertyDefinitionsComponent(<OrgCustomPropertiesPage />, {routePayload: payload})

    screen.getByText('100 properties')
    screen.getByText('The limit of 100 definitions is reached. You cannot add more.')
    expect(screen.queryByTestId('add-definition-button')).not.toBeInTheDocument()
  })

  it('does not show definitions limit banner if limit is not reached', () => {
    const payload: OrgCustomPropertiesListPagePayload = {
      ...listRoutePayload,
      ownDefinitionsCount: 99,
      totalCount: 199,
    }

    renderPropertyDefinitionsComponent(<OrgCustomPropertiesPage />, {routePayload: payload})

    screen.getByText('199 properties')
    expect(screen.queryByText('The limit of 100 definitions is reached. You cannot add more.')).not.toBeInTheDocument()
    expect(screen.getByTestId('add-definition-button')).toBeInTheDocument()
  })

  it('renders page tabs if user has both permissions', async () => {
    renderPropertyDefinitionsComponent(<OrgCustomPropertiesPage />, {routePayload: listRoutePayload})

    expect(screen.getByRole('navigation', {name: 'Page selector'})).toBeInTheDocument()
  })

  it('tabs contain correct urls if user has both permissions', async () => {
    renderPropertyDefinitionsComponent(<OrgCustomPropertiesPage />, {routePayload: listRoutePayload})

    expect(screen.getByText('album')).toBeInTheDocument()
    expect(screen.getByText('band')).toBeInTheDocument()

    expect(screen.queryByTestId('repos-properties-list')).not.toBeInTheDocument()

    expect(screen.getByRole('link', {name: 'Set values'}).getAttribute('href')).toEqual(
      '/organizations/acme/settings/custom-properties?tab=set-values',
    )
    expect(screen.getByRole('link', {name: 'Properties (2)'}).getAttribute('href')).toEqual(
      '/organizations/acme/settings/custom-properties?tab=properties',
    )
  })

  it('renders correct initial tab if user has both permissions', async () => {
    paramsMock.set('tab', 'set-values')
    renderPropertyDefinitionsComponent(<OrgCustomPropertiesPage />, {
      routePayload: setValuesRoutePayload,
      search: '?tab=set-values',
    })

    expect(screen.queryByText('album')).not.toBeInTheDocument()
    expect(screen.queryByText('band')).not.toBeInTheDocument()

    expect(screen.getByTestId('repos-properties-list')).toBeInTheDocument()
  })

  it('renders tab based on the payload and not URL', async () => {
    paramsMock.set('tab', 'set-values')
    renderPropertyDefinitionsComponent(<OrgCustomPropertiesPage />, {
      routePayload: {...listRoutePayload, permissions: 'definitions'},
      search: '?tab=set-values',
    })

    expect(screen.queryByRole('navigation', {name: 'Page selector'})).not.toBeInTheDocument()

    expect(screen.getByTestId('repos-definitions-list')).toBeInTheDocument()
  })
})
